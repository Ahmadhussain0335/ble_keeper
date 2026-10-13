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

    @Test
    fun exitAtAnAppUpdate_isIgnored() {
        assertFalse(
            ExitReasons.isUnreportedForceStop(userRequested, 100_000, 1000, hadSessions = true, appUpdatedAtMs = 99_000),
        )
        assertTrue(
            ExitReasons.isUnreportedForceStop(userRequested, 500_000, 1000, hadSessions = true, appUpdatedAtMs = 99_000),
        )
    }

    @Test
    fun otherReasons_areIgnored() {
        assertFalse(ExitReasons.isUnreportedForceStop(lowMemory, 2000, 1000, hadSessions = true))
    }
}
