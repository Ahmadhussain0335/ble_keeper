import 'dart:typed_data';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:ble_keeper/src/event_mapper.dart';
import 'package:ble_keeper/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

const _device = 'AA:BB:CC:DD:EE:FF';
const _ts = 1760000000123;
final _char = PCharacteristicRef(
  serviceUuid: '12345678-1234-1234-1234-1234567890ab',
  characteristicUuid: '12345678-1234-1234-1234-1234567890ac',
);

PEvent _event(PEventType type) =>
    PEvent(seq: 1, timestampMs: _ts, type: type, deviceId: _device);

void main() {
  test('every event carries the native timestamp', () {
    final e = mapEvent(_event(PEventType.connected));
    expect(e.timestamp, DateTime.fromMillisecondsSinceEpoch(_ts));
  });

  test('connected', () {
    final e = mapEvent(_event(PEventType.connected));
    expect(e, isA<Connected>().having((c) => c.deviceId, 'deviceId', _device));
  });

  test('disconnected keeps reason and platform code', () {
    final e = mapEvent(
      _event(PEventType.disconnected)
        ..disconnectReason = PDisconnectReason.linkLoss
        ..platformCode = 8,
    );
    expect(
      e,
      isA<Disconnected>()
          .having((d) => d.reason, 'reason', DisconnectReason.linkLoss)
          .having((d) => d.platformCode, 'platformCode', 8),
    );
  });

  test('disconnected without reason maps to unknown', () {
    final e = mapEvent(_event(PEventType.disconnected)) as Disconnected;
    expect(e.reason, DisconnectReason.unknown);
  });

  test('every disconnect reason maps to the same name', () {
    for (final r in PDisconnectReason.values) {
      final e = mapEvent(
        _event(PEventType.disconnected)..disconnectReason = r,
      ) as Disconnected;
      expect(e.reason.name, r.name);
    }
  });

  test('reconnecting carries the attempt', () {
    final e = mapEvent(_event(PEventType.reconnecting)..attempt = 3);
    expect(e, isA<Reconnecting>().having((r) => r.attempt, 'attempt', 3));
  });

  test('reconnecting without attempt is malformed', () {
    expect(
      () => mapEvent(_event(PEventType.reconnecting)),
      throwsA(isA<MalformedEventException>()),
    );
  });

  test('data carries characteristic and bytes', () {
    final e = mapEvent(
      _event(PEventType.data)
        ..characteristic = _char
        ..value = Uint8List.fromList([1, 0, 0, 0]),
    );
    expect(
      e,
      isA<Data>()
          .having(
            (d) => d.characteristic,
            'characteristic',
            CharacteristicRef(
              serviceUuid: _char.serviceUuid,
              characteristicUuid: _char.characteristicUuid,
            ),
          )
          .having((d) => d.bytes, 'bytes', [1, 0, 0, 0]),
    );
  });

  test('data with no value maps to empty bytes', () {
    final e = mapEvent(_event(PEventType.data)..characteristic = _char) as Data;
    expect(e.bytes, isEmpty);
  });

  test('data without characteristic is malformed', () {
    expect(
      () => mapEvent(_event(PEventType.data)),
      throwsA(isA<MalformedEventException>()),
    );
  });

  test('device events without deviceId are malformed', () {
    for (final type in [
      PEventType.connected,
      PEventType.disconnected,
      PEventType.reconnecting,
      PEventType.data,
    ]) {
      expect(
        () => mapEvent(
          PEvent(seq: 1, timestampMs: _ts, type: type)
            ..attempt = 1
            ..characteristic = _char,
        ),
        throwsA(isA<MalformedEventException>()),
        reason: type.name,
      );
    }
  });

  test('restoredAfterKill lists devices', () {
    final e = mapEvent(
      PEvent(seq: 1, timestampMs: _ts, type: PEventType.restoredAfterKill)
        ..deviceIds = [_device, '11:22:33:44:55:66'],
    );
    expect(
      e,
      isA<RestoredAfterKill>().having((r) => r.deviceIds, 'deviceIds', [
        _device,
        '11:22:33:44:55:66',
      ]),
    );
  });

  group('blocked', () {
    PEvent blocked(PBlockedReason? r, [String? detail]) =>
        PEvent(seq: 1, timestampMs: _ts, type: PEventType.blocked)
          ..blockedReason = r
          ..detail = detail;

    test('bluetoothOff has no device', () {
      final e = mapEvent(blocked(PBlockedReason.bluetoothOff)) as Blocked;
      expect(e.reason, const BluetoothOff());
      expect(e.deviceId, isNull);
    });

    test('permissionMissing carries the permission name', () {
      final e = mapEvent(
        blocked(
          PBlockedReason.permissionMissing,
          'android.permission.BLUETOOTH_CONNECT',
        ),
      ) as Blocked;
      expect(
        e.reason,
        const PermissionMissing('android.permission.BLUETOOTH_CONNECT'),
      );
    });

    test('foregroundStartNotAllowed', () {
      final e = mapEvent(
        blocked(PBlockedReason.foregroundStartNotAllowed),
      ) as Blocked;
      expect(e.reason, const ForegroundStartNotAllowed());
    });

    test('userForceQuit keeps the device', () {
      final e = mapEvent(
        blocked(PBlockedReason.userForceQuit)..deviceId = _device,
      ) as Blocked;
      expect(e.reason, const UserForceQuit());
      expect(e.deviceId, _device);
    });

    test('misconfigured carries the detail', () {
      final e = mapEvent(
        blocked(PBlockedReason.misconfigured, 'missing key'),
      ) as Blocked;
      expect(e.reason, const Misconfigured('missing key'));
    });

    test('missing reason maps to unknown', () {
      final e = mapEvent(blocked(null, 'x')) as Blocked;
      expect(e.reason, const UnknownBlockedReason('x'));
    });
  });

  test('toWire keeps the normalised UUIDs', () {
    final w = toWire(
      CharacteristicRef(serviceUuid: '180d', characteristicUuid: '2a37'),
    );
    expect(w.serviceUuid, '0000180d-0000-1000-8000-00805f9b34fb');
    expect(w.characteristicUuid, '00002a37-0000-1000-8000-00805f9b34fb');
  });

  test('PEvent survives the Pigeon codec round trip', () {
    const codec = BleKeeperHostApi.pigeonChannelCodec;
    final original = PEvent(
      seq: 42,
      timestampMs: _ts,
      type: PEventType.data,
      deviceId: _device,
      characteristic: _char,
      value: Uint8List.fromList([9, 8, 7]),
      deviceIds: [_device],
    );
    final decoded =
        codec.decodeMessage(codec.encodeMessage(original)) as PEvent;
    expect(decoded.seq, 42);
    expect(decoded.type, PEventType.data);
    expect(
      decoded.characteristic?.characteristicUuid,
      _char.characteristicUuid,
    );
    expect(decoded.value, [9, 8, 7]);
    expect(decoded.deviceIds, [_device]);
  });
}
