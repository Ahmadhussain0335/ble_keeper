package com.ahmadhussain.ble_keeper.core

import com.ahmadhussain.ble_keeper.PBlockedReason
import com.ahmadhussain.ble_keeper.PCharacteristicRef
import com.ahmadhussain.ble_keeper.PDisconnectReason
import com.ahmadhussain.ble_keeper.PEvent
import com.ahmadhussain.ble_keeper.PEventType

/** Builders for event envelopes. `seq` is assigned later by [EventHub]. */
internal object Events {
    private fun now() = System.currentTimeMillis()

    fun connected(deviceId: String) =
        PEvent(seq = 0, timestampMs = now(), type = PEventType.CONNECTED, deviceId = deviceId)

    fun disconnected(deviceId: String, reason: PDisconnectReason, platformCode: Int?) =
        PEvent(
            seq = 0,
            timestampMs = now(),
            type = PEventType.DISCONNECTED,
            deviceId = deviceId,
            disconnectReason = reason,
            platformCode = platformCode?.toLong(),
        )

    fun reconnecting(deviceId: String, attempt: Int) =
        PEvent(
            seq = 0,
            timestampMs = now(),
            type = PEventType.RECONNECTING,
            deviceId = deviceId,
            attempt = attempt.toLong(),
        )

    fun data(deviceId: String, c: CharRef, value: ByteArray, timestampMs: Long = now()) =
        PEvent(
            seq = 0,
            timestampMs = timestampMs,
            type = PEventType.DATA,
            deviceId = deviceId,
            characteristic = PCharacteristicRef(c.service, c.characteristic),
            value = value,
        )

    fun restored(deviceIds: List<String>) =
        PEvent(seq = 0, timestampMs = now(), type = PEventType.RESTORED_AFTER_KILL, deviceIds = deviceIds)

    fun blocked(reason: PBlockedReason, deviceId: String? = null, detail: String? = null) =
        PEvent(
            seq = 0,
            timestampMs = now(),
            type = PEventType.BLOCKED,
            deviceId = deviceId,
            blockedReason = reason,
            detail = detail,
        )
}
