package com.ahmadhussain.ble_keeper.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class ExitReasonsTest {
    private val userRequested = ExitReasons.REASON_USER_REQUESTED
    private val lowMemory = 3

    @Test
    fun newForceStop_withSessions_isReported() {
        assertTrue(ExitReasons.isUnreportedForceStop(userRequested, 2000, 1000, hadSessions = true))
    }

    @Test
    fun alreadyReported_isIgnored() {
        assertFalse(ExitReasons.isUnreportedForceStop(userRequested, 1000, 1000, hadSessions = true))
    }

    @Test
    fun withoutSessions_isIgnored() {
        assertFalse(ExitReasons.isUnreportedForceStop(userRequested, 2000, 1000, hadSessions = false))
    }

    private fun forceStop(exitMs: Long, updatedMs: Long?, sdk: Int) =
        ExitReasons.isUnreportedForceStop(userRequested, exitMs, 1000, hadSessions = true, appUpdatedAtMs = updatedMs, sdkInt = sdk)

    @Test
    fun belowApi33_exitAtTheUpdate_isIgnored() {
        val update = 1_000_000L
        assertFalse(forceStop(update - 2_000, update, sdk = 32)) // installer kill just before
        assertFalse(forceStop(update + 3_000, update, sdk = 32))
        assertFalse(forceStop(update - 30_000, update, sdk = 30)) // window edge
    }

    @Test
    fun belowApi33_realForceStopSoonAfterTheUpdate_isReported() {
        // Hardware test B1: force-stop about 13 s after the update was hidden (F3).
        val update = 1_000_000L
        assertTrue(forceStop(update + 13_000, update, sdk = 32))
        assertTrue(forceStop(update + 5_001, update, sdk = 32))
        assertTrue(forceStop(update - 31_000, update, sdk = 32))
    }

    @Test
    fun api33AndLater_updateWindowNotApplied() {
        // Updates have REASON_PACKAGE_UPDATED there; a user-requested exit is a force-stop.
        val update = 1_000_000L
        assertTrue(forceStop(update + 1_000, update, sdk = 33))
        assertTrue(forceStop(update + 13_000, update, sdk = 36))
    }

    @Test
    fun unknownUpdateTime_isReported() {
        assertTrue(forceStop(2_000, null, sdk = 30))
    }

    @Test
    fun otherReasons_areIgnored() {
        assertFalse(ExitReasons.isUnreportedForceStop(lowMemory, 2000, 1000, hadSessions = true))
    }
}
