package com.ahmadhussain.ble_keeper.log

import com.ahmadhussain.ble_keeper.PEvent

/**
 * Collects Data events between log flushes so the log gets one summary line
 * per device and characteristic per interval instead of one line (and one
 * disk write) per notification. Not thread-safe; the runtime uses it on the
 * main thread.
 */
internal class DataAggregator {
    private data class Key(val deviceId: String, val characteristic: String)

    private class Bucket(val firstSeq: Long) {
        var lastSeq = firstSeq
        var count = 0
        var bytes = 0L
    }

    private val buckets = LinkedHashMap<Key, Bucket>()

    val isEmpty: Boolean get() = buckets.isEmpty()

    fun add(e: PEvent) {
        val key = Key(e.deviceId.orEmpty(), e.characteristic?.characteristicUuid.orEmpty())
        val b = buckets.getOrPut(key) { Bucket(e.seq) }
        b.lastSeq = e.seq
        b.count++
        b.bytes += e.value?.size ?: 0
    }

    /** Summary lines for everything collected since the last drain. */
    fun drain(nowMs: Long, formatter: LogFormatter): List<String> {
        val lines = buckets.map { (k, b) ->
            formatter.dataSummary(nowMs, k.deviceId, k.characteristic, b.count, b.bytes, b.firstSeq, b.lastSeq)
        }
        buckets.clear()
        return lines
    }
}
