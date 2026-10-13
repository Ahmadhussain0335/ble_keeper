package com.ahmadhussain.ble_keeper.log

import com.ahmadhussain.ble_keeper.PBlockedReason
import com.ahmadhussain.ble_keeper.PDisconnectReason
import com.ahmadhussain.ble_keeper.PEvent
import com.ahmadhussain.ble_keeper.PEventType
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Formats one event per line:
 *
 *     2026-10-13T09:12:33.123Z #42 data device=dev-3f2a91c4 char=...90ac len=4
 *
 * The iOS implementation produces the same format; keep them in sync.
 *
 * Data minimisation (GDPR Art. 5(1)(c)): payload bytes are never written,
 * only their length. Device IDs (MAC addresses are persistent hardware
 * identifiers) are replaced by a salted HMAC when [pseudonymizer] is set,
 * which the runtime does for release builds.
 */
internal class LogFormatter(private val pseudonymizer: Pseudonymizer?) {

    fun format(e: PEvent): String {
        val sb = StringBuilder()
        sb.append(iso(e.timestampMs)).append(" #").append(e.seq).append(' ').append(typeName(e.type))
        e.deviceId?.let { sb.append(" device=").append(deviceLabel(it)) }
        when (e.type) {
            PEventType.DISCONNECTED -> {
                sb.append(" reason=").append(reasonName(e.disconnectReason))
                e.platformCode?.let { sb.append(" code=").append(it) }
            }
            PEventType.RECONNECTING -> sb.append(" attempt=").append(e.attempt)
            PEventType.DATA -> {
                e.characteristic?.let { sb.append(" char=").append(it.characteristicUuid) }
                sb.append(" len=").append(e.value?.size ?: 0)
            }
            PEventType.RESTORED_AFTER_KILL ->
                sb.append(" devices=").append(e.deviceIds.orEmpty().joinToString(",") { deviceLabel(it) })
            PEventType.BLOCKED -> {
                sb.append(" reason=").append(blockedName(e.blockedReason))
                e.detail?.let { sb.append(" detail=").append(quote(it)) }
            }
            PEventType.CONNECTED -> Unit
        }
        return sb.toString()
    }

    /** A diagnostic line that is not an event, for example a warning. */
    fun note(timestampMs: Long, level: String, text: String): String =
        "${iso(timestampMs)} $level ${quote(text)}"

    /** The device ID as written to the log: raw, or its pseudonym. */
    fun deviceLabel(id: String) = pseudonymizer?.pseudonym(id) ?: id

    companion object {
        fun iso(timestampMs: Long): String {
            val f = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            f.timeZone = TimeZone.getTimeZone("UTC")
            return f.format(Date(timestampMs))
        }

        fun quote(text: String): String =
            "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r") + "\""

        fun typeName(t: PEventType) = when (t) {
            PEventType.CONNECTED -> "connected"
            PEventType.DISCONNECTED -> "disconnected"
            PEventType.RECONNECTING -> "reconnecting"
            PEventType.DATA -> "data"
            PEventType.RESTORED_AFTER_KILL -> "restoredAfterKill"
            PEventType.BLOCKED -> "blocked"
        }

        fun reasonName(r: PDisconnectReason?) = when (r) {
            PDisconnectReason.PEER_TERMINATED -> "peerTerminated"
            PDisconnectReason.LINK_LOSS -> "linkLoss"
            PDisconnectReason.LOCAL_TERMINATED -> "localTerminated"
            PDisconnectReason.BLUETOOTH_OFF -> "bluetoothOff"
            PDisconnectReason.STOPPED -> "stopped"
            PDisconnectReason.CONNECT_FAILED -> "connectFailed"
            PDisconnectReason.UNKNOWN, null -> "unknown"
        }

        fun blockedName(r: PBlockedReason?) = when (r) {
            PBlockedReason.BLUETOOTH_OFF -> "bluetoothOff"
            PBlockedReason.PERMISSION_MISSING -> "permissionMissing"
            PBlockedReason.FOREGROUND_START_NOT_ALLOWED -> "foregroundStartNotAllowed"
            PBlockedReason.USER_FORCE_QUIT -> "userForceQuit"
            PBlockedReason.MISCONFIGURED -> "misconfigured"
            PBlockedReason.UNKNOWN, null -> "unknown"
        }
    }
}

/** Maps a device ID to a stable per-install pseudonym: `dev-` + 8 hex chars of HMAC-SHA256. */
internal class Pseudonymizer(salt: ByteArray) {
    private val key = SecretKeySpec(salt, "HmacSHA256")

    fun pseudonym(deviceId: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(key)
        val digest = mac.doFinal(deviceId.uppercase(Locale.ROOT).toByteArray(Charsets.UTF_8))
        return "dev-" + digest.take(4).joinToString("") { "%02x".format(it) }
    }
}
