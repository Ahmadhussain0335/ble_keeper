package com.ahmadhussain.ble_keeper.core

/**
 * Decides which runtime permissions are missing. Pure so it can be tested on
 * the JVM; callers pass the SDK level and a grant check.
 */
internal object PermissionChecker {
    const val BLUETOOTH_CONNECT = "android.permission.BLUETOOTH_CONNECT"
    const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"

    /**
     * Permissions without which the plugin cannot connect or run its service.
     *
     * Android 12 (API 31) made BLUETOOTH_CONNECT a runtime permission for
     * connectGatt and GATT operations. Android 14 (API 34) also requires it
     * (or another Bluetooth/network permission) before a foreground service of
     * type connectedDevice may start; otherwise startForeground throws
     * SecurityException. Below API 31 the install-time BLUETOOTH permission
     * is enough.
     */
    fun missingForConnect(sdkInt: Int, isGranted: (String) -> Boolean): List<String> =
        if (sdkInt >= 31 && !isGranted(BLUETOOTH_CONNECT)) listOf(BLUETOOTH_CONNECT) else emptyList()

    /**
     * Android 13 (API 33) hides foreground-service notifications when
     * POST_NOTIFICATIONS is denied, but the service still runs. This is a
     * warning, not a block.
     */
    fun notificationsHidden(sdkInt: Int, isGranted: (String) -> Boolean): Boolean =
        sdkInt >= 33 && !isGranted(POST_NOTIFICATIONS)
}
