package com.ahmadhussain.ble_keeper.core

/** A characteristic by lowercase 128-bit UUIDs. */
internal data class CharRef(val service: String, val characteristic: String)

/** A persisted keepConnected request. */
internal data class Session(
    val deviceId: String,
    val subscribe: List<CharRef>,
    val notificationTitle: String? = null,
    val notificationText: String? = null,
    val notificationIcon: String? = null,
    val restartOnBoot: Boolean = true,
)

/** Error with a code that is passed to Dart as `BleKeeperException.code`. */
internal class KeeperException(val code: String, message: String) : Exception(message)
