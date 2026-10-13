package com.ahmadhussain.ble_keeper.gatt

/**
 * Decides how to connect, independent of Android APIs so it can be tested.
 *
 * Direct connects (autoConnect = false) are fast but time out after about
 * 30 s and keep the radio scanning at a high duty cycle. autoConnect = true
 * waits without timing out at a low duty cycle, but only reliably finds
 * devices the stack has seen. So: connect directly at first, and switch to
 * autoConnect once the device has connected in this process, after
 * [directAttemptsBeforeAuto] failed direct attempts, or after
 * [directWindowMs] of trying. A device that is absent after a reboot or a
 * sticky restart therefore stops draining the battery within minutes.
 *
 * Times are monotonic milliseconds (SystemClock.elapsedRealtime).
 */
internal class ConnectStrategy(
    private val directAttemptsBeforeAuto: Int = 3,
    private val directWindowMs: Long = 2 * 60_000L,
    /** Some stacks silently drop a long-pending autoConnect; recreate it after this. */
    val autoConnectWatchdogMs: Long = 30 * 60_000L,
    /** A link must stay up this long before the attempt counter resets. */
    private val stableLinkMs: Long = 30_000L,
) {
    private var everConnected = false
    private var directFailures = 0
    private var firstDirectAtMs: Long? = null

    fun useAutoConnect(nowMs: Long): Boolean {
        if (everConnected) return true
        if (directFailures >= directAttemptsBeforeAuto) return true
        val first = firstDirectAtMs ?: return false
        return nowMs - first >= directWindowMs
    }

    fun onAttempt(autoConnect: Boolean, nowMs: Long) {
        if (!autoConnect && firstDirectAtMs == null) firstDirectAtMs = nowMs
    }

    /** A connect attempt ended before the link was up. */
    fun onConnectFailed(wasAutoConnect: Boolean) {
        if (!wasAutoConnect) directFailures++
    }

    fun onConnected() {
        everConnected = true
        directFailures = 0
        firstDirectAtMs = null
    }

    /** Turning Bluetooth off can clear the stack's device cache; start over. */
    fun onBluetoothOff() {
        everConnected = false
        directFailures = 0
        firstDirectAtMs = null
    }

    /** True when a link that became ready at [readyAtMs] counts as stable at [nowMs]. */
    fun isStable(readyAtMs: Long?, nowMs: Long): Boolean =
        readyAtMs != null && nowMs - readyAtMs >= stableLinkMs
}
