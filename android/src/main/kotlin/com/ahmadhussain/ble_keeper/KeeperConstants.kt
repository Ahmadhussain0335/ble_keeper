package com.ahmadhussain.ble_keeper

/**
 * Every name-bearing string the plugin persists or registers with the OS.
 * Changing these after a release orphans existing users' sessions and logs.
 */
internal object KeeperConstants {
    const val LOG_TAG = "BleKeeper"

    const val NOTIFICATION_CHANNEL_ID = "ble_keeper_connection"
    const val NOTIFICATION_ID = 0x0B1E

    /** Directory under `noBackupFilesDir`; excluded from Auto Backup by the OS. */
    const val STORAGE_DIR = "ble_keeper"
    const val SESSIONS_FILE = "sessions.json"
    const val CALLBACKS_FILE = "callbacks.json"
    const val STATE_FILE = "state.json"
    const val LOG_DIR = "logs"
    const val LOG_FILE = "events.log"
    const val EXPORT_DIR = "ble_keeper_export"

    const val LOG_MAX_BYTES = 1_000_000L

    const val ACTION_KEEP = "com.ahmadhussain.ble_keeper.action.KEEP"
    const val ACTION_BOOT = "com.ahmadhussain.ble_keeper.action.BOOT"

    const val GATT_THREAD_NAME = "ble-keeper-gatt"

    /** Client Characteristic Configuration Descriptor (Bluetooth Core Spec Vol 3, Part G, 3.3.3.3). */
    const val CCCD_UUID = "00002902-0000-1000-8000-00805f9b34fb"

    /** Largest ATT MTU (Bluetooth Core Spec Vol 3, Part F, 3.2.9). */
    const val MAX_MTU = 517
    const val DEFAULT_MTU = 23
}
