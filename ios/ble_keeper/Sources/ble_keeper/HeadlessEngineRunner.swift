import Flutter
import UIKit

/// Runs the Dart background dispatcher in a Flutter engine without UI.
///
/// Used when Core Bluetooth relaunched the app in the background: with the
/// UIScene app template no scene connects in that case, so the UI engine
/// (and the app's Dart `main`) never starts. Main thread only.
final class HeadlessEngineRunner {
  /// Registers plugins on the headless engine. Supplied by the app through
  /// `BleKeeperPlugin.bootstrap` (usually GeneratedPluginRegistrant).
  var registrant: ((FlutterPluginRegistry) -> Void)?

  private var engine: FlutterEngine?
  private var failed = false
  private var attachTimer: DispatchWorkItem?
  private var stopTimer: DispatchWorkItem?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  var isRunning: Bool { engine != nil }

  /// True while plugins are registered on the headless engine, so the plugin
  /// instance created there knows it is not a UI engine.
  private(set) var registering = false

  func start(_ runtime: KeeperRuntime) {
    guard engine == nil, !failed, let handle = runtime.state.dispatcherHandle else { return }
    guard let registrant = registrant else {
      fail(runtime, "background handler needs BleKeeperPlugin.bootstrap(launchOptions:pluginRegistrant:) in AppDelegate")
      return
    }
    // Callback handles are only valid for the build that created them.
    guard let info = FlutterCallbackCache.lookupCallbackInformation(handle) else {
      fail(runtime, "background dispatcher not found; call registerBackgroundHandler on every app start")
      return
    }
    // A Bluetooth relaunch gives the app about 10 s; ask for the extra time
    // the engine needs to boot and deliver the first batch.
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: KeeperConstants.headlessEngineName) {
      [weak self] in self?.endBackgroundTask()
    }
    let e = FlutterEngine(name: KeeperConstants.headlessEngineName, project: nil, allowHeadlessExecution: true)
    guard e.run(withEntrypoint: info.callbackName, libraryURI: info.callbackLibraryPath) else {
      endBackgroundTask()
      fail(runtime, "background engine failed to start")
      return
    }
    registering = true
    registrant(e)
    registering = false
    engine = e
    runtime.note(nil, "headless engine started")
    let timer = DispatchWorkItem { [weak self] in
      guard let self = self, self.engine != nil, !runtime.hub.hasSink else { return }
      self.fail(runtime, "background handler did not attach within 20 s")
    }
    attachTimer = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timer)
  }

  /// The background isolate is ready; the boot background task can end.
  func attached() {
    attachTimer?.cancel()
    endBackgroundTask()
  }

  /// Lets the background isolate finish its current batch before stopping.
  func stopSoon() {
    guard engine != nil else { return }
    stopTimer?.cancel()
    let timer = DispatchWorkItem { [weak self] in self?.stop() }
    stopTimer = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timer)
  }

  func stop() {
    attachTimer?.cancel()
    stopTimer?.cancel()
    engine?.destroyContext()
    engine = nil
    endBackgroundTask()
  }

  func reset() {
    failed = false
  }

  private func fail(_ runtime: KeeperRuntime, _ detail: String) {
    failed = true
    stop()
    runtime.publish(Events.blocked(.misconfigured, detail: detail))
  }

  private func endBackgroundTask() {
    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }
}
