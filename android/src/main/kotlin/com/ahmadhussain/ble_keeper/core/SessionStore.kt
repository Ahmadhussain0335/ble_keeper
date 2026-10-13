package com.ahmadhussain.ble_keeper.core

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.IOException

/**
 * Persists keepConnected requests so a restarted process (sticky restart,
 * boot, app update) knows what to reconnect.
 *
 * Writes go to a temporary file that is then renamed over the old one, so a
 * process kill mid-write cannot leave a half-written file behind.
 */
internal class SessionStore(private val file: File) {
    /** Last loaded or saved value; avoids reading the file on every call. */
    private var cache: List<Session>? = null

    @Synchronized
    fun load(): List<Session> {
        cache?.let { return it }
        val loaded = if (!file.exists()) {
            emptyList()
        } else {
            try {
                decode(file.readText())
            } catch (e: JSONException) {
                quarantine()
                emptyList()
            } catch (e: IOException) {
                return emptyList()
            }
        }
        cache = loaded
        return loaded
    }

    @Synchronized
    fun upsert(session: Session): List<Session> {
        val sessions = load().filterNot { it.deviceId == session.deviceId } + session
        save(sessions)
        return sessions
    }

    @Synchronized
    fun remove(deviceId: String): List<Session> {
        val sessions = load().filterNot { it.deviceId == deviceId }
        save(sessions)
        return sessions
    }

    @Synchronized
    fun save(sessions: List<Session>) {
        cache = sessions
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(encode(sessions))
        if (!tmp.renameTo(file)) {
            file.delete()
            tmp.renameTo(file)
        }
    }

    /** Keeps a corrupt file for diagnosis instead of overwriting it silently. */
    private fun quarantine() {
        file.renameTo(File(file.parentFile, "${file.name}.corrupt"))
    }

    companion object {
        const val SCHEMA_VERSION = 1

        fun encode(sessions: List<Session>): String {
            val array = JSONArray()
            for (s in sessions) {
                val subscribe = JSONArray()
                for (c in s.subscribe) {
                    subscribe.put(JSONObject().put("service", c.service).put("characteristic", c.characteristic))
                }
                array.put(
                    JSONObject()
                        .put("deviceId", s.deviceId)
                        .put("subscribe", subscribe)
                        .putOpt("notificationTitle", s.notificationTitle)
                        .putOpt("notificationText", s.notificationText)
                        .putOpt("notificationIcon", s.notificationIcon)
                        .put("restartOnBoot", s.restartOnBoot),
                )
            }
            return JSONObject().put("schemaVersion", SCHEMA_VERSION).put("sessions", array).toString()
        }

        fun decode(text: String): List<Session> {
            val root = JSONObject(text)
            val version = root.optInt("schemaVersion", 0)
            if (version > SCHEMA_VERSION) throw JSONException("unsupported schema $version")
            val array = root.getJSONArray("sessions")
            return (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                val subs = o.getJSONArray("subscribe")
                Session(
                    deviceId = o.getString("deviceId"),
                    subscribe = (0 until subs.length()).map { j ->
                        val c = subs.getJSONObject(j)
                        CharRef(c.getString("service"), c.getString("characteristic"))
                    },
                    notificationTitle = o.optStringOrNull("notificationTitle"),
                    notificationText = o.optStringOrNull("notificationText"),
                    notificationIcon = o.optStringOrNull("notificationIcon"),
                    restartOnBoot = o.optBoolean("restartOnBoot", true),
                )
            }
        }

        private fun JSONObject.optStringOrNull(key: String): String? =
            if (has(key) && !isNull(key)) getString(key) else null
    }
}
