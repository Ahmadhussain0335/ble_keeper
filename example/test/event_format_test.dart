import 'dart:typed_data';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:ble_keeper_example/src/event_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime(2026, 10, 13, 9, 5, 7, 8);
  const id = 'AA:BB:CC:DD:EE:FF';

  test('time is HH:mm:ss.SSS', () {
    expect(formatTime(t), '09:05:07.008');
  });

  test('formats every event type', () {
    expect(
      formatEvent(Connected(deviceId: id, timestamp: t)),
      '09:05:07.008  connected $id',
    );
    expect(
      formatEvent(
        Disconnected(
          deviceId: id,
          reason: DisconnectReason.linkLoss,
          platformCode: 8,
          timestamp: t,
        ),
      ),
      '09:05:07.008  disconnected $id: linkLoss (code 8)',
    );
    expect(
      formatEvent(Reconnecting(deviceId: id, attempt: 2, timestamp: t)),
      '09:05:07.008  reconnecting $id, attempt 2',
    );
    expect(
      formatEvent(
        Data(
          deviceId: id,
          characteristic: CharacteristicRef(
            serviceUuid: '180d',
            characteristicUuid: '2a37',
          ),
          bytes: Uint8List(4),
          timestamp: t,
        ),
      ),
      '09:05:07.008  data $id: 4 bytes',
    );
    expect(
      formatEvent(RestoredAfterKill(deviceIds: const [id], timestamp: t)),
      '09:05:07.008  restored after kill: $id',
    );
  });

  test('formats every blocked reason', () {
    String f(BlockedReason r, [String? d]) =>
        formatEvent(Blocked(reason: r, deviceId: d, timestamp: t));
    expect(f(const BluetoothOff()), '09:05:07.008  BLOCKED Bluetooth is off');
    expect(
      f(const PermissionMissing('android.permission.BLUETOOTH_CONNECT'), id),
      '09:05:07.008  BLOCKED permission missing: android.permission.BLUETOOTH_CONNECT ($id)',
    );
    expect(
      f(const ForegroundStartNotAllowed()),
      contains('from the background'),
    );
    expect(f(const UserForceQuit()), contains('force-quit'));
    expect(
      f(const Misconfigured('x')),
      '09:05:07.008  BLOCKED misconfigured: x',
    );
    expect(f(const UnknownBlockedReason()), '09:05:07.008  BLOCKED unknown');
  });
}
