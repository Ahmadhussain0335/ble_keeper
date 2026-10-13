import CoreBluetooth
import Foundation

/// Converts a CBUUID to the lowercase 128-bit form used on the wire.
/// `CBUUID.uuidString` returns the short form for 16- and 32-bit UUIDs.
func fullUuid(_ uuid: CBUUID) -> String {
  let s = uuid.uuidString.lowercased()
  switch s.count {
  case 4: return "0000\(s)-0000-1000-8000-00805f9b34fb"
  case 8: return "\(s)-0000-1000-8000-00805f9b34fb"
  default: return s
  }
}

/// Maps a didDisconnect / didFailToConnect error to a disconnect reason.
/// A nil error on didDisconnect means the app cancelled the connection.
enum DisconnectMapping {
  static func reason(_ error: Error?) -> (PDisconnectReason, Int?) {
    guard let error = error else { return (.localTerminated, nil) }
    let ns = error as NSError
    guard ns.domain == CBErrorDomain else { return (.unknown, ns.code) }
    switch CBError.Code(rawValue: ns.code) {
    case .connectionTimeout: return (.linkLoss, ns.code)
    case .peripheralDisconnected: return (.peerTerminated, ns.code)
    case .connectionFailed: return (.connectFailed, ns.code)
    default: return (.unknown, ns.code)
    }
  }
}

/// A pending read or write that completes once, by callback or timeout.
final class Waiter<T> {
  private var completion: ((Result<T, KeeperError>) -> Void)?

  init(_ completion: @escaping (Result<T, KeeperError>) -> Void) {
    self.completion = completion
  }

  var isDone: Bool { completion == nil }

  func finish(_ result: Result<T, KeeperError>) {
    let c = completion
    completion = nil
    c?(result)
  }
}

/// Owns the connection to one peripheral and keeps it alive.
///
/// Threading: every method runs on the BLE queue that the CBCentralManager
/// was created with; Core Bluetooth delivers delegate callbacks there too.
///
/// Reconnect: `CBCentralManager.connect` does not time out (Apple
/// documentation for connect(_:options:)). A pending connect survives the
/// app being suspended, and with state restoration the system relaunches the
/// app when it completes. So after a disconnect the session simply issues a
/// new pending connect; no polling or backoff is needed.
final class PeripheralSession: NSObject, CBPeripheralDelegate {
  private enum State { case idle, connecting, discovering, subscribing, ready, waiting, off, stopped }

  private(set) var session: Session
  let peripheral: CBPeripheral
  private let central: CBCentralManager
  private let queue: DispatchQueue
  private let emit: (PEvent) -> Void
  private let note: (String) -> Void

  private var state = State.idle
  private var attempt = 0
  private var pendingServices = 0
  private var pendingNotify = Set<String>()
  private var setupToken = 0
  private var reads: [String: [Waiter<Data>]] = [:]
  private var writes: [String: [Waiter<Void>]] = [:]
  private var writeWithoutResponseQueue: [() -> Void] = []
  private var reported = Set<String>()

  var deviceId: String { session.deviceId }
  private var linkUp: Bool { state == .discovering || state == .subscribing || state == .ready }

  init(
    session: Session, peripheral: CBPeripheral, central: CBCentralManager, queue: DispatchQueue,
    emit: @escaping (PEvent) -> Void, note: @escaping (String) -> Void
  ) {
    self.session = session
    self.peripheral = peripheral
    self.central = central
    self.queue = queue
    self.emit = emit
    self.note = note
    super.init()
  }

  func start() {
    peripheral.delegate = self
    if peripheral.state == .connected {
      // Restored by the system with the link still up.
      didConnect()
    } else {
      connect()
    }
  }

  /// Reconnects after Bluetooth was off or the session was idle.
  func ensureConnecting() {
    guard state == .off || state == .idle else { return }
    attempt = 0
    start()
  }

  func update(_ newSession: Session) {
    let added = newSession.subscribe.filter { !session.subscribe.contains($0) }
    session = newSession
    if state == .ready, !added.isEmpty { subscribe(added) }
  }

  func stop() {
    guard state != .stopped else { return }
    let wasUp = linkUp
    state = .stopped
    failAll(KeeperError(code: "not_connected", message: "stopped"))
    central.cancelPeripheralConnection(peripheral)
    if wasUp { emit(Events.disconnected(deviceId, .stopped, code: nil)) }
  }

  /// Bluetooth off invalidates every connection; no didDisconnect follows.
  func bluetoothOff() {
    guard state != .stopped, state != .off else { return }
    let wasUp = linkUp
    failAll(KeeperError(code: "bluetooth_off", message: "Bluetooth is off"))
    state = .off
    if wasUp { emit(Events.disconnected(deviceId, .bluetoothOff, code: nil)) }
  }

  // MARK: Central callbacks (forwarded by CentralManagerHolder)

  func didConnect() {
    guard state != .stopped else { return }
    peripheral.delegate = self
    state = .discovering
    armSetupTimeout()
    // Discover everything so read/write work on characteristics that are
    // not subscribed (for example a command characteristic).
    peripheral.discoverServices(nil)
  }

  func didFailToConnect(_ error: Error?) {
    guard state != .stopped, state != .off else { return }
    note("connect failed: \(error?.localizedDescription ?? "unknown")")
    attempt += 1
    emit(Events.reconnecting(deviceId, attempt: attempt))
    state = .waiting
    let delay = min(60.0, pow(2.0, Double(min(attempt - 1, 6))))
    queue.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self = self, self.state == .waiting else { return }
      self.connect()
    }
  }

  func didDisconnect(_ error: Error?, isReconnecting: Bool) {
    let wasUp = linkUp
    failAll(KeeperError(code: "not_connected", message: "device disconnected"))
    guard state != .stopped, state != .off else { return }
    if wasUp {
      let (reason, code) = DisconnectMapping.reason(error)
      emit(Events.disconnected(deviceId, reason, code: code))
    }
    attempt += 1
    emit(Events.reconnecting(deviceId, attempt: attempt))
    if isReconnecting {
      // iOS 17 auto-reconnect (CBConnectPeripheralOptionEnableAutoReconnect)
      // is already reconnecting; a second connect is not needed.
      state = .connecting
    } else {
      connect()
    }
  }

  // MARK: Operations

  func read(_ ref: CharRef, completion: @escaping (Result<Data, KeeperError>) -> Void) {
    let waiter = Waiter(completion)
    guard let ch = readyCharacteristic(ref, waiter) else { return }
    guard ch.properties.contains(.read) else {
      waiter.finish(.failure(KeeperError(code: "read_unsupported", message: "\(ref.characteristic) does not support read")))
      return
    }
    let key = Self.key(ch)
    reads[key, default: []].append(waiter)
    peripheral.readValue(for: ch)
    timeout(waiter, "read")
  }

  func write(
    _ ref: CharRef, _ value: Data, withResponse: Bool,
    completion: @escaping (Result<Void, KeeperError>) -> Void
  ) {
    let waiter = Waiter(completion)
    guard let ch = readyCharacteristic(ref, waiter) else { return }
    let type: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
    let needed: CBCharacteristicProperties = withResponse ? .write : .writeWithoutResponse
    guard ch.properties.contains(needed) else {
      waiter.finish(
        .failure(
          KeeperError(
            code: "write_type_unsupported",
            message: "\(ref.characteristic) does not support write \(withResponse ? "with" : "without") response")))
      return
    }
    let max = withResponse ? KeeperConstants.maxAttributeLength : peripheral.maximumWriteValueLength(for: type)
    guard value.count <= max else {
      waiter.finish(.failure(KeeperError(code: "payload_too_large", message: "\(value.count) bytes exceeds \(max)")))
      return
    }
    if withResponse {
      writes[Self.key(ch), default: []].append(waiter)
      peripheral.writeValue(value, for: ch, type: .withResponse)
      timeout(waiter, "write")
    } else {
      // Write without response has flow control since iOS 11: wait for
      // peripheralIsReady(toSendWriteWithoutResponse:) when the buffer is full.
      let send = { [weak self] in
        guard let self = self, !waiter.isDone else { return }
        self.peripheral.writeValue(value, for: ch, type: .withoutResponse)
        waiter.finish(.success(()))
      }
      if peripheral.canSendWriteWithoutResponse {
        send()
      } else {
        writeWithoutResponseQueue.append(send)
        timeout(waiter, "write")
      }
    }
  }

  // MARK: CBPeripheralDelegate

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard state == .discovering else { return }
    if let error = error {
      failSetup("service discovery failed: \(error.localizedDescription)")
      return
    }
    let services = peripheral.services ?? []
    pendingServices = services.count
    if services.isEmpty {
      subscribe(session.subscribe)
      return
    }
    for s in services { peripheral.discoverCharacteristics(nil, for: s) }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard state == .discovering else { return }
    if let error = error { note("characteristic discovery failed for \(fullUuid(service.uuid)): \(error.localizedDescription)") }
    pendingServices -= 1
    if pendingServices <= 0 { subscribe(session.subscribe) }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?
  ) {
    let key = Self.key(characteristic)
    if let error = error {
      reportOnce(key, "enabling notifications on \(fullUuid(characteristic.uuid)) failed: \(error.localizedDescription)")
    }
    pendingNotify.remove(key)
    if state == .subscribing, pendingNotify.isEmpty { becomeReady() }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    let key = Self.key(characteristic)
    if var waiting = reads[key], !waiting.isEmpty {
      let waiter = waiting.removeFirst()
      reads[key] = waiting
      if !waiter.isDone {
        if let error = error {
          waiter.finish(.failure(KeeperError(code: "gatt_error", message: error.localizedDescription)))
        } else {
          waiter.finish(.success(characteristic.value ?? Data()))
        }
        return
      }
    }
    guard error == nil, let service = characteristic.service else { return }
    let ref = CharRef(service: fullUuid(service.uuid), characteristic: fullUuid(characteristic.uuid))
    emit(Events.data(deviceId, ref, characteristic.value ?? Data(), timestampMs: Events.now()))
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    let key = Self.key(characteristic)
    guard var waiting = writes[key], !waiting.isEmpty else { return }
    let waiter = waiting.removeFirst()
    writes[key] = waiting
    if let error = error {
      waiter.finish(.failure(KeeperError(code: "gatt_error", message: error.localizedDescription)))
    } else {
      waiter.finish(.success(()))
    }
  }

  func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
    while peripheral.canSendWriteWithoutResponse, !writeWithoutResponseQueue.isEmpty {
      writeWithoutResponseQueue.removeFirst()()
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    // The peripheral changed its GATT table; rediscover and resubscribe.
    guard state == .ready else { return }
    note("services changed, rediscovering")
    state = .discovering
    armSetupTimeout()
    peripheral.discoverServices(nil)
  }

  // MARK: Private

  private func connect() {
    guard state != .stopped else { return }
    state = .connecting
    var options: [String: Any] = [:]
    if session.notifyOnDisconnection { options[CBConnectPeripheralOptionNotifyOnDisconnectionKey] = true }
    if #available(iOS 17.0, *), session.enableAutoReconnect {
      options[CBConnectPeripheralOptionEnableAutoReconnect] = true
    }
    central.connect(peripheral, options: options)
  }

  private func subscribe(_ chars: [CharRef]) {
    state = .subscribing
    for ref in chars {
      guard let ch = find(ref) else {
        reportOnce(ref.characteristic, "characteristic \(ref.characteristic) not found in service \(ref.service)")
        continue
      }
      guard ch.properties.contains(.notify) || ch.properties.contains(.indicate) else {
        reportOnce(ref.characteristic, "characteristic \(ref.characteristic) supports neither notify nor indicate")
        continue
      }
      pendingNotify.insert(Self.key(ch))
      // Writes the CCCD; Core Bluetooth picks notify or indicate.
      peripheral.setNotifyValue(true, for: ch)
    }
    if pendingNotify.isEmpty { becomeReady() }
  }

  private func becomeReady() {
    guard state != .ready else { return }
    state = .ready
    setupToken += 1
    attempt = 0
    emit(Events.connected(deviceId))
  }

  private func failSetup(_ reason: String) {
    note(reason)
    // didDisconnect (with a nil error) follows and starts the reconnect.
    central.cancelPeripheralConnection(peripheral)
  }

  /// A peripheral that stops answering during setup would otherwise leave
  /// the session stuck; drop the link after 30 s so it reconnects.
  private func armSetupTimeout() {
    setupToken += 1
    let token = setupToken
    queue.asyncAfter(deadline: .now() + 30) { [weak self] in
      guard let self = self, self.setupToken == token,
        self.state == .discovering || self.state == .subscribing
      else { return }
      self.failSetup("setup timed out")
    }
  }

  private func reportOnce(_ key: String, _ detail: String) {
    guard reported.insert(key + detail).inserted else { return }
    emit(Events.blocked(.misconfigured, deviceId: deviceId, detail: detail))
  }

  private func readyCharacteristic<T>(_ ref: CharRef, _ waiter: Waiter<T>) -> CBCharacteristic? {
    guard state == .ready else {
      waiter.finish(.failure(KeeperError(code: "not_connected", message: "device is not connected")))
      return nil
    }
    guard let ch = find(ref) else {
      waiter.finish(
        .failure(
          KeeperError(
            code: "characteristic_not_found",
            message: "characteristic \(ref.characteristic) not found in service \(ref.service)")))
      return nil
    }
    return ch
  }

  private func timeout<T>(_ waiter: Waiter<T>, _ op: String) {
    queue.asyncAfter(deadline: .now() + KeeperConstants.operationTimeout) {
      waiter.finish(.failure(KeeperError(code: "timeout", message: "\(op) timed out")))
    }
  }

  private func find(_ ref: CharRef) -> CBCharacteristic? {
    peripheral.services?
      .first { fullUuid($0.uuid) == ref.service }?
      .characteristics?
      .first { fullUuid($0.uuid) == ref.characteristic }
  }

  private func failAll(_ error: KeeperError) {
    for waiter in reads.values.flatMap({ $0 }) { waiter.finish(.failure(error)) }
    for waiter in writes.values.flatMap({ $0 }) { waiter.finish(.failure(error)) }
    reads.removeAll()
    writes.removeAll()
    writeWithoutResponseQueue.removeAll()
    pendingNotify.removeAll()
    setupToken += 1
  }

  private static func key(_ ch: CBCharacteristic) -> String {
    "\(ch.service.map { fullUuid($0.uuid) } ?? "")/\(fullUuid(ch.uuid))"
  }
}
