package com.ahmadhussain.ble_keeper.gatt

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.ahmadhussain.ble_keeper.KeeperConstants
import com.ahmadhussain.ble_keeper.PBlockedReason
import com.ahmadhussain.ble_keeper.PDisconnectReason
import com.ahmadhussain.ble_keeper.PEvent
import com.ahmadhussain.ble_keeper.core.CharRef
import com.ahmadhussain.ble_keeper.core.Events
import com.ahmadhussain.ble_keeper.core.KeeperException
import com.ahmadhussain.ble_keeper.core.Session
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.android.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

/**
 * Owns the GATT connection to one device and keeps it alive.
 *
 * Threading: all state lives on [handler]'s thread (one HandlerThread per
 * service, shared by all devices). On API 33+ connectGatt delivers callbacks
 * on that handler; below 33 they arrive on binder threads and are re-posted
 * to it (see connectGattCompat). Suspend functions hop to the handler
 * dispatcher.
 *
 * Reconnect: see [ConnectStrategy]. Direct connects (autoConnect = false)
 * first, because autoConnect = true only reliably finds devices the stack has
 * seen; autoConnect = true after the first success or after a few minutes of
 * failed direct attempts, so an absent device does not drain the battery.
 * autoConnect has no timeout; a watchdog recreates one that has been pending
 * for a long time. The attempt counter resets only after a link stayed up
 * for 30 s, so a link that keeps dropping right after setup backs off.
 * After any disconnect the BluetoothGatt is closed and a new one created;
 * reusing a disconnected object behaves differently across vendors.
 */
@SuppressLint("MissingPermission") // BLUETOOTH_CONNECT is checked before the service starts.
internal class GattManager(
    private val context: Context,
    private val adapter: BluetoothAdapter,
    initialSession: Session,
    private val handler: Handler,
    private val emit: (PEvent) -> Unit,
    private val note: (deviceId: String, text: String) -> Unit,
    private val backoff: BackoffPolicy = BackoffPolicy(),
) {
    private enum class State { IDLE, CONNECTING, DISCOVERING, SUBSCRIBING, READY, WAITING, BLUETOOTH_OFF, STOPPED }

    private val dispatcher = handler.asCoroutineDispatcher()
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val queue = GattOperationQueue()
    private val reportedProblems = mutableSetOf<String>()

    @Volatile
    var session: Session = initialSession
        private set
    val deviceId: String get() = session.deviceId

    private var state = State.IDLE
    private var gatt: BluetoothGatt? = null
    private var attempt = 0
    private val strategy = ConnectStrategy()
    private var lastAttemptAuto = false
    private var readyAtMs: Long? = null
    private var watchdogJob: Job? = null

    /** Connected was emitted for the current link; Disconnected pairs with it. */
    private var connectedEmitted = false
    private var localDisconnect = false
    private var mtu = KeeperConstants.DEFAULT_MTU
    private var reconnectJob: Job? = null
    private var setupJob: Job? = null

    private val linkUp get() = state == State.DISCOVERING || state == State.SUBSCRIBING || state == State.READY

    fun start() = onGattThread {
        if (state != State.IDLE) return@onGattThread
        if (adapter.isEnabled) connect() else state = State.BLUETOOTH_OFF
    }

    fun update(newSession: Session) = onGattThread {
        val added = newSession.subscribe - session.subscribe.toSet()
        session = newSession
        val g = gatt
        if (state == State.READY && g != null && added.isNotEmpty()) {
            setupJob = scope.launch { runSetupStep(g) { subscribeAll(g, added) } }
        }
    }

    fun stop() = onGattThread {
        if (state == State.STOPPED) return@onGattThread
        val wasConnected = connectedEmitted
        connectedEmitted = false
        state = State.STOPPED
        reconnectJob?.cancel()
        setupJob?.cancel()
        watchdogJob?.cancel()
        queue.close(KeeperException("not_connected", "stopped"))
        gatt?.let {
            it.disconnect()
            it.close()
        }
        gatt = null
        if (wasConnected) emit(Events.disconnected(deviceId, PDisconnectReason.STOPPED, null))
        scope.cancel()
    }

    /**
     * When Bluetooth turns off every BluetoothGatt becomes invalid and must be
     * closed; it does not recover by itself when Bluetooth comes back.
     */
    fun onBluetoothOff() = onGattThread {
        if (state == State.STOPPED || state == State.BLUETOOTH_OFF) return@onGattThread
        val wasConnected = connectedEmitted
        connectedEmitted = false
        readyAtMs = null
        reconnectJob?.cancel()
        setupJob?.cancel()
        watchdogJob?.cancel()
        strategy.onBluetoothOff()
        queue.close(KeeperException("bluetooth_off", "Bluetooth is off"))
        gatt?.close()
        gatt = null
        if (wasConnected) emit(Events.disconnected(deviceId, PDisconnectReason.BLUETOOTH_OFF, null))
        state = State.BLUETOOTH_OFF
    }

    fun onBluetoothOn() = onGattThread {
        if (state != State.BLUETOOTH_OFF) return@onGattThread
        attempt = 0
        connect()
    }

    suspend fun read(c: CharRef): ByteArray = withContext(dispatcher) {
        val g = readyGatt()
        val ch = findOrThrow(g, c)
        if (ch.properties and BluetoothGattCharacteristic.PROPERTY_READ == 0) {
            throw KeeperException("read_unsupported", "${c.characteristic} does not support read")
        }
        dropLinkOnTimeout(g) { queue.execute<ByteArray>(OP_READ) { g.readCharacteristic(ch) } }
    }

    suspend fun write(c: CharRef, value: ByteArray, withResponse: Boolean) = withContext(dispatcher) {
        val g = readyGatt()
        val ch = findOrThrow(g, c)
        // Write without response must fit one ATT packet (MTU - 3). Write with
        // response may be a long write (prepare/execute), up to the 512-byte
        // attribute limit (Core Spec Vol 3, Part F, 3.2.9).
        val max = if (withResponse) MAX_ATTRIBUTE_LENGTH else mtu - 3
        if (value.size > max) {
            throw KeeperException("payload_too_large", "${value.size} bytes exceeds $max (MTU $mtu)")
        }
        val needed = if (withResponse) {
            BluetoothGattCharacteristic.PROPERTY_WRITE
        } else {
            BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
        }
        if (ch.properties and needed == 0) {
            throw KeeperException(
                "write_type_unsupported",
                "${c.characteristic} does not support write ${if (withResponse) "with" else "without"} response",
            )
        }
        val type = if (withResponse) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }
        dropLinkOnTimeout(g) { queue.execute<Unit>(OP_WRITE) { writeCharacteristicCompat(g, ch, value, type) } }
    }

    /**
     * A GATT callback that never arrives leaves the stack's own busy flag set,
     * so every later operation would be rejected. Reconnecting clears it.
     */
    private suspend fun <T> dropLinkOnTimeout(g: BluetoothGatt, op: suspend () -> T): T =
        try {
            op()
        } catch (e: KeeperException) {
            if (e.code == "timeout" && g === gatt) dropLink(g, "operation timed out")
            throw e
        }

    private fun connect() {
        if (state == State.STOPPED) return
        val device = try {
            adapter.getRemoteDevice(deviceId)
        } catch (e: IllegalArgumentException) {
            emit(Events.blocked(PBlockedReason.MISCONFIGURED, deviceId, "invalid Bluetooth address"))
            state = State.STOPPED
            return
        }
        queue.reopen()
        localDisconnect = false
        state = State.CONNECTING
        val now = SystemClock.elapsedRealtime()
        val auto = strategy.useAutoConnect(now)
        strategy.onAttempt(auto, now)
        lastAttemptAuto = auto
        val g = connectGattCompat(device, autoConnect = auto)
        gatt = g
        if (g == null) {
            strategy.onConnectFailed(auto)
            scheduleReconnect(GattStatus.GATT_ERROR, stableLink = false)
            return
        }
        if (auto) armWatchdog(g)
    }

    private fun armWatchdog(g: BluetoothGatt) {
        watchdogJob?.cancel()
        watchdogJob = scope.launch {
            delay(strategy.autoConnectWatchdogMs)
            if (state == State.CONNECTING && gatt === g) {
                note(deviceId, "autoConnect pending for ${strategy.autoConnectWatchdogMs / 60_000} min, recreating it")
                g.close()
                gatt = null
                connect()
            }
        }
    }

    /**
     * The handler overload exists from API 26, but below API 33 the framework
     * stores a notification in the shared characteristic object on the binder
     * thread before posting the callback to the handler, so two fast
     * notifications can both read the second value. Below 33 the callback
     * therefore runs on the binder thread, copies the value at once and
     * re-posts (see onCharacteristicChanged).
     */
    private fun connectGattCompat(device: BluetoothDevice, autoConnect: Boolean): BluetoothGatt? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            device.connectGatt(
                context,
                autoConnect,
                callback,
                BluetoothDevice.TRANSPORT_LE,
                BluetoothDevice.PHY_LE_1M_MASK,
                handler,
            )
        } else {
            device.connectGatt(context, autoConnect, callback, BluetoothDevice.TRANSPORT_LE)
        }

    private fun handleConnectionState(g: BluetoothGatt, status: Int, newState: Int) {
        if (g !== gatt) {
            // Callback for an object from an earlier attempt.
            g.close()
            return
        }
        if (newState == BluetoothProfile.STATE_CONNECTED && status == GattStatus.SUCCESS) {
            // Some stacks report CONNECTED twice; a second setup would run two
            // discoveries and subscriptions in parallel.
            if (state != State.CONNECTING) {
                note(deviceId, "ignoring CONNECTED in state $state")
                return
            }
            watchdogJob?.cancel()
            strategy.onConnected()
            state = State.DISCOVERING
            setupJob?.cancel()
            setupJob = scope.launch { runSetupStep(g) { setup(g) } }
        } else if (newState == BluetoothProfile.STATE_DISCONNECTED || status != GattStatus.SUCCESS) {
            onDisconnected(g, status)
        }
    }

    private suspend fun setup(g: BluetoothGatt) {
        queue.execute<Unit>(OP_DISCOVER) { g.discoverServices() }
        mtu = try {
            queue.execute<Int>(OP_MTU) { g.requestMtu(KeeperConstants.MAX_MTU) }
        } catch (e: KeeperException) {
            KeeperConstants.DEFAULT_MTU
        }
        state = State.SUBSCRIBING
        subscribeAll(g, session.subscribe)
        state = State.READY
        readyAtMs = SystemClock.elapsedRealtime()
        // Not again after a service-change rediscovery on the same link.
        if (!connectedEmitted) {
            connectedEmitted = true
            emit(Events.connected(deviceId))
        }
    }

    /** Runs a setup step; on failure drops the link so the reconnect loop starts over. */
    private suspend fun runSetupStep(g: BluetoothGatt, step: suspend () -> Unit) {
        try {
            step()
        } catch (e: KeeperException) {
            dropLink(g, "setup failed: ${e.code} ${e.message}")
        }
    }

    private fun dropLink(g: BluetoothGatt, reason: String) {
        if (state == State.STOPPED || g !== gatt) return
        note(deviceId, reason)
        localDisconnect = true
        g.disconnect()
        onDisconnected(g, GattStatus.LOCAL_HOST_TERMINATED)
    }

    private suspend fun subscribeAll(g: BluetoothGatt, chars: List<CharRef>) {
        for (c in chars) {
            val ch = find(g, c)
            if (ch == null) {
                reportOnce(c, "characteristic ${c.characteristic} not found in service ${c.service}")
                continue
            }
            val props = ch.properties
            val value = when {
                props and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0 ->
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                props and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0 ->
                    BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                else -> {
                    reportOnce(c, "characteristic ${c.characteristic} supports neither notify nor indicate")
                    continue
                }
            }
            // Enables local delivery of notifications; the peripheral only
            // sends them after the CCCD write below.
            if (!g.setCharacteristicNotification(ch, true)) {
                throw KeeperException("gatt_error", "setCharacteristicNotification failed for ${c.characteristic}")
            }
            val cccd = ch.getDescriptor(UUID.fromString(KeeperConstants.CCCD_UUID))
            if (cccd == null) {
                reportOnce(c, "characteristic ${c.characteristic} has no CCCD descriptor")
                continue
            }
            queue.execute<Unit>(OP_CCCD) { writeDescriptorCompat(g, cccd, value) }
        }
    }

    private fun reportOnce(c: CharRef, detail: String) {
        if (reportedProblems.add("${c.service}/${c.characteristic}/$detail")) {
            emit(Events.blocked(PBlockedReason.MISCONFIGURED, deviceId, detail))
        }
    }

    private fun onDisconnected(g: BluetoothGatt, status: Int) {
        val wasUp = linkUp
        val wasConnected = connectedEmitted
        val stable = strategy.isStable(readyAtMs, SystemClock.elapsedRealtime())
        connectedEmitted = false
        readyAtMs = null
        setupJob?.cancel()
        watchdogJob?.cancel()
        queue.close(KeeperException("not_connected", "device disconnected"))
        g.close()
        if (gatt === g) gatt = null
        if (state == State.STOPPED || state == State.BLUETOOTH_OFF) return
        if (!wasUp) strategy.onConnectFailed(lastAttemptAuto)
        if (wasConnected) {
            val reason = GattStatus.disconnectReason(status, linkWasUp = true, localRequest = localDisconnect)
            emit(Events.disconnected(deviceId, reason, status))
        } else {
            note(deviceId, "connect attempt or setup failed, status $status")
        }
        localDisconnect = false
        // Only a link that stayed up long enough reconnects at once and starts
        // counting attempts from 1 again. Links that fail during setup or drop
        // right after it back off, otherwise an in-range device would be
        // reconnected in a tight loop.
        if (stable) attempt = 0
        scheduleReconnect(status, stableLink = stable)
    }

    private fun scheduleReconnect(status: Int, stableLink: Boolean) {
        if (!adapter.isEnabled) {
            state = State.BLUETOOTH_OFF
            return
        }
        attempt++
        // A lost link reconnects at once with autoConnect, which waits for the
        // device without timing out. Immediate failures (status 133, connect
        // timeout) back off exponentially so a broken stack is not hammered.
        val wait = if (GattStatus.needsBackoff(status, stableLink)) backoff.delayMs(attempt) else 0L
        emit(Events.reconnecting(deviceId, attempt))
        state = State.WAITING
        reconnectJob = scope.launch {
            delay(wait)
            connect()
        }
    }

    private fun onData(g: BluetoothGatt, ch: BluetoothGattCharacteristic, value: ByteArray, timestampMs: Long) {
        if (g !== gatt) return
        val ref = CharRef(ch.service.uuid.toString(), ch.uuid.toString())
        emit(Events.data(deviceId, ref, value, timestampMs))
    }

    private fun readyGatt(): BluetoothGatt {
        val g = gatt
        if (state != State.READY || g == null) {
            throw KeeperException("not_connected", "device is not connected")
        }
        return g
    }

    private fun find(g: BluetoothGatt, c: CharRef): BluetoothGattCharacteristic? =
        g.getService(UUID.fromString(c.service))?.getCharacteristic(UUID.fromString(c.characteristic))

    private fun findOrThrow(g: BluetoothGatt, c: CharRef): BluetoothGattCharacteristic =
        find(g, c) ?: throw KeeperException(
            "characteristic_not_found",
            "characteristic ${c.characteristic} not found in service ${c.service}",
        )

    private fun onGattThread(block: () -> Unit) {
        if (Looper.myLooper() == handler.looper) block() else handler.post(block)
    }

    private fun gattError(op: String, status: Int) = KeeperException("gatt_error", "$op failed with status $status")

    private fun finish(op: String, status: Int, value: Any?) {
        if (status == BluetoothGatt.GATT_SUCCESS) queue.complete(op, value) else queue.fail(op, gattError(op, status))
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) =
            onGattThread { handleConnectionState(g, status, newState) }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) =
            onGattThread { if (g === gatt) finish(OP_DISCOVER, status, Unit) }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) =
            onGattThread {
                if (g !== gatt) return@onGattThread
                // The peripheral can also change the MTU later; always keep it.
                if (status == BluetoothGatt.GATT_SUCCESS) this@GattManager.mtu = mtu
                finish(OP_MTU, status, mtu)
            }

        // API 31+: the peripheral changed its GATT table (Service Changed
        // indication); cached handles are stale, so rediscover and resubscribe.
        override fun onServiceChanged(g: BluetoothGatt) = onGattThread {
            if (g !== gatt || state != State.READY) return@onGattThread
            note(deviceId, "services changed, rediscovering")
            state = State.DISCOVERING
            setupJob?.cancel()
            setupJob = scope.launch { runSetupStep(g) { setup(g) } }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) =
            onGattThread { if (g === gatt) finish(OP_CCCD, status, Unit) }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) =
            onGattThread { if (g === gatt) finish(OP_WRITE, status, Unit) }

        // API 33+ delivers the value as a parameter. The default
        // implementation forwards to the deprecated overload, so overriding
        // this one means the deprecated one only runs below API 33.
        override fun onCharacteristicRead(
            g: BluetoothGatt,
            c: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) = onGattThread { if (g === gatt) finish(OP_READ, status, value) }

        @Deprecated("Below API 33 only")
        @Suppress("DEPRECATION")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            // Copy now: the characteristic object is shared and its value is
            // overwritten by the next read or notification.
            val value = c.value?.copyOf() ?: ByteArray(0)
            onGattThread { if (g === gatt) finish(OP_READ, status, value) }
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            val ts = System.currentTimeMillis()
            onGattThread { onData(g, c, value, ts) }
        }

        @Deprecated("Below API 33 only")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            val ts = System.currentTimeMillis()
            val value = c.value?.copyOf() ?: ByteArray(0)
            onGattThread { onData(g, c, value, ts) }
        }
    }

    private companion object {
        const val OP_DISCOVER = "discoverServices"
        const val OP_MTU = "requestMtu"
        const val OP_CCCD = "writeCccd"
        const val OP_READ = "readCharacteristic"
        const val OP_WRITE = "writeCharacteristic"
        const val MAX_ATTRIBUTE_LENGTH = 512

        @Suppress("DEPRECATION")
        fun writeDescriptorCompat(g: BluetoothGatt, d: BluetoothGattDescriptor, value: ByteArray): Boolean =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeDescriptor(d, value) == BluetoothStatusCodes.SUCCESS
            } else {
                d.value = value
                g.writeDescriptor(d)
            }

        @Suppress("DEPRECATION")
        fun writeCharacteristicCompat(
            g: BluetoothGatt,
            c: BluetoothGattCharacteristic,
            value: ByteArray,
            writeType: Int,
        ): Boolean =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeCharacteristic(c, value, writeType) == BluetoothStatusCodes.SUCCESS
            } else {
                c.writeType = writeType
                c.value = value
                g.writeCharacteristic(c)
            }
    }
}
