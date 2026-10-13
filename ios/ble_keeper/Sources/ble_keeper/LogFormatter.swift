import CryptoKit
import Foundation

/// Formats one line per event, identical to the Android LogFormatter,
/// except Data events, which are summarised per device and characteristic
/// each minute (see `dataSummary`):
///
///     2026-10-13T09:12:33.123Z #42 disconnected device=dev-3f2a91c4 reason=linkLoss code=8
///     2026-10-13T09:13:00.000Z #43-102 data device=dev-3f2a91c4 char=...90ac count=60 bytes=240
///
/// Data minimisation (GDPR Art. 5(1)(c)): payload bytes are never written,
/// only their length. Device identifiers are replaced by a salted HMAC when a
/// pseudonymizer is set (release builds).
struct LogFormatter {
  let pseudonymizer: Pseudonymizer?

  func format(_ e: PEvent) -> String {
    var s = "\(LogFormatter.iso(e.timestampMs)) #\(e.seq) \(LogFormatter.typeName(e.type))"
    if let id = e.deviceId { s += " device=\(deviceLabel(id))" }
    switch e.type {
    case .disconnected:
      s += " reason=\(LogFormatter.reasonName(e.disconnectReason))"
      if let code = e.platformCode { s += " code=\(code)" }
    case .reconnecting:
      s += " attempt=\(e.attempt ?? 0)"
    case .data:
      if let c = e.characteristic { s += " char=\(c.characteristicUuid)" }
      s += " len=\(e.value?.data.count ?? 0)"
    case .restoredAfterKill:
      s += " devices=\((e.deviceIds ?? []).map(deviceLabel).joined(separator: ","))"
    case .blocked:
      s += " reason=\(LogFormatter.blockedName(e.blockedReason))"
      if let detail = e.detail { s += " detail=\(LogFormatter.quote(detail))" }
    case .connected:
      break
    }
    return s
  }

  /// One line for `count` Data events with sequence numbers firstSeq...lastSeq.
  func dataSummary(
    _ timestampMs: Int64, deviceId: String, characteristic: String, count: Int, bytes: Int,
    firstSeq: Int64, lastSeq: Int64
  ) -> String {
    "\(LogFormatter.iso(timestampMs)) #\(firstSeq)-\(lastSeq) data device=\(deviceLabel(deviceId)) "
      + "char=\(characteristic) count=\(count) bytes=\(bytes)"
  }

  /// A diagnostic line that is not an event.
  func note(_ timestampMs: Int64, level: String, _ text: String) -> String {
    "\(LogFormatter.iso(timestampMs)) \(level) \(LogFormatter.quote(text))"
  }

  func deviceLabel(_ id: String) -> String {
    pseudonymizer?.pseudonym(id) ?? id
  }

  static func iso(_ timestampMs: Int64) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return f.string(from: Date(timeIntervalSince1970: Double(timestampMs) / 1000))
  }

  static func quote(_ text: String) -> String {
    let escaped = text
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
    return "\"\(escaped)\""
  }

  static func typeName(_ t: PEventType) -> String {
    switch t {
    case .connected: return "connected"
    case .disconnected: return "disconnected"
    case .reconnecting: return "reconnecting"
    case .data: return "data"
    case .restoredAfterKill: return "restoredAfterKill"
    case .blocked: return "blocked"
    }
  }

  static func reasonName(_ r: PDisconnectReason?) -> String {
    switch r {
    case .peerTerminated: return "peerTerminated"
    case .linkLoss: return "linkLoss"
    case .localTerminated: return "localTerminated"
    case .bluetoothOff: return "bluetoothOff"
    case .stopped: return "stopped"
    case .connectFailed: return "connectFailed"
    case .unknown, .none: return "unknown"
    }
  }

  static func blockedName(_ r: PBlockedReason?) -> String {
    switch r {
    case .bluetoothOff: return "bluetoothOff"
    case .permissionMissing: return "permissionMissing"
    case .foregroundStartNotAllowed: return "foregroundStartNotAllowed"
    case .userForceQuit: return "userForceQuit"
    case .misconfigured: return "misconfigured"
    case .unknown, .none: return "unknown"
    }
  }
}

/// Maps a device ID to a stable per-install pseudonym: `dev-` + 8 hex chars
/// of HMAC-SHA256 over the upper-cased ID.
struct Pseudonymizer {
  private let key: SymmetricKey

  init(salt: Data) {
    key = SymmetricKey(data: salt)
  }

  func pseudonym(_ deviceId: String) -> String {
    let mac = HMAC<SHA256>.authenticationCode(for: Data(deviceId.uppercased().utf8), using: key)
    return "dev-" + mac.prefix(4).map { String(format: "%02x", $0) }.joined()
  }
}

/// Collects Data events between log flushes so the log gets one summary
/// line per device and characteristic per interval. Main thread only.
final class DataAggregator {
  private struct Key: Hashable {
    let deviceId: String
    let characteristic: String
  }

  private struct Bucket {
    let firstSeq: Int64
    var lastSeq: Int64
    var count = 0
    var bytes = 0
  }

  private var order: [Key] = []
  private var buckets: [Key: Bucket] = [:]

  var isEmpty: Bool { buckets.isEmpty }

  func add(_ e: PEvent) {
    let key = Key(deviceId: e.deviceId ?? "", characteristic: e.characteristic?.characteristicUuid ?? "")
    var b = buckets[key] ?? {
      order.append(key)
      return Bucket(firstSeq: e.seq, lastSeq: e.seq)
    }()
    b.lastSeq = e.seq
    b.count += 1
    b.bytes += e.value?.data.count ?? 0
    buckets[key] = b
  }

  /// Summary lines for everything collected since the last drain.
  func drain(_ nowMs: Int64, _ formatter: LogFormatter) -> [String] {
    let lines = order.compactMap { key -> String? in
      guard let b = buckets[key] else { return nil }
      return formatter.dataSummary(
        nowMs, deviceId: key.deviceId, characteristic: key.characteristic, count: b.count,
        bytes: b.bytes, firstSeq: b.firstSeq, lastSeq: b.lastSeq)
    }
    order.removeAll()
    buckets.removeAll()
    return lines
  }
}
