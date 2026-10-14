package com.ahmadhussain.ble_keeper.core

/**
 * Decides whether a BOOT_COMPLETED broadcast follows a real reboot.
 *
 * Android 15+ also sends BOOT_COMPLETED to an app when it leaves the stopped
 * state, i.e. when the user opens it after a force-stop (seen on Android 16,
 * 2026-10-14 hardware test A6c). Treating that as a reboot reported a
 * misleading RestoredAfterKill. Signals, in order:
 * - ApplicationStartInfo.wasForceStopped() (API 35+) for the current process;
 * - device uptime: after a real boot the broadcast arrives within minutes.
 */
internal object BootClassifier {
    /** BOOT_COMPLETED later than this after boot is not treated as a reboot. */
    const val MAX_BOOT_UPTIME_MS = 10 * 60_000L

    fun isRealBoot(uptimeMs: Long, wasForceStopped: Boolean?): Boolean {
        if (wasForceStopped == true) return false
        return uptimeMs <= MAX_BOOT_UPTIME_MS
    }
}
