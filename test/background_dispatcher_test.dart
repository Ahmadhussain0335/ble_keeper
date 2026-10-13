import 'dart:async';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:ble_keeper/src/background_dispatcher.dart';
import 'package:ble_keeper/src/messages.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

PEvent _connected(int seq) => PEvent(
  seq: seq,
  timestampMs: 0,
  type: PEventType.connected,
  deviceId: 'id',
);

void main() {
  test(
    'calls the handler once per event, in order, without duplicates',
    () async {
      final received = <int>[];
      final receiver = BackgroundEventReceiver(
        (KeeperEvent e) => received.add(e.timestamp.millisecondsSinceEpoch),
      );

      await receiver.onEvents([_connected(1), _connected(2)]);
      await receiver.onEvents([_connected(2)]);

      expect(received, hasLength(2));
    },
  );

  test('waits for an async handler before acknowledging', () async {
    final gate = Completer<void>();
    var finished = false;
    final receiver = BackgroundEventReceiver((KeeperEvent e) async {
      await gate.future;
      finished = true;
    });

    final ack = receiver.onEvents([_connected(1)]);
    var acked = false;
    unawaited(ack.then((_) => acked = true));
    await pumpEventQueue();
    expect(acked, isFalse);

    gate.complete();
    await ack;
    expect(finished, isTrue);
  });

  test(
    'a throwing handler is reported and the batch is still acknowledged',
    () async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      var calls = 0;
      final receiver = BackgroundEventReceiver((KeeperEvent e) {
        calls++;
        throw StateError('boom');
      });

      await receiver.onEvents([_connected(1), _connected(2)]);

      expect(calls, 2);
      expect(errors, hasLength(2));
    },
  );

  test('a malformed event is reported and skipped', () async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    var calls = 0;
    final receiver = BackgroundEventReceiver((KeeperEvent e) => calls++);

    await receiver.onEvents([
      PEvent(seq: 1, timestampMs: 0, type: PEventType.connected),
      _connected(2),
    ]);

    expect(calls, 1);
    expect(errors, hasLength(1));
  });
}
