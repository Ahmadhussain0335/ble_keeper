import CoreBluetooth
import Flutter
import UIKit

/// Process-wide state shared by the plugin instances (one per Flutter
/// engine) and the Core Bluetooth holder. Independent of any Flutter engine.
///
/// Main thread unless noted: `publish` and `note` may be called from any
/// thread.
final class KeeperRuntime {
  static let shared = KeeperRuntime()

  let sessions: SessionStore
  let state: KeeperState
  let config: ConfigurationChecker
  let hub: EventHub
  let headless = HeadlessEngineRunner()

  private var formatter: LogFormatter
  private let log: RotatingEventLog
  private let exportDir: URL
  private(set) var central: CentralManagerHolder?
  private(set) var bootstrapped = false
  private(set) var launchedForBluetooth = false
  private var uiEngines = 0
  private var launchClassified = false
  private var configReported = false
  private var bootstrapWarned = false

  private init() {
    let dir = StorageLocation.directory()
    sessions = SessionStore(url: dir.appendingPathComponent(KeeperConstants.sessionsFile))
    state = KeeperState(url: dir.appendingPathComponent(KeeperConstants.stateFile))
    config = ConfigurationChecker()
    formatter = KeeperRuntime.makeFormatter(state)
    log = RotatingEventLog(
      dir: dir.appendingPathComponent(KeeperConstants.logDirectory, isDirectory: true),
      fileName: KeeperConstants.logFile, maxBytes: KeeperConstants.logMaxBytes,
      queue: DispatchQueue(label: KeeperConstants.logQueueLabel))
    exportDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      KeeperConstants.exportDirectory, isDirectory: true)
    hub = EventHub()
    hub.onPublished = { [weak self] e in
      guard let self = self else { return }
      self.log.append(self.formatter.format(e))
    }
    hub.onDropped = { [weak self] n in self?.note(nil, "dropped \(n) undelivered events (buffer full)") }
    hub.onNoSink = { [weak self] in self?.onNoSink() }
    hub.onDeliveryFailed = { [weak self] in
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.hub.retry() }
    }
    // Foreground state for the reconnect policy (PeripheralSession).
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.central?.setForeground(true) }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.central?.setForeground(false) }
    // Only called when the app is running (foreground or background, not
    // suspended) and the user swipes it away; never for suspended apps.
    NotificationCenter.default.addObserver(
      forName: UIApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self = self, !self.sessions.load().isEmpty else { return }
      self.state.setWillTerminateSeen(true)
    }
  }

  func publish(_ event: PEvent) {
    if Thread.isMainThread {
      hub.publish(event)
    } else {
      DispatchQueue.main.async { self.hub.publish(event) }
    }
  }

  func note(_ deviceId: String?, _ text: String) {
    let prefix = deviceId.map { "device=\(formatter.deviceLabel($0)) " } ?? ""
    log.append(formatter.note(Events.now(), level: "note", prefix + text))
  }

  // MARK: Launch

  func bootstrap(
    launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
    registrant: @escaping (FlutterPluginRegistry) -> Void
  ) {
    bootstrapped = true
    headless.registrant = registrant
    launchedForBluetooth = launchOptions?[.bluetoothCentrals] != nil
    if launchedForBluetooth { note(nil, "launched by Core Bluetooth") }
    if !sessions.load().isEmpty || launchedForBluetooth {
      // Must happen during didFinishLaunching for state restoration.
      startCentralIfPossible()
    } else {
      classifyLaunch(restored: false)
    }
  }

  /// Decides once per launch whether to report RestoredAfterKill or a
  /// probable force-quit. Called after the first Core Bluetooth state update
  /// (restoration, if any, has been delivered by then).
  func classifyLaunch(restored: Bool) {
    guard !launchClassified else { return }
    launchClassified = true
    let ids = sessions.load().map { $0.deviceId }
    let outcome = ForceQuitDetector.classify(
      hadSessions: !ids.isEmpty, restored: restored, willTerminateSeen: state.willTerminateSeen,
      previousAppVersion: state.appVersion, currentAppVersion: config.appVersion)
    state.setWillTerminateSeen(false)
    state.setAppVersion(config.appVersion)
    switch outcome {
    case .restored:
      publish(Events.restored(ids))
    case .forceQuit:
      publish(
        Events.blocked(
          .userForceQuit,
          detail: "the app was closed from the app switcher while running; iOS does not relaunch it"))
    case .probableForceQuit:
      publish(
        Events.blocked(
          .userForceQuit,
          detail: "best effort: not relaunched by Core Bluetooth since the last launch; most likely closed from the app switcher"))
    case .appUpdated:
      note(nil, "app updated since the last launch")
    case .none:
      break
    }
  }

  // MARK: Engines

  func pluginRegistered(isHeadless: Bool) {
    if !isHeadless { uiEngines += 1 }
    if !sessions.load().isEmpty { startCentralIfPossible() }
  }

  func pluginDetached(isHeadless: Bool) {
    if !isHeadless { uiEngines = max(0, uiEngines - 1) }
  }

  func attachSink(_ sink: EventSink) {
    if !bootstrapped, !bootstrapWarned {
      bootstrapWarned = true
      publish(
        Events.blocked(
          .misconfigured,
          detail: "call BleKeeperPlugin.bootstrap(launchOptions:pluginRegistrant:) in AppDelegate; without it state restoration does not work"))
    }
    hub.attach(sink)
    if sink.isBackground {
      headless.attached()
    } else {
      headless.stopSoon()
    }
  }

  /// The headless engine is only for background relaunches. On a normal cold
  /// launch events can be published before the UI engine registers; those
  /// wait for the UI instead of running the handler in the foreground.
  private func onNoSink() {
    guard uiEngines == 0, state.dispatcherHandle != nil,
      UIApplication.shared.applicationState == .background
    else { return }
    headless.start(self)
  }

  // MARK: Commands

  func keep(_ session: Session) {
    sessions.upsert(session)
    if #available(iOS 13.1, *) {
      switch CBManager.authorization {
      case .denied, .restricted:
        publish(Events.blocked(.permissionMissing, deviceId: session.deviceId, detail: "bluetooth"))
        return
      default:
        break
      }
    }
    if startCentralIfPossible() { central?.reconcile() }
  }

  func stop(_ deviceId: String) {
    sessions.remove(deviceId)
    central?.reconcile()
  }

  func exportLog() throws -> URL {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd-HHmmss"
    return try log.export(to: exportDir.appendingPathComponent("ble_keeper_events_\(f.string(from: Date())).log"))
  }

  /// Erases the log, exported copies and the corrupt-session backup, and
  /// rotates the pseudonym salt so later lines cannot be linked to logs that
  /// were already shared (GDPR Art. 17). Called on the main actor.
  func clearLog() {
    log.clear([exportDir])
    try? FileManager.default.removeItem(
      at: StorageLocation.directory().appendingPathComponent(KeeperConstants.sessionsFile + ".corrupt"))
    state.rotateSalt()
    formatter = KeeperRuntime.makeFormatter(state)
  }

  private static func makeFormatter(_ state: KeeperState) -> LogFormatter {
    #if DEBUG
      return LogFormatter(pseudonymizer: nil)
    #else
      return LogFormatter(pseudonymizer: Pseudonymizer(salt: state.salt()))
    #endif
  }

  /// Creates the CBCentralManager unless the Info.plist would make that
  /// crash. Reports configuration problems once per launch.
  @discardableResult
  private func startCentralIfPossible() -> Bool {
    if central != nil { return true }
    if !configReported {
      configReported = true
      for problem in config.problems { publish(Events.blocked(.misconfigured, detail: problem)) }
    }
    guard config.hasUsageDescription else { return false }
    let holder = CentralManagerHolder(runtime: self, restore: config.hasBackgroundMode)
    holder.setForeground(UIApplication.shared.applicationState == .active)
    central = holder
    return true
  }
}
