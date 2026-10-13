import Foundation

/// Persists keepConnected requests so a relaunch (state restoration or a
/// user launch) knows what to reconnect. Atomic writes; a corrupt file is
/// moved aside and treated as empty.
final class SessionStore {
  private struct Envelope: Codable {
    var schemaVersion: Int
    var sessions: [Session]
  }

  static let schemaVersion = 1

  private let url: URL
  private let lock = NSLock()

  init(url: URL) {
    self.url = url
  }

  func load() -> [Session] {
    lock.lock()
    defer { lock.unlock() }
    return loadLocked()
  }

  @discardableResult
  func upsert(_ session: Session) -> [Session] {
    lock.lock()
    defer { lock.unlock() }
    let sessions = loadLocked().filter { $0.deviceId != session.deviceId } + [session]
    saveLocked(sessions)
    return sessions
  }

  @discardableResult
  func remove(_ deviceId: String) -> [Session] {
    lock.lock()
    defer { lock.unlock() }
    let sessions = loadLocked().filter { $0.deviceId != deviceId }
    saveLocked(sessions)
    return sessions
  }

  private func loadLocked() -> [Session] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    do {
      let envelope = try JSONDecoder().decode(Envelope.self, from: data)
      guard envelope.schemaVersion <= SessionStore.schemaVersion else { return [] }
      return envelope.sessions
    } catch {
      let corrupt = url.appendingPathExtension("corrupt")
      try? FileManager.default.removeItem(at: corrupt)
      try? FileManager.default.moveItem(at: url, to: corrupt)
      return []
    }
  }

  private func saveLocked(_ sessions: [Session]) {
    let envelope = Envelope(schemaVersion: SessionStore.schemaVersion, sessions: sessions)
    guard let data = try? JSONEncoder().encode(envelope) else { return }
    StorageLocation.write(data, to: url)
  }
}

/// Where the plugin keeps its files: Application Support, excluded from
/// iCloud/iTunes backup, readable after the first unlock (Core Bluetooth can
/// relaunch the app while the phone is locked).
enum StorageLocation {
  static func directory(_ name: String = KeeperConstants.storageDirectory) -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    var dir = base.appendingPathComponent(name, isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(
        at: dir, withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? dir.setResourceValues(values)
    }
    return dir
  }

  static func write(_ data: Data, to url: URL) {
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
