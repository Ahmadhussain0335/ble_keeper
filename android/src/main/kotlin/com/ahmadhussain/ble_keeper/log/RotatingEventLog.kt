package com.ahmadhussain.ble_keeper.log

import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.util.concurrent.Callable
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Append-only text log split over two files: `events.log` (current) and
 * `events.log.1` (previous). When the current file would exceed [maxBytes] it
 * becomes the previous file, so at most about 2 x [maxBytes] is kept.
 *
 * All file access runs on [executor] (a single thread). The current file
 * stays open behind a buffer that is flushed [flushDelayMs] after the first
 * unflushed line, before rotation, export and clear. A process kill can lose
 * at most that much of the newest log.
 */
internal class RotatingEventLog(
    private val dir: File,
    private val fileName: String,
    private val maxBytes: Long,
    private val executor: ScheduledExecutorService,
    private val flushDelayMs: Long = 2_000,
) {
    private val current get() = File(dir, fileName)
    private val previous get() = File(dir, "$fileName.1")

    // Executor thread only.
    private var out: OutputStream? = null
    private var size = 0L
    private var flushScheduled = false

    fun append(line: String) {
        executor.execute { appendNow(line) }
    }

    /** Writes buffered lines to disk. Blocks until done. */
    fun flush() {
        executor.submit { flushNow() }.get()
    }

    /**
     * Writes previous + current into [target] and returns it. Earlier exports
     * in the same directory are deleted, so copies do not pile up. Blocks
     * until done.
     */
    fun export(target: File): File = executor.submit(Callable {
        flushNow()
        target.parentFile?.apply {
            mkdirs()
            listFiles()?.forEach { it.delete() }
        }
        target.outputStream().use { o ->
            for (f in listOf(previous, current)) {
                if (f.exists()) f.inputStream().use { it.copyTo(o) }
            }
        }
        target
    }).get()

    /** Deletes both log files and everything in [extraDirs]. Blocks until done. */
    fun clear(vararg extraDirs: File) {
        executor.submit {
            closeNow()
            previous.delete()
            current.delete()
            for (d in extraDirs) d.listFiles()?.forEach { it.delete() }
        }.get()
    }

    private fun appendNow(line: String) {
        try {
            val bytes = (line + "\n").toByteArray(Charsets.UTF_8)
            if (out == null) open()
            if (size > 0 && size + bytes.size > maxBytes) {
                closeNow()
                previous.delete()
                current.renameTo(previous)
                open()
            }
            out?.write(bytes)
            size += bytes.size
            if (!flushScheduled) {
                flushScheduled = true
                executor.schedule({ flushNow() }, flushDelayMs, TimeUnit.MILLISECONDS)
            }
        } catch (_: Exception) {
            // Logging must never take the connection down (disk full, etc.).
            closeNow()
        }
    }

    private fun open() {
        dir.mkdirs()
        size = if (current.exists()) current.length() else 0L
        out = BufferedOutputStream(FileOutputStream(current, true), 16 * 1024)
    }

    private fun flushNow() {
        flushScheduled = false
        try {
            out?.flush()
        } catch (_: Exception) {
            closeNow()
        }
    }

    private fun closeNow() {
        flushScheduled = false
        try {
            out?.close()
        } catch (_: Exception) {
            // Nothing to do; the next append reopens.
        }
        out = null
    }
}
