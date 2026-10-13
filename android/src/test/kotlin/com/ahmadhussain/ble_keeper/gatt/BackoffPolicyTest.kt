package com.ahmadhussain.ble_keeper.gatt

import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class BackoffPolicyTest {
    private fun fixedRandom(value: Double) = object : Random() {
        override fun nextBits(bitCount: Int) = 0
        override fun nextDouble() = value
    }

    @Test
    fun withoutJitter_doublesUntilCap() {
        val p = BackoffPolicy(baseMs = 1000, maxMs = 8000, jitter = 0.0)
        assertEquals(listOf(1000L, 2000L, 4000L, 8000L, 8000L), (1..5).map { p.delayMs(it) })
    }

    @Test
    fun jitter_staysWithinBounds() {
        val low = BackoffPolicy(baseMs = 1000, jitter = 0.2, random = fixedRandom(0.0))
        val high = BackoffPolicy(baseMs = 1000, jitter = 0.2, random = fixedRandom(0.999999))
        assertEquals(800L, low.delayMs(1))
        assertTrue(high.delayMs(1) in 1199L..1200L)
    }

    @Test
    fun hugeAttempt_doesNotOverflow() {
        val p = BackoffPolicy(baseMs = 1000, maxMs = 60_000, jitter = 0.0)
        assertEquals(60_000L, p.delayMs(10_000))
    }

    @Test
    fun attemptZeroOrNegative_usesBase() {
        val p = BackoffPolicy(baseMs = 1000, jitter = 0.0)
        assertEquals(1000L, p.delayMs(0))
    }
}
