package com.ahmadhussain.ble_keeper.core

import com.ahmadhussain.ble_keeper.PEvent
import com.ahmadhussain.ble_keeper.PEventType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class EventHubTest {

    private class FakeSink(override val isBackground: Boolean) : EventHub.Sink {
        val batches = mutableListOf<List<PEvent>>()
        val pendingAcks = ArrayDeque<(Boolean) -> Unit>()
        var autoAck: Boolean? = null

        override fun deliver(events: List<PEvent>, done: (Boolean) -> Unit) {
            batches.add(events)
            val ack = autoAck
            if (ack != null) done(ack) else pendingAcks.addLast(done)
        }

        fun ack(ok: Boolean = true) = pendingAcks.removeFirst()(ok)
    }

    private fun event() = PEvent(seq = 0, timestampMs = 1, type = PEventType.CONNECTED, deviceId = "A")

    @Test
    fun publish_assignsIncreasingSeq_andBuffersWithoutSink() {
        val published = mutableListOf<Long>()
        var noSinkCalls = 0
        val hub = EventHub(onPublished = { published.add(it.seq) })
        hub.onNoSink = { noSinkCalls++ }

        hub.publish(event())
        hub.publish(event())

        assertEquals(listOf(1L, 2L), published)
        assertEquals(2, hub.pending)
        assertEquals(2, noSinkCalls)
    }

    @Test
    fun attach_flushesBuffer_andAckRemovesBatch() {
        val hub = EventHub()
        hub.publish(event())
        hub.publish(event())
        val sink = FakeSink(isBackground = false)

        hub.attach(sink)

        assertEquals(listOf(1L, 2L), sink.batches.single().map { it.seq })
        assertEquals(2, hub.pending)
        sink.ack()
        assertEquals(0, hub.pending)
    }

    @Test
    fun onlyOneBatchInFlight_nextBatchAfterAck() {
        val hub = EventHub()
        val sink = FakeSink(isBackground = false)
        hub.attach(sink)

        hub.publish(event())
        hub.publish(event())
        hub.publish(event())

        assertEquals(1, sink.batches.size)
        sink.ack()
        assertEquals(listOf(2L, 3L), sink.batches[1].map { it.seq })
    }

    @Test
    fun failedDelivery_keepsSinkAndEvents_andRetryRedelivers() {
        val hub = EventHub()
        var failures = 0
        hub.onDeliveryFailed = { failures++ }
        val sink = FakeSink(isBackground = false)
        hub.attach(sink)
        hub.publish(event())

        sink.ack(ok = false)

        assertEquals(1, hub.pending)
        assertTrue(hub.hasSink)
        assertEquals(1, failures)
        assertEquals(1, sink.batches.size) // no immediate retry loop

        hub.retry()
        assertEquals(listOf(1L), sink.batches[1].map { it.seq })
        sink.ack()
        assertEquals(0, hub.pending)
    }

    @Test
    fun uiSink_isPreferredOverBackgroundSink() {
        val hub = EventHub()
        val background = FakeSink(isBackground = true).apply { autoAck = true }
        val ui = FakeSink(isBackground = false).apply { autoAck = true }
        hub.attach(background)
        hub.attach(ui)

        hub.publish(event())

        assertTrue(background.batches.isEmpty())
        assertEquals(1, ui.batches.size)
    }

    @Test
    fun detachingInFlightSink_redeliversToNextSink_andIgnoresLateAck() {
        val hub = EventHub()
        val first = FakeSink(isBackground = false)
        val second = FakeSink(isBackground = true)
        hub.attach(first)
        hub.attach(second)
        hub.publish(event())

        hub.detach(first)
        assertEquals(listOf(1L), second.batches.single().map { it.seq })

        first.ack() // late, must be ignored
        assertEquals(1, hub.pending)
        second.ack()
        assertEquals(0, hub.pending)
    }

    @Test
    fun capacity_dropsOldest_andReportsCount() {
        var dropped = 0
        val hub = EventHub(capacity = 3, onDropped = { dropped += it })
        repeat(5) { hub.publish(event()) }

        assertEquals(3, hub.pending)
        assertEquals(2, dropped)
        val sink = FakeSink(isBackground = false)
        hub.attach(sink)
        assertEquals(listOf(3L, 4L, 5L), sink.batches.single().map { it.seq })
    }

    @Test
    fun droppedWhileInFlight_ackRemovesBySeq() {
        val hub = EventHub(capacity = 2, maxBatch = 2)
        val sink = FakeSink(isBackground = false)
        hub.attach(sink)
        hub.publish(event()) // seq 1, in flight
        hub.publish(event()) // seq 2
        hub.publish(event()) // seq 3, drops seq 1 from the buffer

        sink.ack()

        assertEquals(listOf(2L, 3L), sink.batches[1].map { it.seq })
    }

    @Test
    fun batches_areLimitedToMaxBatch() {
        val hub = EventHub(maxBatch = 2)
        repeat(5) { hub.publish(event()) }
        val sink = FakeSink(isBackground = false).apply { autoAck = true }

        hub.attach(sink)

        assertEquals(listOf(2, 2, 1), sink.batches.map { it.size })
    }
}
