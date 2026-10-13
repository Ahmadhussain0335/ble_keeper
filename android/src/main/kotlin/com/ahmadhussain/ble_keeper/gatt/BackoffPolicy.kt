package com.ahmadhussain.ble_keeper.gatt

import kotlin.math.min
import kotlin.random.Random

/**
 * Exponential backoff with jitter: base, 2x base, 4x base ... capped at
 * [maxMs], each scaled by a random factor in [1 - jitter, 1 + jitter] so
 * several devices do not retry in lockstep.
 */
internal class BackoffPolicy(
    private val baseMs: Long = 1_000,
    private val maxMs: Long = 60_000,
    private val jitter: Double = 0.2,
    private val random: Random = Random.Default,
) {
    /** Delay before attempt number [attempt] (1-based). */
    fun delayMs(attempt: Int): Long {
        val shift = (attempt - 1).coerceIn(0, 30)
        val raw = min(maxMs, baseMs shl shift)
        val factor = 1.0 + (random.nextDouble() * 2.0 - 1.0) * jitter
        return (raw * factor).toLong().coerceAtLeast(0)
    }
}
