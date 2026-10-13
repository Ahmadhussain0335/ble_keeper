import Flutter
import UIKit

/// Flutter entry point. One instance per Flutter engine (the UI engine and,
/// when used, the headless background engine). Connections are owned by
/// KeeperRuntime / CentralManagerHolder, not by this class.
public class BleKeeperPlugin: NSObject, FlutterPlugin, BleKeeperHostApi {

  /// Call from `application(_:didFinishLaunchingWithOptions:)`, before
  /// `super`. Required for Core Bluetooth state restoration (the central
  /// manager must exist before didFinishLaunching returns when iOS relaunches
  /// the app in the background) and for the background handler.
  ///
  /// ```swift
  /// BleKeeperPlugin.bootstrap(launchOptions: launchOptions) { registry in
  ///   GeneratedPluginRegistrant.register(with: registry)
  /// }
  /// ```
  public static func bootstrap(
    launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
    pluginRegistrant: @escaping (FlutterPluginRegistry) -> Void
  ) {
    KeeperRuntime.shared.bootstrap(launchOptions: launchOptions, registrant: pluginRegistrant)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let runtime = KeeperRuntime.shared
    let instance = BleKeeperPlugin(
      messenger: registrar.messenger(), isHeadless: runtime.headless.registering)
    BleKeeperHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    registrar.publish(instance)
    runtime.pluginRegistered(isHeadless: instance.isHeadless)
  }

  private let messenger: FlutterBinaryMessenger
  private let eventApi: BleKeeperEventApi
  let isHeadless: Bool
  private var sink: PluginSink?

  init(messenger: FlutterBinaryMessenger, isHeadless: Bool) {
    self.messenger = messenger
    self.eventApi = BleKeeperEventApi(binaryMessenger: messenger)
    self.isHeadless = isHeadless
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    BleKeeperHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    try? detach()
    KeeperRuntime.shared.pluginDetached(isHeadless: isHeadless)
  }

  private var runtime: KeeperRuntime { KeeperRuntime.shared }

  // MARK: BleKeeperHostApi

  func keepConnected(request: PKeepRequest) async throws {
    try guarded {
      let deviceId = try Self.deviceId(request.deviceId)
      guard !request.subscribe.isEmpty else {
        throw KeeperError(code: "invalid_argument", message: "subscribe must not be empty")
      }
      var subscribe: [CharRef] = []
      for c in request.subscribe where !subscribe.contains(try Self.charRef(c)) {
        subscribe.append(try Self.charRef(c))
      }
      runtime.keep(
        Session(
          deviceId: deviceId, subscribe: subscribe,
          notifyOnDisconnection: request.ios?.notifyOnDisconnection ?? false,
          enableAutoReconnect: request.ios?.enableAutoReconnect ?? false))
    }
  }

  func stop(deviceId: String) async throws {
    try guarded { runtime.stop(try Self.deviceId(deviceId)) }
  }

  func write(
    deviceId: String, characteristic: PCharacteristicRef, value: FlutterStandardTypedData,
    withResponse: Bool
  ) async throws {
    do {
      let id = try Self.deviceId(deviceId)
      let ref = try Self.charRef(characteristic)
      guard let central = runtime.central else { throw notRunning(id) }
      try await central.write(id, ref, value.data, withResponse: withResponse)
    } catch let e as KeeperError {
      throw BleKeeperPigeonError(code: e.code, message: e.message, details: nil)
    }
  }

  func read(deviceId: String, characteristic: PCharacteristicRef) async throws
    -> FlutterStandardTypedData
  {
    do {
      let id = try Self.deviceId(deviceId)
      let ref = try Self.charRef(characteristic)
      guard let central = runtime.central else { throw notRunning(id) }
      return FlutterStandardTypedData(bytes: try await central.read(id, ref))
    } catch let e as KeeperError {
      throw BleKeeperPigeonError(code: e.code, message: e.message, details: nil)
    }
  }

  func registerBackgroundHandler(dispatcherHandle: Int64, handlerHandle: Int64) throws {
    runtime.state.setHandles(dispatcher: dispatcherHandle, handler: handlerHandle)
    runtime.headless.reset()
  }

  func backgroundHandlerHandle() throws -> Int64? {
    runtime.state.handlerHandle
  }

  func exportLog() async throws -> String {
    do {
      return try runtime.exportLog().path
    } catch {
      throw BleKeeperPigeonError(code: "io_error", message: error.localizedDescription, details: nil)
    }
  }

  func clearLog() async throws {
    runtime.clearLog()
  }

  func attach(isBackground: Bool) throws {
    if let old = sink { runtime.hub.detach(old) }
    let s = PluginSink(eventApi: eventApi, isBackground: isBackground)
    sink = s
    runtime.attachSink(s)
  }

  func detach() throws {
    guard let s = sink else { return }
    sink = nil
    runtime.hub.detach(s)
  }

  func activeDeviceIds() throws -> [String] {
    runtime.sessions.load().map { $0.deviceId }
  }

  // MARK: Helpers

  private func guarded(_ body: () throws -> Void) throws {
    do {
      try body()
    } catch let e as KeeperError {
      throw BleKeeperPigeonError(code: e.code, message: e.message, details: nil)
    }
  }

  private func notRunning(_ id: String) -> KeeperError {
    runtime.sessions.load().contains { $0.deviceId == id }
      ? KeeperError(code: "not_connected", message: "device is not connected")
      : KeeperError(code: "unknown_device", message: "keepConnected was not called for this device")
  }

  static func deviceId(_ raw: String) throws -> String {
    guard let uuid = UUID(uuidString: raw.trimmingCharacters(in: .whitespaces)) else {
      throw KeeperError(
        code: "invalid_argument",
        message: "on iOS the device ID is the CBPeripheral identifier UUID")
    }
    return uuid.uuidString
  }

  static func charRef(_ c: PCharacteristicRef) throws -> CharRef {
    guard let s = UUID(uuidString: c.serviceUuid), let ch = UUID(uuidString: c.characteristicUuid) else {
      throw KeeperError(code: "invalid_argument", message: "invalid UUID")
    }
    return CharRef(service: s.uuidString.lowercased(), characteristic: ch.uuidString.lowercased())
  }
}

/// Delivers event batches to Dart in one engine and reports the ack.
private final class PluginSink: EventSink {
  let isBackground: Bool
  private let eventApi: BleKeeperEventApi

  init(eventApi: BleKeeperEventApi, isBackground: Bool) {
    self.eventApi = eventApi
    self.isBackground = isBackground
  }

  func deliver(_ events: [PEvent], done: @escaping (Bool) -> Void) {
    var task = UIBackgroundTaskIdentifier.invalid
    var finished = false
    // A Bluetooth wake gives a suspended app a few seconds; the background
    // task covers the round trip to Dart. A slow handler must not hold the
    // queue forever, so the batch is failed after 60 s.
    let finish: (Bool) -> Void = { ok in
      guard !finished else { return }
      finished = true
      done(ok)
      if task != .invalid {
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
      }
    }
    task = UIApplication.shared.beginBackgroundTask(withName: "ble_keeper.deliver") { finish(false) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { finish(false) }
    let api = eventApi
    Task { @MainActor in
      do {
        try await api.onEvents(events: events)
        finish(true)
      } catch {
        finish(false)
      }
    }
  }
}
