package com.ahmadhussain.ble_keeper.gatt

import com.ahmadhussain.ble_keeper.PDisconnectReason
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class GattStatusTest {
    private fun reason(status: Int, up: Boolean = true, local: Boolean = false) =
        GattStatus.disconnectReason(status, up, local)

    @Test
    fun hciCodes_mapToReasons() {
        assertEquals(PDisconnectReason.PEER_TERMINATED, reason(0x13))
        assertEquals(PDisconnectReason.LINK_LOSS, reason(0x08))
        assertEquals(PDisconnectReason.LINK_LOSS, reason(0x22))
        assertEquals(PDisconnectReason.LOCAL_TERMINATED, reason(0x16))
        assertEquals(PDisconnectReason.CONNECT_FAILED, reason(0x3E))
        assertEquals(PDisconnectReason.CONNECT_FAILED, reason(147))
    }

    @Test
    fun status133_dependsOnWhetherTheLinkWasUp() {
        assertEquals(PDisconnectReason.CONNECT_FAILED, reason(133, up = false))
        assertEquals(PDisconnectReason.UNKNOWN, reason(133, up = true))
    }

    @Test
    fun localRequest_winsOverStatus() {
        assertEquals(PDisconnectReason.LOCAL_TERMINATED, reason(0x13, local = true))
    }

    @Test
    fun unknownStatus_isUnknown() {
        assertEquals(PDisconnectReason.UNKNOWN, reason(0x05))
    }

    @Test
    fun peerTerminated_afterStableLink_reconnectsAtOnce_butShortLivedLinkBacksOff() {
        assertFalse(GattStatus.needsBackoff(0x13, linkWasUp = true))
        assertTrue(GattStatus.needsBackoff(0x13, linkWasUp = false))
    }

    @Test
    fun backoff_forImmediateFailuresAnd133_notForLinkLoss() {
        assertTrue(GattStatus.needsBackoff(133, linkWasUp = true))
        assertTrue(GattStatus.needsBackoff(0x3E, linkWasUp = false))
        assertFalse(GattStatus.needsBackoff(0x08, linkWasUp = true))
    }
}
