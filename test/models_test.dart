import 'package:ble_keeper/ble_keeper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeUuid', () {
    test('expands a 16-bit UUID with the Bluetooth base UUID', () {
      expect(normalizeUuid('180D'), '0000180d-0000-1000-8000-00805f9b34fb');
    });

    test('expands a 32-bit UUID', () {
      expect(normalizeUuid('0000180d'), '0000180d-0000-1000-8000-00805f9b34fb');
    });

    test('lowercases a 128-bit UUID', () {
      expect(
        normalizeUuid('12345678-1234-1234-1234-1234567890AB'),
        '12345678-1234-1234-1234-1234567890ab',
      );
    });

    test('adds dashes to a 128-bit UUID without them', () {
      expect(
        normalizeUuid('123456781234123412341234567890ab'),
        '12345678-1234-1234-1234-1234567890ab',
      );
    });

    test('trims whitespace', () {
      expect(normalizeUuid(' 180d '), '0000180d-0000-1000-8000-00805f9b34fb');
    });

    for (final bad in [
      '',
      '18',
      '180g',
      '12345',
      '12345678-1234-1234-1234-1234567890a',
      '12345678_1234_1234_1234_1234567890ab',
    ]) {
      test('rejects "$bad"', () {
        expect(() => normalizeUuid(bad), throwsArgumentError);
      });
    }
  });

  group('CharacteristicRef', () {
    test('normalises both UUIDs', () {
      final c = CharacteristicRef(
        serviceUuid: '180D',
        characteristicUuid: '2A37',
      );
      expect(c.serviceUuid, '0000180d-0000-1000-8000-00805f9b34fb');
      expect(c.characteristicUuid, '00002a37-0000-1000-8000-00805f9b34fb');
    });

    test('equal when UUIDs are equal after normalisation', () {
      final a = CharacteristicRef(
        serviceUuid: '180d',
        characteristicUuid: '2a37',
      );
      final b = CharacteristicRef(
        serviceUuid: '0000180D-0000-1000-8000-00805F9B34FB',
        characteristicUuid: '00002a37-0000-1000-8000-00805f9b34fb',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('rejects an invalid UUID', () {
      expect(
        () =>
            CharacteristicRef(serviceUuid: 'nope', characteristicUuid: '2a37'),
        throwsArgumentError,
      );
    });
  });

  group('options defaults', () {
    test('AndroidOptions restarts on boot by default', () {
      expect(const AndroidOptions().restartOnBoot, isTrue);
    });

    test('IosOptions disables system options by default', () {
      const o = IosOptions();
      expect(o.notifyOnDisconnection, isFalse);
      expect(o.enableAutoReconnect, isFalse);
    });
  });
}
