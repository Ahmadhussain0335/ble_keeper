package com.ahmadhussain.ble_keeper

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class BleKeeperPluginTest {
    @Test
    fun hostCalls_beforeAttach_failWithNotAttached() {
        val plugin = BleKeeperPlugin()

        val error = assertFailsWith<BleKeeperFlutterError> { plugin.registerBackgroundHandler(1, 2) }

        assertEquals("not_attached", error.code)
    }

    @Test
    fun detach_beforeAttach_doesNotThrow() {
        BleKeeperPlugin().detach()
    }
}
