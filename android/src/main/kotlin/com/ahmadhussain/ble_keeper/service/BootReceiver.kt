package com.ahmadhussain.ble_keeper.service

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import com.ahmadhussain.ble_keeper.KeeperConstants
import com.ahmadhussain.ble_keeper.core.BootClassifier
import com.ahmadhussain.ble_keeper.core.KeeperRuntime

/**
 * Restarts kept connections after a reboot or an app update.
 *
 * Receiving BOOT_COMPLETED or MY_PACKAGE_REPLACED is an exemption from the
 * Android 12 background foreground-service start restriction. Android 15
 * blocks some foreground-service types from BOOT_COMPLETED (dataSync,
 * camera, mediaPlayback, phoneCall, mediaProjection, microphone);
 * connectedDevice is not on that list. BOOT_COMPLETED is delivered after the
 * first unlock, when credential-protected storage (our session file) is
 * readable. A force-stopped app receives neither broadcast until the user
 * opens it again.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val runtime = KeeperRuntime.get(context)
        if (intent.action == Intent.ACTION_BOOT_COMPLETED &&
            !BootClassifier.isRealBoot(SystemClock.elapsedRealtime(), wasForceStopped(context))
        ) {
            // The user opened the app after a force-stop (Android 15+ sends
            // BOOT_COMPLETED then). userForceQuit is reported separately and
            // the UI attach resumes every session; nothing to restore here.
            runtime.note(null, "BOOT_COMPLETED after leaving the stopped state; not a reboot")
            return
        }
        if (runtime.sessions.load().none { it.restartOnBoot }) return
        runtime.note(null, "received ${intent.action}")
        runtime.ensureRunning(null, KeeperConstants.ACTION_BOOT)
    }

    /** ApplicationStartInfo.wasForceStopped() for this process (API 35+), else null. */
    private fun wasForceStopped(context: Context): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) return null
        return try {
            context.getSystemService(ActivityManager::class.java)
                ?.getHistoricalProcessStartReasons(1)
                ?.firstOrNull()
                ?.wasForceStopped()
        } catch (e: Exception) {
            null
        }
    }
}
