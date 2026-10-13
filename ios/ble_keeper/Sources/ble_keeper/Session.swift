import Foundation

/// A characteristic by lowercase 128-bit UUID strings.
struct CharRef: Codable, Hashable {
  let service: String
  let characteristic: String
}

/// A persisted keepConnected request.
struct Session: Codable, Equatable {
  /// `CBPeripheral.identifier`, upper-case UUID string.
  let deviceId: String
  let subscribe: [CharRef]
  var notifyOnDisconnection: Bool = false
  var enableAutoReconnect: Bool = false
}

/// Error passed to Dart as `BleKeeperException.code`.
struct KeeperError: Error {
  let code: String
  let message: String
}
