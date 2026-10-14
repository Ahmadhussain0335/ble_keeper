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

    /** API 33 added REASON_PACKAGE_UPDATED; from then on updates are not REASON_USER_REQUESTED. */
    const val PACKAGE_UPDATED_REASON_API = 33

    /**
     * The installer kills the old process at install time, just before
     * PackageInfo.lastUpdateTime is set. Only exits in this narrow window are
     * treated as the update (a wide window hid real force-stops shortly
     * after an update, hardware test B1 / F3).
     */
    const val UPDATE_WINDOW_BEFORE_MS = 30_000L
    const val UPDATE_WINDOW_AFTER_MS = 5_000L

    /**
     * True when the latest exit was a user force-stop that has not been
     * reported yet and devices were being kept connected at the time.
     *
     * Below API 33 an app update can also be recorded as
     * REASON_USER_REQUESTED, so an exit from [UPDATE_WINDOW_BEFORE_MS] before
     * to [UPDATE_WINDOW_AFTER_MS] after [appUpdatedAtMs] is ignored there.
     */
    fun isUnreportedForceStop(
        reason: Int,
        exitTimestampMs: Long,
        lastReportedExitMs: Long,
        hadSessions: Boolean,
        appUpdatedAtMs: Long? = null,
        sdkInt: Int = PACKAGE_UPDATED_REASON_API,
    ): Boolean = hadSessions &&
        reason == REASON_USER_REQUESTED &&
        exitTimestampMs > lastReportedExitMs &&
        !isUpdateKill(exitTimestampMs, appUpdatedAtMs, sdkInt)

    private fun isUpdateKill(exitTimestampMs: Long, appUpdatedAtMs: Long?, sdkInt: Int): Boolean {
        if (sdkInt >= PACKAGE_UPDATED_REASON_API || appUpdatedAtMs == null) return false
        val delta = exitTimestampMs - appUpdatedAtMs
        return delta >= -UPDATE_WINDOW_BEFORE_MS && delta <= UPDATE_WINDOW_AFTER_MS
    }
}
