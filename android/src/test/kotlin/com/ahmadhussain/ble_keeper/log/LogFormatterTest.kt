package com.ahmadhussain.ble_keeper.log

import com.ahmadhussain.ble_keeper.PBlockedReason
import com.ahmadhussain.ble_keeper.PCharacteristicRef
import com.ahmadhussain.ble_keeper.PDisconnectReason
import com.ahmadhussain.ble_keeper.PEvent
import com.ahmadhussain.ble_keeper.PEventType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Golden lines. The iOS LogFormatterTests use the same expectations; keep
 * both in sync when the format changes.
 */
internal class LogFormatterTest {
    private val ts = 1760347953123L // 2025-10-13T09:32:33.123Z
    private val device = "AA:BB:CC:DD:EE:FF"
    private val raw = LogFormatter(null)

    private fun event(type: PEventType) = PEvent(seq = 7, timestampMs = ts, type = type, deviceId = device)

    @Test
    fun iso_isUtcWithMilliseconds() {
        assertEquals("2025-10-13T09:32:33.123Z", LogFormatter.iso(ts))
    }

    @Test
    fun connected() {
        assertEquals("2025-10-13T09:32:33.123Z #7 connected device=$device", raw.format(event(PEventType.CONNECTED)))
    }

    @Test
    fun disconnected_withCode() {
        val e = event(PEventType.DISCONNECTED).copy(disconnectReason = PDisconnectReason.LINK_LOSS, platformCode = 8)
        assertEquals(
            "2025-10-13T09:32:33.123Z #7 disconnected device=$device reason=linkLoss code=8",
            raw.format(e),
        )
    }

    @Test
    fun reconnecting() {
        assertEquals(
            "2025-10-13T09:32:33.123Z #7 reconnecting device=$device attempt=3",
            raw.format(event(PEventType.RECONNECTING).copy(attempt = 3)),
        )
    }

    @Test
    fun data_logsLengthNotPayload() {
        val e = event(PEventType.DATA).copy(
            characteristic = PCharacteristicRef("s", "12345678-1234-1234-1234-1234567890ac"),
            value = byteArrayOf(0x41, 0x42, 0x43, 0x44),
        )
        val line = raw.format(e)
        assertEquals(
            "2025-10-13T09:32:33.123Z #7 data device=$device char=12345678-1234-1234-1234-1234567890ac len=4",
            line,
        )
        assertFalse(line.contains("ABCD"))
    }

    @Test
    fun restored_listsDevices() {
        val e = PEvent(seq = 1, timestampMs = ts, type = PEventType.RESTORED_AFTER_KILL, deviceIds = listOf("A", "B"))
        assertEquals("2025-10-13T09:32:33.123Z #1 restoredAfterKill devices=A,B", raw.format(e))
    }

    @Test
    fun blocked_quotesAndEscapesDetail() {
        val e = PEvent(
            seq = 2,
            timestampMs = ts,
            type = PEventType.BLOCKED,
            blockedReason = PBlockedReason.MISCONFIGURED,
            detail = "line1\n\"x\"",
        )
        val line = raw.format(e)
        assertEquals("2025-10-13T09:32:33.123Z #2 blocked reason=misconfigured detail=\"line1\\n\\\"x\\\"\"", line)
        assertFalse(line.contains('\n'))
    }

    @Test
    fun pseudonymizer_hidesDeviceId_stablyPerSalt() {
        val a = Pseudonymizer(ByteArray(16) { 1 })
        val b = Pseudonymizer(ByteArray(16) { 2 })
        val line = LogFormatter(a).format(event(PEventType.CONNECTED))

        assertFalse(line.contains(device))
        assertTrue(Regex("device=dev-[0-9a-f]{8}$").containsMatchIn(line))
        assertEquals(a.pseudonym(device), a.pseudonym(device.lowercase()))
        assertNotEquals(a.pseudonym(device), b.pseudonym(device))
    }

    @Test
    fun dataSummary() {
        assertEquals(
            "2025-10-13T09:32:33.123Z #5-64 data device=$device char=12345678-1234-1234-1234-1234567890ac count=60 bytes=240",
            raw.dataSummary(ts, device, "12345678-1234-1234-1234-1234567890ac", 60, 240, 5, 64),
        )
    }

    @Test
    fun note_isQuoted() {
        assertEquals("2025-10-13T09:32:33.123Z note \"a b\"", raw.note(ts, "note", "a b"))
    }
}
