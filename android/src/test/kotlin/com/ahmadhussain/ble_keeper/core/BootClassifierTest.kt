package com.ahmadhussain.ble_keeper.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class BootClassifierTest {
    @Test
    fun broadcastSoonAfterBoot_isARealBoot() {
        assertTrue(BootClassifier.isRealBoot(uptimeMs = 45_000, wasForceStopped = null))
        assertTrue(BootClassifier.isRealBoot(uptimeMs = 45_000, wasForceStopped = false))
    }

    @Test
    fun broadcastHoursAfterBoot_isAStoppedStateExit() {
        // Hardware test A6c: uptime was hours when the force-stopped app was opened.
        assertFalse(BootClassifier.isRealBoot(uptimeMs = 5 * 3_600_000L, wasForceStopped = null))
    }

    @Test
    fun forceStoppedFlag_winsEvenRightAfterBoot() {
        assertFalse(BootClassifier.isRealBoot(uptimeMs = 30_000, wasForceStopped = true))
    }

    @Test
    fun boundary_isInclusive() {
        assertTrue(BootClassifier.isRealBoot(BootClassifier.MAX_BOOT_UPTIME_MS, null))
        assertFalse(BootClassifier.isRealBoot(BootClassifier.MAX_BOOT_UPTIME_MS + 1, null))
    }
}
