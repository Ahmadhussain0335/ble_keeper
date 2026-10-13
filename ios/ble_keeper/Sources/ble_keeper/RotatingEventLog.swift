import Foundation

/// Append-only text log over two files: `events.log` (current) and
/// `events.log.1` (previous). When the current file would exceed `maxBytes`
/// it becomes the previous one, so at most about 2 x `maxBytes` is kept.
/// All file access runs on one serial queue.
final class RotatingEventLog {
  private let dir: URL
  private let fileName: String
  private let maxBytes: UInt64
  private let queue: DispatchQueue

  init(dir: URL, fileName: String, maxBytes: UInt64, queue: DispatchQueue) {
    self.dir = dir
    self.fileName = fileName
    self.maxBytes = maxBytes
    self.queue = queue
  }

  private var current: URL { dir.appendingPathComponent(fileName) }
  private var previous: URL { dir.appendingPathComponent(fileName + ".1") }

  func append(_ line: String) {
    queue.async { self.appendNow(line) }
  }

  /// Writes previous + current into `target`. Blocks until done.
  func export(to target: URL) throws -> URL {
    try queue.sync {
      let fm = FileManager.default
      try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      var data = Data()
      for f in [previous, current] {
        if let chunk = try? Data(contentsOf: f) { data.append(chunk) }
      }
      try data.write(to: target, options: .atomic)
      return target
    }
  }

  /// Deletes both log files and everything in `extraDirs`. Blocks until done.
  func clear(_ extraDirs: [URL] = []) {
    queue.sync {
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
    let fm = FileManager.default
    guard let bytes = (line + "\n").data(using: .utf8) else { return }
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: current) {
      // seekToEnd gives the size without a file-attribute API (those are
      // required-reason APIs in the privacy manifest).
      let size = (try? handle.seekToEnd()) ?? 0
      if size + UInt64(bytes.count) > maxBytes {
        try? handle.close()
        try? fm.removeItem(at: previous)
        try? fm.moveItem(at: current, to: previous)
        StorageLocation.write(bytes, to: current)
        return
      }
      try? handle.write(contentsOf: bytes)
      try? handle.close()
    } else {
      StorageLocation.write(bytes, to: current)
    }
  }
}
