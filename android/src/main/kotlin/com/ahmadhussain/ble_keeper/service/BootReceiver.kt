package com.ahmadhussain.ble_keeper.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.ahmadhussain.ble_keeper.KeeperConstants
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
        if (runtime.sessions.load().none { it.restartOnBoot }) return
        runtime.note(null, "received ${intent.action}")
        runtime.ensureRunning(null, KeeperConstants.ACTION_BOOT)
    }
}
