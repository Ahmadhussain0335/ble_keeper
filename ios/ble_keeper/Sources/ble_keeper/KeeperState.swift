import Foundation
import Security

/// Small persistent state: background callback handles, the log salt and
/// the markers used by the force-quit heuristic. A file rather than
/// UserDefaults keeps it out of backups (handles are only valid for the
/// installed build) and avoids the UserDefaults required-reason entry.
final class KeeperState {
  private struct Values: Codable {
    var dispatcherHandle: Int64?
    var handlerHandle: Int64?
    var salt: String?
    var appVersion: String?
    var willTerminateSeen: Bool?
  }

  private let url: URL
  private let lock = NSLock()
  private var cache: Values?

  init(url: URL) {
    self.url = url
  }

  var dispatcherHandle: Int64? { read { $0.dispatcherHandle } }
  var handlerHandle: Int64? { read { $0.handlerHandle } }

  func setHandles(dispatcher: Int64, handler: Int64) {
    update {
      $0.dispatcherHandle = dispatcher
      $0.handlerHandle = handler
    }
  }

  /// App version recorded at the previous launch.
  var appVersion: String? { read { $0.appVersion } }

  func setAppVersion(_ version: String) {
    update { $0.appVersion = version }
  }

  /// True when `applicationWillTerminate` ran during the previous launch.
  var willTerminateSeen: Bool { read { $0.willTerminateSeen ?? false } }

  func setWillTerminateSeen(_ value: Bool) {
    update { $0.willTerminateSeen = value }
  }

  /// Per-install random salt for log pseudonyms. Created on first use.
  func salt() -> Data {
    lock.lock()
    defer { lock.unlock() }
    var values = loadLocked()
    if let hex = values.salt, let data = Data(hex: hex), data.count == 16 { return data }
    var bytes = [UInt8](repeating: 0, count: 16)
    if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
      bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
    }
    let data = Data(bytes)
    values.salt = data.map { String(format: "%02x", $0) }.joined()
    saveLocked(values)
    return data
  }

  private func read<T>(_ body: (Values) -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body(loadLocked())
  }

  private func update(_ body: (inout Values) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    var values = loadLocked()
    body(&values)
    saveLocked(values)
  }

  private func loadLocked() -> Values {
    if let cache = cache { return cache }
    let values = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Values.self, from: $0) }
      ?? Values()
    cache = values
    return values
  }

  private func saveLocked(_ values: Values) {
    cache = values
    if let data = try? JSONEncoder().encode(values) {
      StorageLocation.write(data, to: url)
    }
  }
}

extension Data {
  init?(hex: String) {
    guard hex.count % 2 == 0 else { return nil }
    var bytes = [UInt8]()
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}
