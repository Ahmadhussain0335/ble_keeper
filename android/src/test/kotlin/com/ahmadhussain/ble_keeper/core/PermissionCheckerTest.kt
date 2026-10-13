package com.ahmadhussain.ble_keeper.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class PermissionCheckerTest {
    private val none: (String) -> Boolean = { false }
    private val all: (String) -> Boolean = { true }

    @Test
    fun belowApi31_nothingIsMissing() {
        assertEquals(emptyList(), PermissionChecker.missingForConnect(30, none))
    }

    @Test
    fun api31_requiresBluetoothConnect() {
        assertEquals(listOf(PermissionChecker.BLUETOOTH_CONNECT), PermissionChecker.missingForConnect(31, none))
        assertEquals(emptyList(), PermissionChecker.missingForConnect(31, all))
    }

    @Test
    fun notificationsHidden_onlyFromApi33() {
        assertFalse(PermissionChecker.notificationsHidden(32, none))
        assertTrue(PermissionChecker.notificationsHidden(33, none))
        assertFalse(PermissionChecker.notificationsHidden(33, all))
    }
}
