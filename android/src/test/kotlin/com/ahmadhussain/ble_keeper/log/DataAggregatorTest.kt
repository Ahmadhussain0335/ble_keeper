package com.ahmadhussain.ble_keeper.log

import com.ahmadhussain.ble_keeper.PCharacteristicRef
import com.ahmadhussain.ble_keeper.PEvent
import com.ahmadhussain.ble_keeper.PEventType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class DataAggregatorTest {
    private val formatter = LogFormatter(null)

    private fun data(seq: Long, device: String, char: String, size: Int) = PEvent(
        seq = seq,
        timestampMs = 0,
        type = PEventType.DATA,
        deviceId = device,
        characteristic = PCharacteristicRef("s", char),
        value = ByteArray(size),
    )

    @Test
    fun summarisesPerDeviceAndCharacteristic_thenStartsOver() {
        val a = DataAggregator()
        a.add(data(1, "A", "c1", 4))
        a.add(data(2, "A", "c1", 4))
        a.add(data(3, "B", "c1", 2))
        a.add(data(4, "A", "c1", 4))

        val lines = a.drain(1760347953123L, formatter)

        assertEquals(
            listOf(
                "2025-10-13T09:32:33.123Z #1-4 data device=A char=c1 count=3 bytes=12",
                "2025-10-13T09:32:33.123Z #3-3 data device=B char=c1 count=1 bytes=2",
            ),
            lines,
        )
        assertTrue(a.isEmpty)
        assertEquals(emptyList(), a.drain(0, formatter))
    }
}
