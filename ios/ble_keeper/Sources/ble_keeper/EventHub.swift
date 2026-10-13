import Foundation

/// A Dart isolate that receives events.
protocol EventSink: AnyObject {
  /// True for the headless background engine. UI sinks are preferred.
  var isBackground: Bool { get }

  /// Delivers `events`; calls `done(true)` once Dart acknowledged them.
  func deliver(_ events: [PEvent], done: @escaping (Bool) -> Void)
}

/// Buffers events and delivers them to one Dart receiver at a time.
///
/// Main thread only: Flutter channels must be used from the platform thread.
/// Delivery is at-least-once; a batch leaves the buffer only after the
/// receiver acknowledges it, and Dart drops duplicates by `seq`.
/// Same algorithm as the Android EventHub.
final class EventHub {
  private let capacity: Int
  private let maxBatch: Int
  /// Called for every event after its seq is assigned (logging).
  var onPublished: (PEvent) -> Void
  /// Called with the number of events dropped because the buffer was full.
  var onDropped: (Int) -> Void

  private var buffer: [PEvent] = []
  private var sinks: [EventSink] = []
  private var nextSeq: Int64 = 1
  private var inFlight: NSObject?
  private weak var inFlightSink: EventSink?

  /// Called when events are waiting and no sink is attached.
  var onNoSink: () -> Void = {}

  /// Called when a delivery failed (timeout, channel error). The sink stays
  /// attached; dead engines are removed by `detach`. The owner calls
  /// `retry` later.
  var onDeliveryFailed: () -> Void = {}

  init(
    capacity: Int = 1000, maxBatch: Int = 100,
    onPublished: @escaping (PEvent) -> Void = { _ in },
    onDropped: @escaping (Int) -> Void = { _ in }
  ) {
    self.capacity = capacity
    self.maxBatch = maxBatch
    self.onPublished = onPublished
    self.onDropped = onDropped
  }

  var pending: Int { buffer.count }
  var hasSink: Bool { !sinks.isEmpty }
  var hasUiSink: Bool { sinks.contains { !$0.isBackground } }

  func publish(_ event: PEvent) {
    var stamped = event
    stamped.seq = nextSeq
    nextSeq += 1
    onPublished(stamped)
    buffer.append(stamped)
    if buffer.count > capacity {
      let dropped = buffer.count - capacity
      buffer.removeFirst(dropped)
      onDropped(dropped)
    }
    drain()
  }

  func attach(_ sink: EventSink) {
    if !sinks.contains(where: { $0 === sink }) { sinks.append(sink) }
    drain()
  }

  func detach(_ sink: EventSink) {
    sinks.removeAll { $0 === sink }
    if inFlightSink === sink {
      // Its acknowledgement may never come; resend to the next sink.
      inFlight = nil
      inFlightSink = nil
      drain()
    }
  }

  /// Tries delivering again after `onDeliveryFailed`.
  func retry() { drain() }

  private func drain() {
    guard inFlight == nil, !buffer.isEmpty else { return }
    guard let sink = sinks.first(where: { !$0.isBackground }) ?? sinks.first else {
      onNoSink()
      return
    }
    let batch = Array(buffer.prefix(maxBatch))
    let lastSeq = batch[batch.count - 1].seq
    let token = NSObject()
    inFlight = token
    inFlightSink = sink
    sink.deliver(batch) { [weak self] ok in
      guard let self = self, self.inFlight === token else { return }
      self.inFlight = nil
      self.inFlightSink = nil
      if ok {
        // Remove by seq: events may have been dropped while in flight.
        while let first = self.buffer.first, first.seq <= lastSeq { self.buffer.removeFirst() }
        self.drain()
      } else {
        self.onDeliveryFailed()
      }
    }
  }
}
