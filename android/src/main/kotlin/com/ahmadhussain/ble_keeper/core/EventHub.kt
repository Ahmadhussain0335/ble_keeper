package com.ahmadhussain.ble_keeper.core

import com.ahmadhussain.ble_keeper.PEvent

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
    private val capacity: Int = 1000,
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

    val pending: Int get() = buffer.size
    val hasUiSink: Boolean get() = sinks.any { !it.isBackground }
    val hasSink: Boolean get() = sinks.isNotEmpty()

    fun publish(event: PEvent) {
        val stamped = event.copy(seq = nextSeq++)
        onPublished(stamped)
        buffer.addLast(stamped)
        var dropped = 0
        while (buffer.size > capacity) {
            buffer.removeFirst()
            dropped++
        }
        if (dropped > 0) onDropped(dropped)
        drain()
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
            } else {
                sinks.remove(sink)
            }
            drain()
        }
    }
}
