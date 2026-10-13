package com.ahmadhussain.ble_keeper.gatt

import com.ahmadhussain.ble_keeper.core.KeeperException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout

/**
 * Runs one GATT operation at a time.
 *
 * Android's BluetoothGatt allows only one outstanding operation; starting a
 * second before the first callback arrives makes the call return false (or
 * silently drops it on older stacks). Each operation is started by [execute]
 * and finished by [complete] / [fail] from the matching callback.
 */
internal class GattOperationQueue(private val timeoutMs: Long = 10_000) {

    private class Pending(val name: String, val result: CompletableDeferred<Any?>)

    private val mutex = Mutex()

    @Volatile
    private var pending: Pending? = null

    @Volatile
    private var closed: KeeperException? = null

    /**
     * Starts [name] by calling [start] and waits for its completion.
     * [start] returns false when the stack refused the request.
     */
    @Suppress("UNCHECKED_CAST")
    suspend fun <T> execute(name: String, start: () -> Boolean): T = mutex.withLock {
        closed?.let { throw it }
        val p = Pending(name, CompletableDeferred())
        pending = p
        try {
            if (!start()) throw KeeperException("gatt_error", "$name was rejected by the Bluetooth stack")
            withTimeout(timeoutMs) { p.result.await() } as T
        } catch (e: TimeoutCancellationException) {
            throw KeeperException("timeout", "$name timed out after $timeoutMs ms")
        } finally {
            pending = null
        }
    }

    /** Completes the running operation if it is [name]; ignores stale callbacks. */
    fun complete(name: String, value: Any?) {
        val p = pending ?: return
        if (p.name == name) p.result.complete(value)
    }

    fun fail(name: String, error: KeeperException) {
        val p = pending ?: return
        if (p.name == name) p.result.completeExceptionally(error)
    }

    /** Fails the running operation and every later one, for example on disconnect. */
    fun close(error: KeeperException) {
        closed = error
        pending?.result?.completeExceptionally(error)
    }

    /** Accepts operations again after [close], for a new connection. */
    fun reopen() {
        closed = null
    }
}
