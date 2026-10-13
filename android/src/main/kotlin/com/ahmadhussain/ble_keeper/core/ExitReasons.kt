package com.ahmadhussain.ble_keeper.core

/**
 * Classifies the previous process exit, read from
 * ActivityManager.getHistoricalProcessExitReasons (API 30+).
 *
 * Force-stop (Settings "Force stop", `adb shell am force-stop`, and on most
 * devices the Android 13+ Task Manager "Stop") is reported as
 * ApplicationExitInfo.REASON_USER_REQUESTED. After a force-stop Android
 * keeps the app in the stopped state: no sticky restart, no BOOT_COMPLETED,
 * no alarms until the user opens the app again.
 */
internal object ExitReasons {
    /** ApplicationExitInfo.REASON_USER_REQUESTED. */
    const val REASON_USER_REQUESTED = 10

    /** Exits this close to the last app update are treated as the update. */
    const val UPDATE_WINDOW_MS = 60_000L

    /**
     * True when the latest exit was a user force-stop that has not been
     * reported yet and devices were being kept connected at the time.
     *
     * Before API 33 (REASON_PACKAGE_UPDATED) an app update can also be
     * recorded as REASON_USER_REQUESTED; an exit within [UPDATE_WINDOW_MS] of
     * [appUpdatedAtMs] (PackageInfo.lastUpdateTime) is therefore ignored.
     */
    fun isUnreportedForceStop(
        reason: Int,
        exitTimestampMs: Long,
        lastReportedExitMs: Long,
        hadSessions: Boolean,
        appUpdatedAtMs: Long? = null,
    ): Boolean = hadSessions &&
        reason == REASON_USER_REQUESTED &&
        exitTimestampMs > lastReportedExitMs &&
        (appUpdatedAtMs == null || kotlin.math.abs(exitTimestampMs - appUpdatedAtMs) > UPDATE_WINDOW_MS)
}
