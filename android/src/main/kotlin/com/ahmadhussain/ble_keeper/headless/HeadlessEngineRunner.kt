package com.ahmadhussain.ble_keeper.headless

import com.ahmadhussain.ble_keeper.PBlockedReason
import com.ahmadhussain.ble_keeper.core.Events
import com.ahmadhussain.ble_keeper.core.KeeperRuntime
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.view.FlutterCallbackInformation

/**
 * Starts a Flutter engine without UI that runs the Dart background dispatcher
 * (`bleKeeperBackgroundMain`), which then calls the user's handler.
 *
 * Started when events are waiting, no Dart receiver is attached, and no UI
 * engine exists. Destroyed shortly after a UI receiver attaches, and when the
 * service stops. Main thread only.
 */
internal class HeadlessEngineRunner(private val runtime: KeeperRuntime) {
    private var engine: FlutterEngine? = null
    private var starting = false

    /** Set after a failed start; cleared when handles are registered again. */
    private var failed = false

    private val stopRunnable = Runnable { stop() }
    private val attachTimeout = Runnable {
        if (engine != null && !runtime.hub.hasSink) {
            fail("background handler did not attach within ${ATTACH_TIMEOUT_MS / 1000} s")
        }
    }

    val isRunning: Boolean get() = engine != null

    fun start() {
        if (engine != null || starting || failed) return
        val handle = runtime.state.dispatcherHandle ?: return
        val context = runtime.appContext
        starting = true
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context)
        loader.ensureInitializationCompleteAsync(context, null, runtime.mainHandler) {
            starting = false
            // Callback handles are only valid for the build that created them;
            // after an app update the app must call registerBackgroundHandler
            // again before the lookup succeeds.
            val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
            if (info == null) {
                fail("background dispatcher not found; call registerBackgroundHandler on every app start")
                return@ensureInitializationCompleteAsync
            }
            val e = FlutterEngine(context)
            e.dartExecutor.executeDartCallback(
                DartExecutor.DartCallback(context.assets, loader.findAppBundlePath(), info),
            )
            engine = e
            runtime.note(null, "headless engine started")
            runtime.mainHandler.postDelayed(attachTimeout, ATTACH_TIMEOUT_MS)
        }
    }

    /** Lets the background isolate finish its current batch before stopping. */
    fun stopSoon() {
        if (engine == null) return
        runtime.mainHandler.removeCallbacks(stopRunnable)
        runtime.mainHandler.postDelayed(stopRunnable, STOP_DELAY_MS)
    }

    fun stop() {
        runtime.mainHandler.removeCallbacks(stopRunnable)
        runtime.mainHandler.removeCallbacks(attachTimeout)
        engine?.destroy()
        if (engine != null) runtime.note(null, "headless engine stopped")
        engine = null
    }

    fun reset() {
        failed = false
    }

    private fun fail(detail: String) {
        failed = true
        stop()
        runtime.publish(Events.blocked(PBlockedReason.MISCONFIGURED, null, detail))
    }

    private companion object {
        const val ATTACH_TIMEOUT_MS = 20_000L
        const val STOP_DELAY_MS = 5_000L
    }
}
