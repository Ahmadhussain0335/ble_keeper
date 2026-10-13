package com.ahmadhussain.ble_keeper.gatt

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class ConnectStrategyTest {
    private val s = ConnectStrategy(directAttemptsBeforeAuto = 3, directWindowMs = 120_000, stableLinkMs = 30_000)

    @Test
    fun firstAttempt_isDirect() {
        assertFalse(s.useAutoConnect(0))
    }

    @Test
    fun afterThreeDirectFailures_switchesToAutoConnect() {
        repeat(2) {
            s.onAttempt(autoConnect = false, nowMs = 0)
            s.onConnectFailed(wasAutoConnect = false)
        }
        assertFalse(s.useAutoConnect(1_000))
        s.onConnectFailed(wasAutoConnect = false)
        assertTrue(s.useAutoConnect(1_000))
    }

    @Test
    fun afterTwoMinutesOfDirectAttempts_switchesToAutoConnect() {
        s.onAttempt(autoConnect = false, nowMs = 10_000)
        assertFalse(s.useAutoConnect(129_999))
        assertTrue(s.useAutoConnect(130_000))
    }

    @Test
    fun autoConnectFailures_doNotCountAsDirectFailures() {
        repeat(5) { s.onConnectFailed(wasAutoConnect = true) }
        assertFalse(s.useAutoConnect(0))
    }

    @Test
    fun afterAConnection_alwaysAutoConnect() {
        s.onConnected()
        assertTrue(s.useAutoConnect(0))
    }

    @Test
    fun bluetoothOff_startsOverWithDirect() {
        s.onConnected()
        s.onBluetoothOff()
        assertFalse(s.useAutoConnect(0))
    }

    @Test
    fun stability_needsThirtySecondsOfReadyLink() {
        assertFalse(s.isStable(readyAtMs = null, nowMs = 100_000))
        assertFalse(s.isStable(readyAtMs = 0, nowMs = 29_999))
        assertTrue(s.isStable(readyAtMs = 0, nowMs = 30_000))
    }
}
