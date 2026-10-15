import CoreBluetooth
import Foundation

/// Owns the app's single CBCentralManager.
///
/// State restoration (Core Bluetooth Programming Guide, "Performing
/// Long-Term Actions in the Background"; Apple TN3115): when iOS terminates
/// the app while it has pending or active connections, it keeps those
/// connections and relaunches the app in the background when something
/// happens on them. The relaunched app must create a CBCentralManager with
/// the same restore identifier during
/// `application(_:didFinishLaunchingWithOptions:)`; iOS then calls
/// `centralManager(_:willRestoreState:)` before `centralManagerDidUpdateState`.
///
/// All Core Bluetooth work runs on `queue`.
final class CentralManagerHolder: NSObject, CBCentralManagerDelegate {
  let queue = DispatchQueue(label: KeeperConstants.bleQueueLabel)
  private let runtime: KeeperRuntime
  private var manager: CBCentralManager?
  private var sessions: [String: PeripheralSession] = [:]
  private var restoredPeripherals: [UUID: CBPeripheral] = [:]
  private var restoredThisLaunch = false
  private var firstStateHandled = false
  private var reportedUnknown = Set<String>()
  /// Mirrors UIApplication state; written via `setForeground`, read on `queue`.
  private var appInForeground = false

  init(runtime: KeeperRuntime, restore: Bool) {
    self.runtime = runtime
    super.init()
    var options: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: false]
    if restore {
      options[CBCentralManagerOptionRestoreIdentifierKey] = KeeperConstants.restoreIdentifier
    }
    manager = CBCentralManager(delegate: self, queue: queue, options: options)
  }

  /// Called on the main thread when the app enters or leaves the foreground.
  func setForeground(_ foreground: Bool) {
    queue.async {
      self.appInForeground = foreground
      if !foreground { self.sessions.values.forEach { $0.appDidEnterBackground() } }
    }
  }

  /// Aligns connections with the persisted sessions.
  func reconcile() {
    queue.async { self.reconcileLocked() }
  }

  func read(_ deviceId: String, _ ref: CharRef) async throws -> Data {
    try await withCheckedThrowingContinuation { cont in
      queue.async {
        guard let s = self.sessions[deviceId] else {
          cont.resume(throwing: self.missing(deviceId))
          return
        }
        s.read(ref) { cont.resume(with: $0.mapError { $0 as Error }) }
      }
    }
  }

  func write(_ deviceId: String, _ ref: CharRef, _ value: Data, withResponse: Bool) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      queue.async {
        guard let s = self.sessions[deviceId] else {
          cont.resume(throwing: self.missing(deviceId))
          return
        }
        s.write(ref, value, withResponse: withResponse) { cont.resume(with: $0.mapError { $0 as Error }) }
      }
    }
  }

  // MARK: CBCentralManagerDelegate

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    restoredThisLaunch = true
    let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    let stored = Dictionary(runtime.sessions.load().map { ($0.deviceId, $0) }, uniquingKeysWith: { _, b in b })
    for p in peripherals {
      restoredPeripherals[p.identifier] = p
      // The notification that caused the relaunch may be delivered right
      // after this call, so the session and its delegate must exist now.
      // Connect/discover still wait for .poweredOn (reconcileLocked).
      if let s = stored[p.identifier.uuidString], sessions[s.deviceId] == nil {
        let session = makeSession(s, p, central)
        p.delegate = session
        sessions[s.deviceId] = session
      }
    }
    runtime.note(nil, "state restored with \(peripherals.count) peripheral(s)")
    DispatchQueue.main.async { [runtime] in runtime.coreBluetoothRestored() }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if !firstStateHandled {
      firstStateHandled = true
      let restored = restoredThisLaunch || runtime.launchedForBluetooth
      DispatchQueue.main.async { self.runtime.classifyLaunch(restored: restored) }
    }
    switch central.state {
    case .poweredOn:
      runtime.note(nil, "Bluetooth on")
      reconcileLocked()
    case .poweredOff:
      sessions.values.forEach { $0.bluetoothOff() }
      runtime.publish(Events.blocked(.bluetoothOff))
    case .resetting:
      // The system Bluetooth service restarted; peripheral objects are
      // invalid. Drop them and rebuild on the next poweredOn.
      runtime.note(nil, "Bluetooth resetting")
      sessions.values.forEach { $0.bluetoothOff() }
      sessions.removeAll()
      restoredPeripherals.removeAll()
    case .unauthorized:
      runtime.publish(Events.blocked(.permissionMissing, detail: "bluetooth"))
    case .unsupported:
      runtime.publish(Events.blocked(.unknown, detail: "Bluetooth LE is not supported on this device"))
    default:
      break
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    sessions[peripheral.identifier.uuidString]?.didConnect()
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    sessions[peripheral.identifier.uuidString]?.didFailToConnect(error)
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    sessions[peripheral.identifier.uuidString]?.didDisconnect(error, isReconnecting: false)
  }

  // When implemented, iOS 17+ calls this instead of the variant above; older
  // systems never call it. (It cannot be marked @available(iOS 17) because
  // the deployment target is lower than the protocol requirement's.)
  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
    timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?
  ) {
    sessions[peripheral.identifier.uuidString]?.didDisconnect(error, isReconnecting: isReconnecting)
  }

  // MARK: Private

  private func reconcileLocked() {
    let wanted = runtime.sessions.load()
    let ids = Set(wanted.map { $0.deviceId })
    let poweredOn = manager?.state == .poweredOn
    for (id, s) in sessions where !ids.contains(id) {
      // Core Bluetooth commands are only valid while powered on.
      s.stop(cancelConnection: poweredOn)
      sessions[id] = nil
    }
    guard let manager = manager, poweredOn else { return }
    // A restored peripheral without a session (stopped just before the app
    // was terminated) would otherwise stay connected and keep relaunching
    // the app.
    for (uuid, p) in restoredPeripherals where !ids.contains(uuid.uuidString) {
      manager.cancelPeripheralConnection(p)
      restoredPeripherals[uuid] = nil
    }
    for s in wanted {
      if let existing = sessions[s.deviceId] {
        existing.update(s)
        existing.ensureConnecting()
        continue
      }
      guard let uuid = UUID(uuidString: s.deviceId) else { continue }
      // retrievePeripherals only knows peripherals this app has seen before
      // (scanned or connected); identifiers are per app install.
      guard let peripheral = restoredPeripherals[uuid] ?? manager.retrievePeripherals(withIdentifiers: [uuid]).first
      else {
        if reportedUnknown.insert(s.deviceId).inserted {
          runtime.publish(
            Events.blocked(
              .misconfigured, deviceId: s.deviceId,
              detail: "iOS does not know this peripheral; scan for it in this app first (identifiers are per install)"))
        }
        continue
      }
      let session = makeSession(s, peripheral, manager)
      sessions[s.deviceId] = session
      session.start()
    }
  }

  private func makeSession(_ s: Session, _ peripheral: CBPeripheral, _ central: CBCentralManager)
    -> PeripheralSession
  {
    PeripheralSession(
      session: s, peripheral: peripheral, central: central, queue: queue,
      emit: { [runtime] in runtime.publish($0) },
      note: { [runtime] text in runtime.note(s.deviceId, text) },
      isForeground: { [weak self] in self?.appInForeground ?? false })
  }

  private func missing(_ deviceId: String) -> KeeperError {
    if runtime.sessions.load().contains(where: { $0.deviceId == deviceId }) {
      return KeeperError(code: "not_connected", message: "device is not connected")
    }
    return KeeperError(code: "unknown_device", message: "keepConnected was not called for this device")
  }
}
