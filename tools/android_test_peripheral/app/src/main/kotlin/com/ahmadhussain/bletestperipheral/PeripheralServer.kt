package com.ahmadhussain.bletestperipheral

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertisingSet
import android.bluetooth.le.AdvertisingSetCallback
import android.bluetooth.le.AdvertisingSetParameters
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/** Snapshot rendered by the UI. */
data class PeripheralState(
    val running: Boolean = false,
    val advertising: Boolean = false,
    val centrals: List<String> = emptyList(),
    val subscribers: Int = 0,
    val counter: Long = 0,
    val lastCommand: String = "-",
    val log: List<String> = emptyList(),
)

/**
 * GATT server that behaves like tools/esp32_test_device:
 * - notify characteristic: uint32 little-endian counter, +1 every second while
 *   running (also while nobody is connected, so the central can count gaps),
 *   notified to subscribed centrals;
 * - command characteristic: "disconnect", "reboot", "silent";
 * - pairing characteristic: readable only over an encrypted link, so the
 *   first read from an iPhone makes iOS pair (iOS has no pairing UI for BLE
 *   peripherals). The bond lets the central follow the rotating address.
 *
 * Advertising uses one AdvertisingSet that is only enabled/disabled, never
 * recreated, to keep the (private, rotating) address stable as long as the
 * stack allows.
 *
 * Threading: GATT server and advertising callbacks arrive on binder threads
 * and are re-posted to the main thread; all state lives on the main thread.
 */
@SuppressLint("MissingPermission") // Permissions are requested before start().
class PeripheralServer(private val context: Context, private val onState: (PeripheralState) -> Unit) {

    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(BluetoothManager::class.java)
    private var server: BluetoothGattServer? = null
    private var advertisingSet: AdvertisingSet? = null
    private var advertisingCallback: AdvertisingSetCallback? = null

    private val centrals = linkedMapOf<String, BluetoothDevice>()
    private val subscribers = mutableSetOf<String>()
    private var counter = 0L
    private var silentUntil = 0L
    private var rebooting = false
    private var state = PeripheralState()

    private lateinit var notifyChar: BluetoothGattCharacteristic

    private val tick = object : Runnable {
        override fun run() {
            counter = (counter + 1) and 0xFFFFFFFFL
            if (SystemClock.elapsedRealtime() >= silentUntil) notifySubscribers()
            publish()
            main.postDelayed(this, 1_000)
        }
    }

    fun start() {
        if (state.running) return
        val adapter = manager?.adapter
        if (adapter == null || !adapter.isEnabled) {
            log("Bluetooth is off or missing")
            return
        }
        val s = manager.openGattServer(context, callback)
        if (s == null) {
            log("openGattServer failed")
            return
        }
        server = s
        s.addService(buildService())
        state = state.copy(running = true)
        log("GATT server opened, adding service")
    }

    fun stop() {
        main.removeCallbacks(tick)
        advertisingSet?.let { manager?.adapter?.bluetoothLeAdvertiser?.stopAdvertisingSet(advertisingCallback) }
        advertisingSet = null
        advertisingCallback = null
        centrals.values.forEach { server?.cancelConnection(it) }
        server?.close()
        server = null
        centrals.clear()
        subscribers.clear()
        state = state.copy(running = false, advertising = false)
        log("stopped")
    }

    private fun buildService(): BluetoothGattService {
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        notifyChar = BluetoothGattCharacteristic(
            NOTIFY_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ,
        )
        notifyChar.addDescriptor(
            BluetoothGattDescriptor(
                CCCD_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
            ),
        )
        val commandChar = BluetoothGattCharacteristic(
            COMMAND_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        val pairChar = BluetoothGattCharacteristic(
            PAIR_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED,
        )
        service.addCharacteristic(notifyChar)
        service.addCharacteristic(commandChar)
        service.addCharacteristic(pairChar)
        return service
    }

    private fun startAdvertising() {
        val advertiser = manager?.adapter?.bluetoothLeAdvertiser
        if (advertiser == null) {
            log("this phone cannot advertise")
            return
        }
        val params = AdvertisingSetParameters.Builder()
            .setLegacyMode(true)
            .setConnectable(true)
            .setScannable(true)
            .setInterval(AdvertisingSetParameters.INTERVAL_LOW) // 160 x 0.625 ms = 100 ms
            .setTxPowerLevel(AdvertisingSetParameters.TX_POWER_MEDIUM)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        // The local name (the phone's Bluetooth name) goes in the scan response.
        val scanResponse = AdvertiseData.Builder().setIncludeDeviceName(true).build()
        val cb = object : AdvertisingSetCallback() {
            override fun onAdvertisingSetStarted(set: AdvertisingSet?, txPower: Int, status: Int) = main.post {
                if (status == ADVERTISE_SUCCESS && set != null) {
                    advertisingSet = set
                    state = state.copy(advertising = true)
                    log("advertising started (tx $txPower dBm)")
                } else {
                    log("advertising failed to start, status $status")
                }
            }.let { }

            override fun onAdvertisingEnabled(set: AdvertisingSet?, enable: Boolean, status: Int) = main.post {
                if (status == ADVERTISE_SUCCESS) {
                    state = state.copy(advertising = enable)
                    log(if (enable) "advertising enabled" else "advertising disabled")
                } else {
                    log("advertising enable=$enable failed, status $status")
                }
            }.let { }

            override fun onAdvertisingSetStopped(set: AdvertisingSet?) = main.post {
                state = state.copy(advertising = false)
                log("advertising set stopped")
            }.let { }
        }
        advertisingCallback = cb
        advertiser.startAdvertisingSet(params, data, scanResponse, null, null, cb)
    }

    private fun setAdvertising(enable: Boolean) {
        val set = advertisingSet ?: return
        set.enableAdvertising(enable, 0, 0)
    }

    private fun notifySubscribers() {
        val s = server ?: return
        if (subscribers.isEmpty()) return
        val value = counterBytes()
        for (address in subscribers) {
            val device = centrals[address] ?: continue
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                s.notifyCharacteristicChanged(device, notifyChar, false, value)
            } else {
                @Suppress("DEPRECATION")
                notifyChar.value = value
                @Suppress("DEPRECATION")
                s.notifyCharacteristicChanged(device, notifyChar, false)
            }
        }
    }

    private fun counterBytes(): ByteArray = byteArrayOf(
        (counter and 0xFF).toByte(),
        ((counter shr 8) and 0xFF).toByte(),
        ((counter shr 16) and 0xFF).toByte(),
        ((counter shr 24) and 0xFF).toByte(),
    )

    private fun handleCommand(device: BluetoothDevice, raw: String) {
        val command = raw.trim()
        state = state.copy(lastCommand = command)
        log("command \"$command\" from ${device.address}")
        when (command) {
            "disconnect" -> dropLink(device)
            "reboot" -> reboot()
            "silent" -> {
                silentUntil = SystemClock.elapsedRealtime() + SILENT_MS
                log("silent for ${SILENT_MS / 1000} s")
            }
            else -> log("unknown command")
        }
    }

    /**
     * BluetoothGattServer.cancelConnection() is ignored for a link the
     * central opened (seen on Android 13 / One UI 5.1): the server does not
     * own it. Calling connect(device, false) first makes the server a client
     * of that link, after which cancelConnection() drops it.
     */
    private fun dropLink(device: BluetoothDevice) {
        val s = server ?: return
        s.connect(device, false)
        main.postDelayed({ s.cancelConnection(device) }, 200)
    }

    /** Simulates a device reboot: drop links, stop advertising 10 s, counter to 0. */
    private fun reboot() {
        rebooting = true
        centrals.values.toList().forEach { dropLink(it) }
        setAdvertising(false)
        counter = 0
        silentUntil = 0
        main.postDelayed({
            rebooting = false
            setAdvertising(true)
            log("reboot done, advertising again")
        }, REBOOT_PAUSE_MS)
    }

    private val callback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) = main.post {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                log("service added")
                startAdvertising()
                main.removeCallbacks(tick)
                main.postDelayed(tick, 1_000)
            } else {
                log("addService failed, status $status")
            }
        }.let { }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) = main.post {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                centrals[device.address] = device
                log("central connected ${device.address} (status $status)")
            } else {
                centrals.remove(device.address)
                subscribers.remove(device.address)
                log("central disconnected ${device.address} (status $status)")
                // A connection usually stops connectable advertising; resume it
                // (except during a simulated reboot).
                if (!rebooting && state.running) setAdvertising(true)
            }
            publish()
        }.let { }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic,
        ) = main.post {
            // The stack only forwards a PAIR_UUID read once the link is encrypted.
            val value = when (characteristic.uuid) {
                NOTIFY_UUID -> counterBytes()
                PAIR_UUID -> {
                    if (offset == 0) log("pairing characteristic read by ${device.address} (bond ${bondName(device)})")
                    PAIRED_VALUE
                }
                else -> ByteArray(0)
            }
            val slice = if (offset < value.size) value.copyOfRange(offset, value.size) else ByteArray(0)
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, slice)
        }.let { }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) = main.post {
            if (characteristic.uuid != COMMAND_UUID) {
                if (responseNeeded) {
                    server?.sendResponse(device, requestId, BluetoothGatt.GATT_WRITE_NOT_PERMITTED, offset, null)
                }
                return@post
            }
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            // Let the write response go out before acting on the command.
            val text = String(value ?: ByteArray(0), Charsets.UTF_8)
            main.postDelayed({ handleCommand(device, text) }, 100)
        }.let { }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor,
        ) = main.post {
            val value = if (device.address in subscribers) {
                BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            } else {
                BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            }
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
        }.let { }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) = main.post {
            if (descriptor.uuid == CCCD_UUID && value != null) {
                if (value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) {
                    subscribers.add(device.address)
                    log("notifications enabled by ${device.address}")
                } else if (value.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)) {
                    subscribers.remove(device.address)
                    log("notifications disabled by ${device.address}")
                } else {
                    log("unsupported CCCD value ${value.joinToString { "%02x".format(it) }}")
                }
            }
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            publish()
        }.let { }
    }

    private fun bondName(device: BluetoothDevice): String = when (device.bondState) {
        BluetoothDevice.BOND_BONDED -> "bonded"
        BluetoothDevice.BOND_BONDING -> "bonding"
        else -> "none"
    }

    private fun log(text: String) {
        val line = "${TIME.format(Date())}  $text"
        state = state.copy(log = (state.log + line).takeLast(300))
        publish()
    }

    private fun publish() {
        state = state.copy(
            centrals = centrals.keys.toList(),
            subscribers = subscribers.size,
            counter = counter,
        )
        onState(state)
    }

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-1234567890ab")
        val NOTIFY_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-1234567890ac")
        val COMMAND_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-1234567890ad")
        val PAIR_UUID: UUID = UUID.fromString("12345678-1234-1234-1234-1234567890ae")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private val PAIRED_VALUE = "paired".toByteArray(Charsets.US_ASCII)
        const val SILENT_MS = 30_000L
        const val REBOOT_PAUSE_MS = 10_000L
        private val TIME = SimpleDateFormat("HH:mm:ss", Locale.US)
    }
}
