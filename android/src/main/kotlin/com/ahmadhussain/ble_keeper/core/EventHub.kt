package com.ahmadhussain.ble_keeper.core

import com.ahmadhussain.ble_keeper.PEvent
import com.ahmadhussain.ble_keeper.PEventType

/**
 * Buffers events and delivers them to one Dart receiver at a time.
 *
 * Not thread-safe: every call must happen on the main thread (KeeperRuntime
 * guarantees this), because Flutter platform channels must be used from the
 * platform thread.
 *
 * Delivery is at-least-once. A batch leaves the buffer only after the receiver
 * acknowledges it; Dart drops duplicates by [PEvent.seq].
 */
internal class EventHub(
    /** Maximum buffered Data events; the oldest Data event is dropped first. */
    private val capacity: Int = 1000,
    /**
     * Maximum buffered non-Data events (state changes, Blocked,
     * RestoredAfterKill). They are rare and never evicted to make room for
     * Data; only this separate cap bounds them.
     */
    private val controlCapacity: Int = 1000,
    private val maxBatch: Int = 100,
    private val onPublished: (PEvent) -> Unit = {},
    private val onDropped: (count: Int) -> Unit = {},
) {
    /** A Dart isolate that receives events. */
    interface Sink {
        /** True for the headless background engine. UI sinks are preferred. */
        val isBackground: Boolean

        /** Delivers [events]; calls [done] with true once Dart acknowledged them. */
        fun deliver(events: List<PEvent>, done: (Boolean) -> Unit)
    }

    private val buffer = ArrayDeque<PEvent>()
    private val sinks = mutableListOf<Sink>()
    private var nextSeq = 1L

    /** Identifies the batch awaiting an acknowledgement; null when none is. */
    private var inFlight: Any? = null
    private var inFlightSink: Sink? = null

    /** Called when events are waiting and no sink is attached. */
    var onNoSink: () -> Unit = {}

    /**
     * Called when a delivery failed (timeout, channel error). The sink stays
     * attached; dead engines are removed by [detach]. The owner calls
     * [retry] later.
     */
    var onDeliveryFailed: () -> Unit = {}

    val pending: Int get() = buffer.size
    val hasUiSink: Boolean get() = sinks.any { !it.isBackground }
    val hasSink: Boolean get() = sinks.isNotEmpty()

    fun publish(event: PEvent) {
        val stamped = event.copy(seq = nextSeq++)
        onPublished(stamped)
        buffer.addLast(stamped)
        val dropped = evictOldest(isData = true, max = capacity) + evictOldest(isData = false, max = controlCapacity)
        if (dropped > 0) onDropped(dropped)
        drain()
    }

    /** Removes the oldest events of one class until at most [max] remain. */
    private fun evictOldest(isData: Boolean, max: Int): Int {
        var count = buffer.count { (it.type == PEventType.DATA) == isData }
        var dropped = 0
        val it = buffer.iterator()
        while (count > max && it.hasNext()) {
            if ((it.next().type == PEventType.DATA) == isData) {
                it.remove()
                count--
                dropped++
            }
        }
        return dropped
    }

    fun attach(sink: Sink) {
        if (sink !in sinks) sinks.add(sink)
        drain()
    }

    fun detach(sink: Sink) {
        sinks.remove(sink)
        if (inFlightSink === sink) {
            // Its acknowledgement may never come (engine destroyed); resend
            // the batch to the next sink.
            inFlight = null
            inFlightSink = null
            drain()
        }
    }

    /** Tries delivering again after [onDeliveryFailed]. */
    fun retry() = drain()

    private fun drain() {
        if (inFlight != null || buffer.isEmpty()) return
        val sink = sinks.firstOrNull { !it.isBackground } ?: sinks.firstOrNull()
        if (sink == null) {
            onNoSink()
            return
        }
        val batch = buffer.take(maxBatch)
        val lastSeq = batch.last().seq
        val token = Any()
        inFlight = token
        inFlightSink = sink
        sink.deliver(batch) { ok ->
            if (inFlight !== token) return@deliver
            inFlight = null
            inFlightSink = null
            if (ok) {
                // Remove by seq: events may have been dropped from the front
                // while the batch was in flight.
                while (buffer.isNotEmpty() && buffer.first().seq <= lastSeq) buffer.removeFirst()
                drain()
            } else {
                onDeliveryFailed()
            }
        }
    }
}
