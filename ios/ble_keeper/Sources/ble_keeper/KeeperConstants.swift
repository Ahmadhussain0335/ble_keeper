import Foundation

/// Every name-bearing string the plugin persists or registers with the OS.
/// Changing these after a release orphans existing users' sessions and logs.
enum KeeperConstants {
  /// Core Bluetooth state restoration identifier. iOS hands the preserved
  /// state back only to a manager created with the same identifier.
  static let restoreIdentifier = "com.ahmadhussain.ble_keeper.central"

  static let storageDirectory = "ble_keeper"
  static let sessionsFile = "sessions.json"
  static let stateFile = "state.json"
  static let logDirectory = "logs"
  static let logFile = "events.log"
  static let exportDirectory = "ble_keeper_export"
  static let logMaxBytes: UInt64 = 1_000_000

  static let bleQueueLabel = "com.ahmadhussain.ble_keeper.ble"
  static let logQueueLabel = "com.ahmadhussain.ble_keeper.log"
  static let headlessEngineName = "ble_keeper_background"

  /// Attribute values are at most 512 bytes (Core Spec Vol 3, Part F, 3.2.9).
  static let maxAttributeLength = 512
  static let operationTimeout: TimeInterval = 10
}
