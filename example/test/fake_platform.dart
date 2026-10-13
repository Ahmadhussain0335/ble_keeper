import 'dart:async';
import 'dart:typed_data';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:ble_keeper/ble_keeper_platform_interface.dart';

/// In-memory platform for widget and controller tests.
class FakePlatform extends BleKeeperPlatform {
  final controller = StreamController<KeeperEvent>.broadcast();
  final calls = <String>[];
  final writes = <Uint8List>[];

  @override
  Stream<KeeperEvent> get events => controller.stream;

  @override
  Future<void> keepConnected({
    required String deviceId,
    required List<CharacteristicRef> subscribe,
    AndroidOptions? android,
    IosOptions? ios,
  }) async => calls.add('keep $deviceId');

  @override
  Future<void> stop(String deviceId) async => calls.add('stop $deviceId');

  @override
  Future<void> write(
    String deviceId,
    CharacteristicRef characteristic,
    Uint8List value, {
    bool withResponse = true,
  }) async {
    calls.add('write $deviceId');
    writes.add(value);
  }

  @override
  Future<String> exportLog() async => '/tmp/log';

  @override
  Future<void> clearLog() async {}
}

Data counterData(int value, {String id = 'AA:BB:CC:DD:EE:FF'}) {
  final bytes = ByteData(4)..setUint32(0, value, Endian.little);
  return Data(
    deviceId: id,
    characteristic: CharacteristicRef(
      serviceUuid: '12345678-1234-1234-1234-1234567890ab',
      characteristicUuid: '12345678-1234-1234-1234-1234567890ac',
    ),
    bytes: bytes.buffer.asUint8List(),
    timestamp: DateTime(2026, 10, 13, 9, 30, 15, 42),
  );
}
