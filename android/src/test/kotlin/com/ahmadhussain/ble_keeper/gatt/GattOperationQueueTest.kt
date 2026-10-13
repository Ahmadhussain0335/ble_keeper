package com.ahmadhussain.ble_keeper.gatt

import com.ahmadhussain.ble_keeper.core.KeeperException
import kotlinx.coroutines.async
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class GattOperationQueueTest {

    @Test
    fun execute_returnsCompletedValue() = runTest {
        val q = GattOperationQueue()
        val result = async { q.execute<Int>("mtu") { true } }
        runCurrent()
        q.complete("mtu", 247)
        assertEquals(247, result.await())
    }

    @Test
    fun operations_runOneAtATime_inOrder() = runTest {
        val q = GattOperationQueue()
        val started = mutableListOf<String>()
        val a = async { q.execute<Unit>("a") { started.add("a"); true } }
        val b = async { q.execute<Unit>("b") { started.add("b"); true } }
        runCurrent()
        assertEquals(listOf("a"), started)

        q.complete("a", Unit)
        a.await()
        runCurrent()
        assertEquals(listOf("a", "b"), started)
        q.complete("b", Unit)
        b.await()
    }

    @Test
    fun staleCompletion_forAnotherOperation_isIgnored() = runTest {
        val q = GattOperationQueue()
        val r = async { q.execute<Int>("read") { true } }
        runCurrent()
        q.complete("write", 1)
        q.complete("read", 2)
        assertEquals(2, r.await())
    }

    @Test
    fun rejectedStart_failsWithGattError() = runTest {
        val q = GattOperationQueue()
        val e = assertFailsWith<KeeperException> { q.execute<Unit>("write") { false } }
        assertEquals("gatt_error", e.code)
    }

    @Test
    fun missingCallback_timesOut() = runTest {
        val q = GattOperationQueue(timeoutMs = 1000)
        val r = async { runCatching { q.execute<Unit>("cccd") { true } } }
        advanceTimeBy(1001)
        val e = r.await().exceptionOrNull() as KeeperException
        assertEquals("timeout", e.code)
    }

    @Test
    fun fail_propagatesError() = runTest {
        val q = GattOperationQueue()
        val r = async { runCatching { q.execute<Unit>("read") { true } } }
        runCurrent()
        q.fail("read", KeeperException("gatt_error", "status 5"))
        assertEquals("gatt_error", (r.await().exceptionOrNull() as KeeperException).code)
    }

    @Test
    fun close_failsRunningAndLaterOperations_untilReopened() = runTest {
        val q = GattOperationQueue()
        val running = async { runCatching { q.execute<Unit>("read") { true } } }
        runCurrent()

        q.close(KeeperException("not_connected", "gone"))

        assertEquals("not_connected", (running.await().exceptionOrNull() as KeeperException).code)
        assertFailsWith<KeeperException> { q.execute<Unit>("write") { true } }

        q.reopen()
        val again = async { q.execute<Int>("mtu") { true } }
        runCurrent()
        q.complete("mtu", 23)
        assertEquals(23, again.await())
    }
}
