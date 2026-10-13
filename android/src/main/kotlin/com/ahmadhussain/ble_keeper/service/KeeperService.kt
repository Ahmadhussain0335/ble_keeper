package com.ahmadhussain.ble_keeper.service

import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import com.ahmadhussain.ble_keeper.KeeperConstants
import com.ahmadhussain.ble_keeper.PBlockedReason
import com.ahmadhussain.ble_keeper.core.Events
import com.ahmadhussain.ble_keeper.core.KeeperRuntime
import com.ahmadhussain.ble_keeper.core.Session
import com.ahmadhussain.ble_keeper.gatt.GattManager

/**
 * Foreground service of type connectedDevice that owns every GATT connection.
 *
 * It does not depend on a Flutter engine, so connections survive the UI
 * being closed. START_STICKY asks the system to recreate it (with a null
 * intent) after the process is killed for memory; a force-stop cancels that.
 *
 * Methods run on the main thread; GATT work runs on [gattThread].
 */
class KeeperService : Service() {
    private lateinit var runtime: KeeperRuntime
    private lateinit var gattThread: HandlerThread
    private lateinit var gattHandler: Handler
    private val managers = mutableMapOf<String, GattManager>()
    private var bluetoothOff = false
    private var receiverRegistered = false

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF -> onBluetoothOff()
                BluetoothAdapter.STATE_ON -> onBluetoothOn()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        runtime = KeeperRuntime.get(this)
        gattThread = HandlerThread(KeeperConstants.GATT_THREAD_NAME).apply { start() }
        gattHandler = Handler(gattThread.looper)
        runtime.service = this
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        // ACTION_STATE_CHANGED is a protected system broadcast, so the receiver
        // is not exported (Android 14 requires choosing a flag explicitly).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(bluetoothReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(bluetoothReceiver, filter)
        }
        receiverRegistered = true
        bluetoothOff = runtime.bluetoothAdapter()?.isEnabled != true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val all = runtime.sessions.load()
        // After startForegroundService the app has a few seconds to call
        // startForeground, or the system stops it with an exception. Call it
        // first, even when the service is about to stop again.
        try {
            startForegroundNow(all)
        } catch (e: Exception) {
            runtime.reportStartFailure(e)
            stopSelf()
            return START_NOT_STICKY
        }
        val restored = intent == null || intent.action == KeeperConstants.ACTION_BOOT
        // On boot / app update only sessions that opted in are restarted; the
        // rest resume when the UI attaches.
        val sessions = if (intent?.action == KeeperConstants.ACTION_BOOT) all.filter { it.restartOnBoot } else all
        if (sessions.isEmpty()) {
            stopNow()
            return START_NOT_STICKY
        }
        if (restored) {
            runtime.note(null, if (intent == null) "service restarted by the system" else "service started after boot")
            runtime.publish(Events.restored(sessions.map { it.deviceId }))
        }
        if (bluetoothOff) runtime.publish(Events.blocked(PBlockedReason.BLUETOOTH_OFF))
        reconcile(sessions)
        return START_STICKY
    }

    /** Aligns running connections with [sessions] (persisted ones by default). */
    internal fun reconcile(sessions: List<Session> = runtime.sessions.load()) {
        if (sessions.isEmpty()) {
            stopNow()
            return
        }
        val adapter = runtime.bluetoothAdapter() ?: return
        val ids = sessions.map { it.deviceId }.toSet()
        (managers.keys - ids).forEach { managers.remove(it)?.stop() }
        for (s in sessions) {
            val existing = managers[s.deviceId]
            if (existing != null) {
                existing.update(s)
            } else {
                val m = GattManager(
                    context = this,
                    adapter = adapter,
                    initialSession = s,
                    handler = gattHandler,
                    emit = runtime::publish,
                    note = { id, text -> runtime.note(id, text) },
                )
                managers[s.deviceId] = m
                m.start()
            }
        }
        KeeperNotification.update(this, sessions)
    }

    internal fun manager(deviceId: String): GattManager? = managers[deviceId]

    private fun onBluetoothOff() {
        if (bluetoothOff) return
        bluetoothOff = true
        managers.values.forEach { it.onBluetoothOff() }
        runtime.publish(Events.blocked(PBlockedReason.BLUETOOTH_OFF))
    }

    private fun onBluetoothOn() {
        if (!bluetoothOff) return
        bluetoothOff = false
        runtime.note(null, "Bluetooth on, reconnecting")
        managers.values.forEach { it.onBluetoothOn() }
    }

    private fun startForegroundNow(sessions: List<Session>) {
        val notification = KeeperNotification.build(this, sessions)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                KeeperConstants.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(KeeperConstants.NOTIFICATION_ID, notification)
        }
    }

    private fun stopNow() {
        managers.values.forEach { it.stop() }
        managers.clear()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        managers.values.forEach { it.stop() }
        managers.clear()
        if (receiverRegistered) unregisterReceiver(bluetoothReceiver)
        receiverRegistered = false
        // quitSafely runs the already-posted stop/close messages first.
        gattThread.quitSafely()
        if (runtime.service === this) runtime.service = null
        runtime.headless.stop()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
