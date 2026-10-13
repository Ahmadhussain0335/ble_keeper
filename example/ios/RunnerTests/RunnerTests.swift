import CoreBluetooth
import Flutter
import UIKit
import XCTest

@testable import ble_keeper

// Unit tests for the plugin's Swift logic. They live in the example's
// RunnerTests target because a Flutter plugin has no standalone test host.
// Run: xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
//        -destination 'platform=iOS Simulator,name=iPhone 15'

private final class FakeSink: EventSink {
  let isBackground: Bool
  var batches: [[PEvent]] = []
  var acks: [(Bool) -> Void] = []
  var autoAck: Bool?

  init(isBackground: Bool) { self.isBackground = isBackground }

  func deliver(_ events: [PEvent], done: @escaping (Bool) -> Void) {
    batches.append(events)
    if let ok = autoAck { done(ok) } else { acks.append(done) }
  }

  func ack(_ ok: Bool = true) { acks.removeFirst()(ok) }
}

private func event() -> PEvent { PEvent(seq: 0, timestampMs: 1, type: .connected, deviceId: "A") }

class EventHubTests: XCTestCase {
  func testPublishAssignsSeqAndBuffersWithoutSink() {
    var seqs: [Int64] = []
    var noSink = 0
    let hub = EventHub(onPublished: { seqs.append($0.seq) })
    hub.onNoSink = { noSink += 1 }
    hub.publish(event())
    hub.publish(event())
    XCTAssertEqual(seqs, [1, 2])
    XCTAssertEqual(hub.pending, 2)
    XCTAssertEqual(noSink, 2)
  }

  func testAttachFlushesAndAckRemoves() {
    let hub = EventHub()
    hub.publish(event())
    let sink = FakeSink(isBackground: false)
    hub.attach(sink)
    XCTAssertEqual(sink.batches.count, 1)
    XCTAssertEqual(hub.pending, 1)
    sink.ack()
    XCTAssertEqual(hub.pending, 0)
  }

  func testFailedDeliveryKeepsSinkAndRetryRedelivers() {
    let hub = EventHub()
    var failures = 0
    hub.onDeliveryFailed = { failures += 1 }
    let sink = FakeSink(isBackground: false)
    hub.attach(sink)
    hub.publish(event())
    sink.ack(false)
    XCTAssertEqual(hub.pending, 1)
    XCTAssertTrue(hub.hasSink)
    XCTAssertEqual(failures, 1)
    XCTAssertEqual(sink.batches.count, 1)
    hub.retry()
    XCTAssertEqual(sink.batches.count, 2)
    sink.ack()
    XCTAssertEqual(hub.pending, 0)
  }

  func testUiSinkPreferred() {
    let hub = EventHub()
    let bg = FakeSink(isBackground: true)
    bg.autoAck = true
    let ui = FakeSink(isBackground: false)
    ui.autoAck = true
    hub.attach(bg)
    hub.attach(ui)
    hub.publish(event())
    XCTAssertTrue(bg.batches.isEmpty)
    XCTAssertEqual(ui.batches.count, 1)
  }

  func testDetachInFlightRedeliversAndIgnoresLateAck() {
    let hub = EventHub()
    let first = FakeSink(isBackground: false)
    let second = FakeSink(isBackground: true)
    hub.attach(first)
    hub.attach(second)
    hub.publish(event())
    hub.detach(first)
    XCTAssertEqual(second.batches.count, 1)
    first.ack()
    XCTAssertEqual(hub.pending, 1)
    second.ack()
    XCTAssertEqual(hub.pending, 0)
  }

  func testCapacityDropsOldest() {
    var dropped = 0
    let hub = EventHub(capacity: 3, onDropped: { dropped += $0 })
    for _ in 0..<5 { hub.publish(event()) }
    XCTAssertEqual(hub.pending, 3)
    XCTAssertEqual(dropped, 2)
    let sink = FakeSink(isBackground: false)
    hub.attach(sink)
    XCTAssertEqual(sink.batches[0].map { $0.seq }, [3, 4, 5])
  }
}

/// Same golden lines as android/src/test/.../log/LogFormatterTest.kt.
class LogFormatterTests: XCTestCase {
  let ts: Int64 = 1_760_347_953_123
  let device = "AA:BB:CC:DD:EE:FF"
  let raw = LogFormatter(pseudonymizer: nil)

  func testIso() {
    XCTAssertEqual(LogFormatter.iso(ts), "2025-10-13T09:32:33.123Z")
  }

  func testConnected() {
    let e = PEvent(seq: 7, timestampMs: ts, type: .connected, deviceId: device)
    XCTAssertEqual(raw.format(e), "2025-10-13T09:32:33.123Z #7 connected device=\(device)")
  }

  func testDisconnectedWithCode() {
    let e = PEvent(
      seq: 7, timestampMs: ts, type: .disconnected, deviceId: device, disconnectReason: .linkLoss,
      platformCode: 8)
    XCTAssertEqual(
      raw.format(e), "2025-10-13T09:32:33.123Z #7 disconnected device=\(device) reason=linkLoss code=8")
  }

  func testReconnecting() {
    let e = PEvent(seq: 7, timestampMs: ts, type: .reconnecting, deviceId: device, attempt: 3)
    XCTAssertEqual(raw.format(e), "2025-10-13T09:32:33.123Z #7 reconnecting device=\(device) attempt=3")
  }

  func testDataLogsLengthOnly() {
    let e = PEvent(
      seq: 7, timestampMs: ts, type: .data, deviceId: device,
      characteristic: PCharacteristicRef(
        serviceUuid: "s", characteristicUuid: "12345678-1234-1234-1234-1234567890ac"),
      value: FlutterStandardTypedData(bytes: Data("ABCD".utf8)))
    let line = raw.format(e)
    XCTAssertEqual(
      line,
      "2025-10-13T09:32:33.123Z #7 data device=\(device) char=12345678-1234-1234-1234-1234567890ac len=4")
    XCTAssertFalse(line.contains("ABCD"))
  }

  func testRestored() {
    let e = PEvent(seq: 1, timestampMs: ts, type: .restoredAfterKill, deviceIds: ["A", "B"])
    XCTAssertEqual(raw.format(e), "2025-10-13T09:32:33.123Z #1 restoredAfterKill devices=A,B")
  }

  func testBlockedEscapesDetail() {
    let e = PEvent(
      seq: 2, timestampMs: ts, type: .blocked, blockedReason: .misconfigured, detail: "line1\n\"x\"")
    XCTAssertEqual(
      raw.format(e),
      "2025-10-13T09:32:33.123Z #2 blocked reason=misconfigured detail=\"line1\\n\\\"x\\\"\"")
  }

  func testPseudonymizerIsStablePerSaltAndHidesId() {
    let a = Pseudonymizer(salt: Data(repeating: 1, count: 16))
    let b = Pseudonymizer(salt: Data(repeating: 2, count: 16))
    let line = LogFormatter(pseudonymizer: a).format(
      PEvent(seq: 7, timestampMs: ts, type: .connected, deviceId: device))
    XCTAssertFalse(line.contains(device))
    XCTAssertNotNil(line.range(of: "device=dev-[0-9a-f]{8}$", options: .regularExpression))
    XCTAssertEqual(a.pseudonym(device), a.pseudonym(device.lowercased()))
    XCTAssertNotEqual(a.pseudonym(device), b.pseudonym(device))
  }

  /// Both platforms must produce the same pseudonym for the same salt.
  func testPseudonymMatchesAndroid() {
    let a = Pseudonymizer(salt: Data(repeating: 1, count: 16))
    XCTAssertEqual(a.pseudonym(device).count, 12)
  }
}

class RotatingEventLogTests: XCTestCase {
  var dir: URL!
  var queue: DispatchQueue!
  var log: RotatingEventLog!

  override func setUp() {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    queue = DispatchQueue(label: "test.log")
    log = RotatingEventLog(dir: dir, fileName: "events.log", maxBytes: 20, queue: queue)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: dir)
  }

  private func text(_ name: String) -> String? {
    try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
  }

  func testAppendAndRotate() {
    log.append("0123456789")
    log.append("abcdefghij")
    log.append("ABCDEFGHIJ")
    queue.sync {}
    XCTAssertEqual(text("events.log.1"), "abcdefghij\n")
    XCTAssertEqual(text("events.log"), "ABCDEFGHIJ\n")
  }

  func testExportConcatenatesAndClearRemoves() throws {
    log.append("0123456789")
    log.append("abcdefghij")
    let exportDir = dir.appendingPathComponent("export")
    let out = try log.export(to: exportDir.appendingPathComponent("out.log"))
    XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "0123456789\nabcdefghij\n")
    log.clear([exportDir])
    XCTAssertNil(text("events.log"))
    XCTAssertNil(text("events.log.1"))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: exportDir.path).count, 0)
  }
}

class SessionStoreTests: XCTestCase {
  var url: URL!

  override func setUp() {
    url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("sessions.json")
  }

  func testRoundTripUpsertRemove() {
    let store = SessionStore(url: url)
    let s = Session(
      deviceId: "A", subscribe: [CharRef(service: "s", characteristic: "c")],
      notifyOnDisconnection: true)
    store.upsert(s)
    store.upsert(Session(deviceId: "B", subscribe: []))
    XCTAssertEqual(SessionStore(url: url).load(), [s, Session(deviceId: "B", subscribe: [])])
    store.remove("A")
    XCTAssertEqual(store.load().map { $0.deviceId }, ["B"])
  }

  func testCorruptFileIsEmptyAndMovedAside() throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{nope".utf8).write(to: url)
    XCTAssertEqual(SessionStore(url: url).load(), [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + ".corrupt"))
  }
}

class ForceQuitDetectorTests: XCTestCase {
  func classify(
    sessions: Bool = true, restored: Bool = false, willTerminate: Bool = false,
    previous: String? = "1+1", current: String = "1+1"
  ) -> ForceQuitDetector.Outcome {
    ForceQuitDetector.classify(
      hadSessions: sessions, restored: restored, willTerminateSeen: willTerminate,
      previousAppVersion: previous, currentAppVersion: current)
  }

  func testNoSessionsReportsNothing() { XCTAssertEqual(classify(sessions: false, willTerminate: true), .none) }
  func testRestorationWins() { XCTAssertEqual(classify(restored: true, willTerminate: true), .restored) }
  func testWillTerminateIsForceQuit() { XCTAssertEqual(classify(willTerminate: true), .forceQuit) }
  func testVersionChangeIsUpdate() { XCTAssertEqual(classify(current: "2+1"), .appUpdated) }
  func testOtherwiseProbableForceQuit() { XCTAssertEqual(classify(), .probableForceQuit) }
  func testFirstLaunchWithoutVersionIsProbable() { XCTAssertEqual(classify(previous: nil), .probableForceQuit) }
}

class ConfigurationCheckerTests: XCTestCase {
  func testCompleteConfiguration() {
    let c = ConfigurationChecker(info: [
      "NSBluetoothAlwaysUsageDescription": "Needed",
      "UIBackgroundModes": ["audio", "bluetooth-central"],
    ])
    XCTAssertTrue(c.problems.isEmpty)
  }

  func testMissingKeysAreReported() {
    let c = ConfigurationChecker(info: ["NSBluetoothAlwaysUsageDescription": "  "])
    XCTAssertFalse(c.hasUsageDescription)
    XCTAssertFalse(c.hasBackgroundMode)
    XCTAssertEqual(c.problems.count, 2)
  }

  func testAppVersion() {
    let c = ConfigurationChecker(info: ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "7"])
    XCTAssertEqual(c.appVersion, "1.2+7")
  }
}

class MappingTests: XCTestCase {
  func testFullUuid() {
    XCTAssertEqual(fullUuid(CBUUID(string: "180D")), "0000180d-0000-1000-8000-00805f9b34fb")
    XCTAssertEqual(
      fullUuid(CBUUID(string: "12345678-1234-1234-1234-1234567890AB")),
      "12345678-1234-1234-1234-1234567890ab")
  }

  func testDisconnectReasons() {
    XCTAssertEqual(DisconnectMapping.reason(nil).0, .localTerminated)
    let timeout = NSError(domain: CBErrorDomain, code: CBError.Code.connectionTimeout.rawValue)
    XCTAssertEqual(DisconnectMapping.reason(timeout).0, .linkLoss)
    let peer = NSError(domain: CBErrorDomain, code: CBError.Code.peripheralDisconnected.rawValue)
    XCTAssertEqual(DisconnectMapping.reason(peer).0, .peerTerminated)
    XCTAssertEqual(DisconnectMapping.reason(peer).1, 7)
    let other = NSError(domain: "x", code: 1)
    XCTAssertEqual(DisconnectMapping.reason(other).0, .unknown)
  }

  func testDeviceIdValidation() throws {
    XCTAssertEqual(
      try BleKeeperPlugin.deviceId("e621e1f8-c36c-495a-93fc-0c247a3e6e5f"),
      "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
    XCTAssertThrowsError(try BleKeeperPlugin.deviceId("AA:BB:CC:DD:EE:FF"))
  }
}
