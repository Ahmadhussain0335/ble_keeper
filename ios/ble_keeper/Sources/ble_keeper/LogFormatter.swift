import CryptoKit
import Foundation

/// Formats one event per line, identical to the Android LogFormatter:
///
///     2026-10-13T09:12:33.123Z #42 data device=dev-3f2a91c4 char=...90ac len=4
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
