package com.ahmadhussain.ble_keeper.log

import java.io.File
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService

/**
 * Append-only text log split over two files: `events.log` (current) and
 * `events.log.1` (previous). When the current file would exceed [maxBytes] it
 * becomes the previous file, so at most about 2 x [maxBytes] is kept.
 *
 * All file access runs on [executor] (a single thread), so callers never
 * block on disk IO and lines are never interleaved.
 */
internal class RotatingEventLog(
    private val dir: File,
    private val fileName: String,
    private val maxBytes: Long,
    private val executor: ExecutorService,
) {
    private val current get() = File(dir, fileName)
    private val previous get() = File(dir, "$fileName.1")

    fun append(line: String) {
        executor.execute { appendNow(line) }
    }

    /** Writes previous + current into [target] and returns it. Blocks until done. */
    fun export(target: File): File = executor.submit(Callable {
        target.parentFile?.mkdirs()
        target.outputStream().use { out ->
            for (f in listOf(previous, current)) {
                if (f.exists()) f.inputStream().use { it.copyTo(out) }
            }
        }
        target
    }).get()

    /** Deletes both log files and everything in [extraDirs]. Blocks until done. */
    fun clear(vararg extraDirs: File) {
        executor.submit {
            previous.delete()
            current.delete()
            for (d in extraDirs) d.listFiles()?.forEach { it.delete() }
        }.get()
    }

    private fun appendNow(line: String) {
        try {
            dir.mkdirs()
            val bytes = (line + "\n").toByteArray(Charsets.UTF_8)
            val f = current
            if (f.exists() && f.length() + bytes.size > maxBytes) {
                previous.delete()
                f.renameTo(previous)
            }
            current.appendBytes(bytes)
        } catch (_: Exception) {
            // Logging must never take the connection down (disk full, etc.).
        }
    }
}
