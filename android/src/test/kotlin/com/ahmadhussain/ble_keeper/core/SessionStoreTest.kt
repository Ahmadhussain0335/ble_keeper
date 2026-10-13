package com.ahmadhussain.ble_keeper.core

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class SessionStoreTest {
    private val dir: File = Files.createTempDirectory("sessions").toFile()
    private val file = File(dir, "sessions.json")
    private val store = SessionStore(file)

    private val session = Session(
        deviceId = "AA:BB:CC:DD:EE:FF",
        subscribe = listOf(CharRef("12345678-1234-1234-1234-1234567890ab", "12345678-1234-1234-1234-1234567890ac")),
        notificationTitle = "Title",
        notificationText = null,
        notificationIcon = "ic_stat",
        restartOnBoot = false,
    )

    @AfterTest
    fun cleanUp() {
        dir.deleteRecursively()
    }

    @Test
    fun load_withoutFile_isEmpty() {
        assertEquals(emptyList(), store.load())
    }

    @Test
    fun upsert_roundTripsAllFields() {
        store.upsert(session)
        assertEquals(listOf(session), SessionStore(file).load())
    }

    @Test
    fun upsert_replacesSameDevice() {
        store.upsert(session)
        store.upsert(session.copy(notificationTitle = "New"))
        assertEquals(listOf("New"), store.load().map { it.notificationTitle })
    }

    @Test
    fun remove_keepsOtherDevices() {
        store.upsert(session)
        store.upsert(session.copy(deviceId = "11:22:33:44:55:66"))
        store.remove("AA:BB:CC:DD:EE:FF")
        assertEquals(listOf("11:22:33:44:55:66"), store.load().map { it.deviceId })
    }

    @Test
    fun load_isCached_afterFirstRead() {
        store.upsert(session)
        file.writeText("{not json") // changed behind the store's back
        assertEquals(listOf(session), store.load())
    }

    @Test
    fun corruptFile_isQuarantined_andTreatedAsEmpty() {
        file.writeText("{not json")
        assertEquals(emptyList(), store.load())
        assertTrue(File(dir, "sessions.json.corrupt").exists())
    }

    @Test
    fun newerSchema_isNotMisread() {
        file.writeText("""{"schemaVersion":99,"sessions":[]}""")
        assertEquals(emptyList(), store.load())
    }

    @Test
    fun missingOptionalFields_useDefaults() {
        file.writeText(
            """{"schemaVersion":1,"sessions":[{"deviceId":"AA:BB:CC:DD:EE:FF","subscribe":[]}]}""",
        )
        val loaded = store.load().single()
        assertEquals(true, loaded.restartOnBoot)
        assertEquals(null, loaded.notificationTitle)
    }
}
