package com.ahmadhussain.ble_keeper.log

import java.io.File
import java.nio.file.Files
import java.util.concurrent.Executors
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class RotatingEventLogTest {
    private val dir: File = Files.createTempDirectory("log").toFile()
    private val executor = Executors.newSingleThreadScheduledExecutor()
    private val log = RotatingEventLog(dir, "events.log", maxBytes = 20, executor = executor)

    @AfterTest
    fun cleanUp() {
        executor.shutdownNow()
        dir.deleteRecursively()
    }

    private fun flush() = log.flush()

    @Test
    fun append_writesOneLinePerCall() {
        log.append("a")
        log.append("b")
        flush()
        assertEquals("a\nb\n", File(dir, "events.log").readText())
    }

    @Test
    fun rotation_keepsTwoFiles_andDropsTheOldest() {
        log.append("0123456789") // 11 bytes
        log.append("abcdefghij") // would make 22 > 20: rotate
        log.append("ABCDEFGHIJ") // rotate again, first line is gone
        flush()

        assertEquals("abcdefghij\n", File(dir, "events.log.1").readText())
        assertEquals("ABCDEFGHIJ\n", File(dir, "events.log").readText())
    }

    @Test
    fun lines_areBufferedUntilFlush_andFlushedAutomatically() {
        val delayed = RotatingEventLog(dir, "buffered.log", maxBytes = 1_000, executor = executor, flushDelayMs = 50)
        delayed.append("x")
        executor.submit {}.get()
        assertFalse(File(dir, "buffered.log").readText().contains("x"))
        Thread.sleep(200)
        executor.submit {}.get()
        assertEquals("x\n", File(dir, "buffered.log").readText())
    }

    @Test
    fun export_concatenatesPreviousThenCurrent() {
        log.append("0123456789")
        log.append("abcdefghij")
        val out = log.export(File(dir, "export/out.log"))
        assertEquals("0123456789\nabcdefghij\n", out.readText())
    }

    @Test
    fun export_withoutLog_isEmptyFile() {
        val out = log.export(File(dir, "export/out.log"))
        assertTrue(out.exists())
        assertEquals("", out.readText())
    }

    @Test
    fun clear_removesLogsAndExports() {
        log.append("0123456789")
        log.append("abcdefghij")
        val exportDir = File(dir, "export")
        log.export(File(exportDir, "out.log"))

        log.clear(exportDir)

        assertFalse(File(dir, "events.log").exists())
        assertFalse(File(dir, "events.log.1").exists())
        assertEquals(0, exportDir.listFiles()?.size ?: 0)
    }
}
