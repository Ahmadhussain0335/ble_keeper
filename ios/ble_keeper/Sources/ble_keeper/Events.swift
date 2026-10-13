import Flutter
import Foundation

/// Builders for event envelopes. `seq` is assigned later by EventHub.
enum Events {
  static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

  static func connected(_ deviceId: String) -> PEvent {
    PEvent(seq: 0, timestampMs: now(), type: .connected, deviceId: deviceId)
  }

  static func disconnected(_ deviceId: String, _ reason: PDisconnectReason, code: Int?) -> PEvent {
    PEvent(
      seq: 0, timestampMs: now(), type: .disconnected, deviceId: deviceId,
      disconnectReason: reason, platformCode: code.map(Int64.init))
  }

  static func reconnecting(_ deviceId: String, attempt: Int) -> PEvent {
    PEvent(
      seq: 0, timestampMs: now(), type: .reconnecting, deviceId: deviceId,
      attempt: Int64(attempt))
  }

  static func data(_ deviceId: String, _ c: CharRef, _ value: Data, timestampMs: Int64) -> PEvent {
    PEvent(
      seq: 0, timestampMs: timestampMs, type: .data, deviceId: deviceId,
      characteristic: PCharacteristicRef(serviceUuid: c.service, characteristicUuid: c.characteristic),
      value: FlutterStandardTypedData(bytes: value))
  }

  static func restored(_ deviceIds: [String]) -> PEvent {
    PEvent(seq: 0, timestampMs: now(), type: .restoredAfterKill, deviceIds: deviceIds)
  }

  static func blocked(_ reason: PBlockedReason, deviceId: String? = nil, detail: String? = nil)
    -> PEvent
  {
    PEvent(
      seq: 0, timestampMs: now(), type: .blocked, deviceId: deviceId, blockedReason: reason,
      detail: detail)
  }
}
