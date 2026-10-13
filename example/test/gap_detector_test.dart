import 'dart:typed_data';

import 'package:ble_keeper_example/src/gap_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCounter', () {
    test('reads uint32 little-endian', () {
      expect(
        parseCounter(Uint8List.fromList([0x01, 0x02, 0x00, 0x00])),
        0x0201,
      );
      expect(
        parseCounter(Uint8List.fromList([0xff, 0xff, 0xff, 0xff])),
        0xffffffff,
      );
    });

    test('ignores extra bytes', () {
      expect(parseCounter(Uint8List.fromList([5, 0, 0, 0, 9])), 5);
    });

    test('returns null for short payloads', () {
      expect(parseCounter(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('GapDetector', () {
    test('consecutive values have no gap', () {
      final g = GapDetector();
      expect([1, 2, 3].map(g.add), [0, 0, 0]);
      expect(g.missed, 0);
      expect(g.received, 3);
    });

    test('a jump counts the missed values', () {
      final g = GapDetector();
      g.add(10);
      expect(g.add(15), 4);
      expect(g.add(20), 4);
      expect(g.missed, 8);
    });

    test('a repeated value is not a gap', () {
      final g = GapDetector()..add(5);
      expect(g.add(5), 0);
    });

    test('a lower value is a reset, not a gap', () {
      final g = GapDetector()..add(500);
      expect(g.add(1), 0);
      expect(g.resets, 1);
      expect(g.add(3), 1);
      expect(g.missed, 1);
    });

    test('wrap-around at 2^32 is a gap, not a reset', () {
      final g = GapDetector()..add(0xfffffffe);
      expect(g.add(1), 2); // missed 0xffffffff and 0
      expect(g.resets, 0);
    });

    test('reset clears all counters', () {
      final g = GapDetector()
        ..add(1)
        ..add(5)
        ..reset();
      expect(g.missed, 0);
      expect(g.received, 0);
      expect(g.last, isNull);
    });
  });
}
