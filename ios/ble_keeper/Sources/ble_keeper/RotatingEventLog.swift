import Foundation

/// Append-only text log over two files: `events.log` (current) and
/// `events.log.1` (previous). When the current file would exceed `maxBytes`
/// it becomes the previous one, so at most about 2 x `maxBytes` is kept.
///
/// All file access runs on one serial queue. Lines are buffered and written
/// `flushDelay` after the first unwritten line (or when 16 KB are pending),
/// and before export and clear; the file handle stays open in between. A
/// process kill can lose at most that much of the newest log.
final class RotatingEventLog {
  private let dir: URL
  private let fileName: String
  private let maxBytes: UInt64
  private let queue: DispatchQueue
  private let flushDelay: TimeInterval

  // Queue only.
  private var handle: FileHandle?
  private var size: UInt64 = 0
  private var pending: [Data] = []
  private var pendingBytes = 0
  private var flushScheduled = false

  init(dir: URL, fileName: String, maxBytes: UInt64, queue: DispatchQueue, flushDelay: TimeInterval = 2) {
    self.dir = dir
    self.fileName = fileName
    self.maxBytes = maxBytes
    self.queue = queue
    self.flushDelay = flushDelay
  }

  private var current: URL { dir.appendingPathComponent(fileName) }
  private var previous: URL { dir.appendingPathComponent(fileName + ".1") }

  func append(_ line: String) {
    queue.async { self.appendNow(line) }
  }

  /// Writes buffered lines to disk. Blocks until done.
  func flush() {
    queue.sync { flushNow() }
  }

  /// Writes previous + current into `target`. Earlier exports in the same
  /// directory are deleted. Blocks until done.
  func export(to target: URL) throws -> URL {
    try queue.sync {
      flushNow()
      let fm = FileManager.default
      let exportDir = target.deletingLastPathComponent()
      try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
      // Keep only the newest export so copies do not pile up.
      for f in (try? fm.contentsOfDirectory(at: exportDir, includingPropertiesForKeys: nil)) ?? [] {
        try? fm.removeItem(at: f)
      }
      var data = Data()
      for f in [previous, current] {
        if let chunk = try? Data(contentsOf: f) { data.append(chunk) }
      }
      // Export is a user action in the foreground, so the strictest class works.
      try data.write(to: target, options: [.atomic, .completeFileProtection])
      return target
    }
  }

  /// Deletes both log files and everything in `extraDirs`. Blocks until done.
  func clear(_ extraDirs: [URL] = []) {
    queue.sync {
      pending.removeAll()
      pendingBytes = 0
      closeNow()
      let fm = FileManager.default
      try? fm.removeItem(at: previous)
      try? fm.removeItem(at: current)
      for d in extraDirs {
        for f in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] {
          try? fm.removeItem(at: f)
        }
      }
    }
  }

  private func appendNow(_ line: String) {
    guard let bytes = (line + "\n").data(using: .utf8) else { return }
    pending.append(bytes)
    pendingBytes += bytes.count
    if pendingBytes >= 16 * 1024 {
      flushNow()
    } else if !flushScheduled {
      flushScheduled = true
      queue.asyncAfter(deadline: .now() + flushDelay) { self.flushNow() }
    }
  }

  private func flushNow() {
    flushScheduled = false
    guard !pending.isEmpty else { return }
    let lines = pending
    pending.removeAll()
    pendingBytes = 0
    var chunk = Data()
    for line in lines {
      if size + UInt64(chunk.count) > 0, size + UInt64(chunk.count) + UInt64(line.count) > maxBytes {
        write(chunk)
        chunk = Data()
        rotate()
      }
      chunk.append(line)
    }
    write(chunk)
  }

  private func write(_ data: Data) {
    guard !data.isEmpty else { return }
    if handle == nil { open() }
    guard let handle = handle else { return }
    do {
      try handle.write(contentsOf: data)
      size += UInt64(data.count)
    } catch {
      // Logging must never take the connection down (disk full, etc.).
      closeNow()
    }
  }

  private func open() {
    let fm = FileManager.default
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    if !fm.fileExists(atPath: current.path) {
      StorageLocation.write(Data(), to: current)
    }
    handle = try? FileHandle(forWritingTo: current)
    // seekToEnd gives the size without a file-attribute API (those are
    // required-reason APIs in the privacy manifest).
    size = (try? handle?.seekToEnd()) ?? 0
  }

  private func rotate() {
    closeNow()
    let fm = FileManager.default
    try? fm.removeItem(at: previous)
    try? fm.moveItem(at: current, to: previous)
    open()
  }

  private func closeNow() {
    try? handle?.close()
    handle = nil
    size = 0
  }
}
