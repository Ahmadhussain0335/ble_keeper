package com.ahmadhussain.ble_keeper

import android.bluetooth.BluetoothAdapter
import com.ahmadhussain.ble_keeper.core.CharRef
import com.ahmadhussain.ble_keeper.core.EventHub
import com.ahmadhussain.ble_keeper.core.KeeperException
import com.ahmadhussain.ble_keeper.core.KeeperRuntime
import com.ahmadhussain.ble_keeper.core.Session
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.Locale
import java.util.UUID

/**
 * Flutter entry point. One instance per Flutter engine (the UI engine and,
 * when used, the headless background engine). Connections are owned by
 * KeeperService through the process-wide KeeperRuntime, not by this class.
 *
 * Pigeon runs the suspend host methods on Dispatchers.Main.
 */
class BleKeeperPlugin : FlutterPlugin, ActivityAware, BleKeeperHostApi {
    private var runtime: KeeperRuntime? = null
    private var messenger: BinaryMessenger? = null
    private var eventApi: BleKeeperEventApi? = null
    private var sink: PluginSink? = null
    private var scope: CoroutineScope? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        runtime = KeeperRuntime.get(binding.applicationContext)
        messenger = binding.binaryMessenger
        eventApi = BleKeeperEventApi(binding.binaryMessenger)
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        BleKeeperHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BleKeeperHostApi.setUp(binding.binaryMessenger, null)
        detach()
        runtime?.setActivityAttached(this, false)
        scope?.cancel()
        scope = null
        eventApi = null
        messenger = null
        runtime = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        runtime?.setActivityAttached(this, true)
    }

    override fun onDetachedFromActivityForConfigChanges() = Unit

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = Unit

    override fun onDetachedFromActivity() {
        runtime?.setActivityAttached(this, false)
    }

    override suspend fun keepConnected(request: PKeepRequest) = guard {
        val deviceId = normalizeDeviceId(request.deviceId)
        if (request.subscribe.isEmpty()) throw KeeperException("invalid_argument", "subscribe must not be empty")
        val subscribe = request.subscribe.map { CharRef(uuid(it.serviceUuid), uuid(it.characteristicUuid)) }
        val android = request.android
        rt().keep(
            Session(
                deviceId = deviceId,
                subscribe = subscribe.distinct(),
                notificationTitle = android?.notificationTitle,
                notificationText = android?.notificationText,
                notificationIcon = android?.notificationIcon,
                restartOnBoot = android?.restartOnBoot ?: true,
            ),
        )
    }

    override suspend fun stop(deviceId: String) = guard {
        rt().stop(normalizeDeviceId(deviceId))
    }

    override suspend fun write(
        deviceId: String,
        characteristic: PCharacteristicRef,
        value: ByteArray,
        withResponse: Boolean,
    ) = guard {
        rt().manager(normalizeDeviceId(deviceId)).write(charRef(characteristic), value, withResponse)
    }

    override suspend fun read(deviceId: String, characteristic: PCharacteristicRef): ByteArray = guard {
        rt().manager(normalizeDeviceId(deviceId)).read(charRef(characteristic))
    }

    override fun registerBackgroundHandler(dispatcherHandle: Long, handlerHandle: Long) {
        val rt = rt()
        rt.state.setHandles(dispatcherHandle, handlerHandle)
        rt.headless.reset()
    }

    override fun backgroundHandlerHandle(): Long? = rt().state.handlerHandle

    override suspend fun exportLog(): String = guard {
        val rt = rt()
        rt.flushLogSummaries() // main thread (Pigeon runs host calls on Dispatchers.Main)
        withContext(Dispatchers.IO) { rt.exportLog().absolutePath }
    }

    override suspend fun clearLog() = guard {
        val rt = rt()
        withContext(Dispatchers.IO) { rt.clearLog() }
    }

    override fun attach(isBackground: Boolean) {
        val rt = rt()
        sink?.let { rt.hub.detach(it) }
        val s = PluginSink(isBackground)
        sink = s
        rt.attachSink(s)
    }

    override fun detach() {
        val s = sink ?: return
        sink = null
        runtime?.hub?.detach(s)
    }

    override fun activeDeviceIds(): List<String> = rt().sessions.load().map { it.deviceId }

    private inner class PluginSink(override val isBackground: Boolean) : EventHub.Sink {
        override fun deliver(events: List<PEvent>, done: (Boolean) -> Unit) {
            val api = eventApi
            val s = scope
            if (api == null || s == null) {
                done(false)
                return
            }
            s.launch {
                val ok = try {
                    withTimeout(ACK_TIMEOUT_MS) { api.onEvents(events) }
                    true
                } catch (e: Exception) {
                    runtime?.note(null, "event delivery failed: ${e.javaClass.simpleName}")
                    false
                }
                done(ok)
            }
        }
    }

    private fun rt(): KeeperRuntime =
        runtime ?: throw BleKeeperFlutterError("not_attached", "plugin is not attached to an engine")

    private companion object {
        /** A slow background handler must not block delivery forever. */
        const val ACK_TIMEOUT_MS = 60_000L

        inline fun <T> guard(block: () -> T): T =
            try {
                block()
            } catch (e: KeeperException) {
                throw BleKeeperFlutterError(e.code, e.message)
            }

        /** BluetoothAdapter.getRemoteDevice requires upper-case hex with colons. */
        fun normalizeDeviceId(id: String): String {
            val upper = id.trim().uppercase(Locale.ROOT)
            if (!BluetoothAdapter.checkBluetoothAddress(upper)) {
                throw KeeperException(
                    "invalid_argument",
                    "on Android the device ID is a MAC address like AA:BB:CC:DD:EE:FF",
                )
            }
            return upper
        }

        fun uuid(value: String): String = try {
            UUID.fromString(value).toString()
        } catch (e: IllegalArgumentException) {
            throw KeeperException("invalid_argument", "invalid UUID")
        }

        fun charRef(c: PCharacteristicRef) = CharRef(uuid(c.serviceUuid), uuid(c.characteristicUuid))
    }
}
