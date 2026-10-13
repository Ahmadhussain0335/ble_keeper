package com.ahmadhussain.ble_keeper.core

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.ForegroundServiceStartNotAllowedException
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.ahmadhussain.ble_keeper.KeeperConstants
import com.ahmadhussain.ble_keeper.PBlockedReason
import com.ahmadhussain.ble_keeper.PEvent
import com.ahmadhussain.ble_keeper.PEventType
import com.ahmadhussain.ble_keeper.gatt.GattManager
import com.ahmadhussain.ble_keeper.headless.HeadlessEngineRunner
import com.ahmadhussain.ble_keeper.log.DataAggregator
import com.ahmadhussain.ble_keeper.log.LogFormatter
import com.ahmadhussain.ble_keeper.log.Pseudonymizer
import com.ahmadhussain.ble_keeper.log.RotatingEventLog
import com.ahmadhussain.ble_keeper.service.KeeperService
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Process-wide state shared by the plugin instances (one per Flutter engine),
 * the foreground service and the boot receiver. Lives as long as the process,
 * independent of any Flutter engine.
 *
 * Methods that touch [hub], [service] or engine bookkeeping must be called on
 * the main thread; [publish] and [note] may be called from any thread.
 */
internal class KeeperRuntime private constructor(context: Context) {
    val appContext: Context = context.applicationContext
    val mainHandler = Handler(Looper.getMainLooper())

    private val dir = File(appContext.noBackupFilesDir, KeeperConstants.STORAGE_DIR)
    private val exportDir = File(appContext.cacheDir, KeeperConstants.EXPORT_DIR)
    val sessions = SessionStore(File(dir, KeeperConstants.SESSIONS_FILE))
    val state = KeeperState(File(dir, KeeperConstants.STATE_FILE))

    private val isDebuggable = appContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    @Volatile
    private var formatter = newFormatter()
    private val log = RotatingEventLog(
        File(dir, KeeperConstants.LOG_DIR),
        KeeperConstants.LOG_FILE,
        KeeperConstants.LOG_MAX_BYTES,
        Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "ble-keeper-log") },
    )

    // Data events are summarised per minute; everything else is one line.
    // Main thread only.
    private val dataAggregator = DataAggregator()
    private var droppedSinceLastNote = 0
    private var logTickScheduled = false

    val hub = EventHub(
        onPublished = { e ->
            if (e.type == PEventType.DATA) dataAggregator.add(e) else log.append(formatter.format(e))
            scheduleLogTick()
        },
        onDropped = { n ->
            droppedSinceLastNote += n
            scheduleLogTick()
        },
    )
    val headless = HeadlessEngineRunner(this)

    /** The running service, set by the service itself. Main thread only. */
    var service: KeeperService? = null

    private val activityEngines = mutableSetOf<Any>()

    init {
        hub.onNoSink = ::onNoSink
        hub.onDeliveryFailed = { mainHandler.postDelayed({ hub.retry() }, DELIVERY_RETRY_MS) }
        mainHandler.post { checkPreviousExit() }
    }

    fun publish(event: PEvent) = onMain { hub.publish(event) }

    fun note(deviceId: String?, text: String) {
        val prefix = deviceId?.let { "device=${formatter.deviceLabel(it)} " } ?: ""
        log.append(formatter.note(System.currentTimeMillis(), "note", prefix + text))
    }

    fun bluetoothAdapter(): BluetoothAdapter? =
        appContext.getSystemService(BluetoothManager::class.java)?.adapter

    fun isGranted(permission: String) =
        appContext.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** Persists [session] and makes sure the service keeps it connected. */
    fun keep(session: Session) {
        sessions.upsert(session)
        ensureRunning(session.deviceId, KeeperConstants.ACTION_KEEP)
    }

    fun stop(deviceId: String) {
        sessions.remove(deviceId)
        service?.reconcile()
    }

    /**
     * Starts the service, or refreshes it when it already runs. Reports
     * [PBlockedReason]s instead of throwing; returns false when blocked.
     */
    fun ensureRunning(deviceId: String?, action: String): Boolean {
        if (bluetoothAdapter() == null) {
            publish(Events.blocked(PBlockedReason.UNKNOWN, deviceId, "this device has no Bluetooth adapter"))
            return false
        }
        val missing = PermissionChecker.missingForConnect(Build.VERSION.SDK_INT, ::isGranted)
        if (missing.isNotEmpty()) {
            missing.forEach { publish(Events.blocked(PBlockedReason.PERMISSION_MISSING, deviceId, it)) }
            return false
        }
        if (PermissionChecker.notificationsHidden(Build.VERSION.SDK_INT, ::isGranted)) {
            note(null, "POST_NOTIFICATIONS denied: the service runs but its notification is hidden")
        }
        service?.let {
            it.reconcile()
            return true
        }
        return startService(action)
    }

    @SuppressLint("NewApi") // startForegroundService is only reached on API 26+.
    private fun startService(action: String): Boolean {
        val intent = Intent(appContext, KeeperService::class.java).setAction(action)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(intent)
            } else {
                appContext.startService(intent)
            }
            true
        } catch (e: Exception) {
            reportStartFailure(e)
            false
        }
    }

    /**
     * Android 12 (API 31) forbids starting a foreground service while the app
     * is in the background, except for documented exemptions (for example
     * BOOT_COMPLETED and MY_PACKAGE_REPLACED receivers). The failure is
     * ForegroundServiceStartNotAllowedException, an IllegalStateException;
     * API 26-30 throw a plain IllegalStateException for background startService.
     * Android 14 (API 34) throws SecurityException when the connectedDevice
     * type's prerequisite permission is missing.
     */
    fun reportStartFailure(e: Exception) {
        val reason = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && e is ForegroundServiceStartNotAllowedException ->
                PBlockedReason.FOREGROUND_START_NOT_ALLOWED
            e is IllegalStateException -> PBlockedReason.FOREGROUND_START_NOT_ALLOWED
            e is SecurityException -> {
                val missing = PermissionChecker.missingForConnect(Build.VERSION.SDK_INT, ::isGranted)
                if (missing.isNotEmpty()) {
                    missing.forEach { publish(Events.blocked(PBlockedReason.PERMISSION_MISSING, null, it)) }
                    return
                }
                PBlockedReason.MISCONFIGURED
            }
            else -> PBlockedReason.UNKNOWN
        }
        publish(Events.blocked(reason, null, "${e.javaClass.simpleName}: ${e.message}"))
    }

    fun manager(deviceId: String): GattManager {
        service?.manager(deviceId)?.let { return it }
        if (sessions.load().any { it.deviceId == deviceId }) {
            throw KeeperException("not_connected", "device is not connected")
        }
        throw KeeperException("unknown_device", "keepConnected was not called for this device")
    }

    // Engine and sink bookkeeping (main thread).

    fun setActivityAttached(engineToken: Any, attached: Boolean) {
        if (attached) activityEngines.add(engineToken) else activityEngines.remove(engineToken)
    }

    fun attachSink(sink: EventHub.Sink) {
        hub.attach(sink)
        if (!sink.isBackground) {
            headless.stopSoon()
            // Resume persisted sessions when the UI comes back, for example
            // after a force-stop (which Android never recovers from by itself)
            // or for sessions with restartOnBoot = false after a reboot.
            if (sessions.load().isNotEmpty()) {
                ensureRunning(null, KeeperConstants.ACTION_KEEP)
            }
        }
    }

    private fun onNoSink() {
        if (activityEngines.isEmpty() && state.dispatcherHandle != null && service != null) headless.start()
    }

    // Log export (call off the main thread).

    /** Writes pending Data summaries and the drop counter. Main thread only. */
    fun flushLogSummaries() {
        val now = System.currentTimeMillis()
        dataAggregator.drain(now, formatter).forEach(log::append)
        if (droppedSinceLastNote > 0) {
            note(null, "dropped $droppedSinceLastNote undelivered Data events (buffer full)")
            droppedSinceLastNote = 0
        }
    }

    private fun scheduleLogTick() {
        if (logTickScheduled) return
        logTickScheduled = true
        mainHandler.postDelayed({
            logTickScheduled = false
            flushLogSummaries()
        }, LOG_SUMMARY_INTERVAL_MS)
    }

    /** Call [flushLogSummaries] on the main thread first. */
    fun exportLog(): File {
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        return log.export(File(exportDir, "ble_keeper_events_$stamp.log"))
    }

    /**
     * Erases the log, exported copies and the corrupt-session backup, and
     * rotates the pseudonym salt so later lines cannot be linked to logs
     * that were already shared (GDPR Art. 17).
     */
    fun clearLog() {
        log.clear(exportDir)
        File(dir, KeeperConstants.SESSIONS_FILE + ".corrupt").delete()
        state.rotateSalt()
        formatter = newFormatter()
    }

    private fun newFormatter() = LogFormatter(if (isDebuggable) null else Pseudonymizer(state.salt()))

    private fun checkPreviousExit() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val am = appContext.getSystemService(ActivityManager::class.java) ?: return
        val info = try {
            am.getHistoricalProcessExitReasons(null, 0, 1).firstOrNull()
        } catch (e: Exception) {
            null
        } ?: return
        val hadSessions = sessions.load().isNotEmpty()
        val updatedAt: Long? = try {
            appContext.packageManager.getPackageInfo(appContext.packageName, 0).lastUpdateTime
        } catch (e: Exception) {
            null
        }
        if (ExitReasons.isUnreportedForceStop(
                info.reason,
                info.timestamp,
                state.lastReportedExitMs,
                hadSessions,
                updatedAt,
            )
        ) {
            publish(
                Events.blocked(
                    PBlockedReason.USER_FORCE_QUIT,
                    null,
                    "the app was force-stopped; Android does not restart it until the user opens it",
                ),
            )
        }
        if (info.timestamp > state.lastReportedExitMs) state.lastReportedExitMs = info.timestamp
    }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
    }

    companion object {
        private const val DELIVERY_RETRY_MS = 5_000L
        private const val LOG_SUMMARY_INTERVAL_MS = 60_000L

        @Volatile
        private var instance: KeeperRuntime? = null

        fun get(context: Context): KeeperRuntime =
            instance ?: synchronized(this) {
                instance ?: KeeperRuntime(context).also { instance = it }
            }
    }
}
