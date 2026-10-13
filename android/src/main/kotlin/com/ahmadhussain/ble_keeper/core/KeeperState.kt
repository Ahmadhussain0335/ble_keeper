package com.ahmadhussain.ble_keeper.core

import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.security.SecureRandom

/**
 * Small persistent state: background callback handles, the log salt and the
 * last process exit already reported.
 *
 * Stored in `noBackupFilesDir` rather than SharedPreferences: callback
 * handles are only valid for the installed build, and Auto Backup of
 * SharedPreferences would restore stale handles onto a new device. A library
 * cannot change the host app's backup rules, so it avoids backed-up storage.
 */
internal class KeeperState(private val file: File) {
    private var cache: JSONObject? = null

    @get:Synchronized
    val dispatcherHandle: Long? get() = read().optLongOrNull("dispatcherHandle")

    @get:Synchronized
    val handlerHandle: Long? get() = read().optLongOrNull("handlerHandle")

    @Synchronized
    fun setHandles(dispatcher: Long, handler: Long) {
        write(read().put("dispatcherHandle", dispatcher).put("handlerHandle", handler))
    }

    @get:Synchronized
    @set:Synchronized
    var lastReportedExitMs: Long
        get() = read().optLong("lastReportedExitMs", 0L)
        set(value) {
            write(read().put("lastReportedExitMs", value))
        }

    /** Per-install random salt for log pseudonyms. Created on first use. */
    @Synchronized
    fun salt(): ByteArray {
        val existing = read().optString("salt", "")
        if (existing.length == 32) return hexToBytes(existing)
        val bytes = ByteArray(16).also { SecureRandom().nextBytes(it) }
        write(read().put("salt", bytes.joinToString("") { "%02x".format(it) }))
        return bytes
    }

    /** Forgets the salt so pseudonyms in new log lines cannot be linked to old ones. */
    @Synchronized
    fun rotateSalt() {
        write(read().apply { remove("salt") })
    }

    private fun read(): JSONObject {
        cache?.let { return it }
        val loaded = try {
            if (file.exists()) JSONObject(file.readText()) else JSONObject()
        } catch (e: JSONException) {
            JSONObject()
        } catch (e: IOException) {
            JSONObject()
        }
        cache = loaded
        return loaded
    }

    private fun write(json: JSONObject) {
        cache = json
        try {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, "${file.name}.tmp")
            tmp.writeText(json.toString())
            if (!tmp.renameTo(file)) {
                file.delete()
                tmp.renameTo(file)
            }
        } catch (_: IOException) {
            // Keep the in-memory value; persisting is retried on the next write.
        }
    }

    private companion object {
        fun JSONObject.optLongOrNull(key: String): Long? = if (has(key) && !isNull(key)) getLong(key) else null

        fun hexToBytes(hex: String) = ByteArray(hex.length / 2) { i ->
            hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }
}
