import 'dart:convert';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:ble_keeper/ble_keeper_platform_interface.dart';
import 'package:ble_keeper_example/src/device_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

void main() {
  late FakePlatform fake;
  late DeviceController c;
  const id = 'AA:BB:CC:DD:EE:FF';

  setUp(() {
    fake = FakePlatform();
    BleKeeperPlatform.instance = fake;
    c = DeviceController(BleKeeper.instance);
  });

  tearDown(() => c.dispose());

  test('adopts a device the plugin already keeps connected', () async {
    fake.active = [id];
    expect(await c.adoptActiveDevice(), id);
    expect(c.state.value.deviceId, id);
    await c.sendCommand('silent');
    expect(fake.calls, ['write $id']);
  });

  test('adopts nothing when no device is kept', () async {
    expect(await c.adoptActiveDevice(), isNull);
    expect(c.state.value.deviceId, isNull);
  });

  test('does not replace a device chosen in this run', () async {
    await c.keep(id);
    fake.active = ['11:22:33:44:55:66'];
    expect(await c.adoptActiveDevice(), isNull);
    expect(c.state.value.deviceId, id);
  });

  test('keep sets the device and connecting state', () async {
    await c.keep(' $id ');
    expect(fake.calls, ['keep $id']);
    expect(c.state.value.deviceId, id);
    expect(c.state.value.link, LinkState.connecting);
  });

  test('data updates counter and missed count', () async {
    await c.keep(id);
    for (final v in [1, 2, 6]) {
      fake.controller.add(counterData(v));
    }
    await pumpEventQueue();
    final s = c.state.value;
    expect(s.counter, 6);
    expect(s.received, 3);
    expect(s.missed, 3);
    expect(s.link, LinkState.connected);
    expect(s.log.last, contains('gap: missed 3'));
  });

  test('a reboot is a reset, not missed values', () async {
    await c.keep(id);
    fake.controller
      ..add(counterData(100))
      ..add(counterData(1));
    await pumpEventQueue();
    expect(c.state.value.missed, 0);
    expect(c.state.value.resets, 1);
  });

  test('connection events change the link state', () async {
    final t = DateTime(2026);
    await c.keep(id);
    fake.controller.add(Connected(deviceId: id, timestamp: t));
    await pumpEventQueue();
    expect(c.state.value.link, LinkState.connected);

    fake.controller.add(
      Disconnected(
        deviceId: id,
        reason: DisconnectReason.linkLoss,
        timestamp: t,
      ),
    );
    await pumpEventQueue();
    expect(c.state.value.link, LinkState.reconnecting);

    fake.controller.add(Blocked(reason: const BluetoothOff(), timestamp: t));
    await pumpEventQueue();
    expect(c.state.value.link, LinkState.blocked);
    expect(c.state.value.lastProblem, contains('Bluetooth is off'));

    fake.controller.add(
      Disconnected(
        deviceId: id,
        reason: DisconnectReason.stopped,
        timestamp: t,
      ),
    );
    await pumpEventQueue();
    expect(c.state.value.link, LinkState.idle);
  });

  test('sendCommand writes UTF-8 to the command characteristic', () async {
    await c.keep(id);
    await c.sendCommand('reboot');
    expect(utf8.decode(fake.writes.single), 'reboot');
  });

  test('log is capped', () async {
    final small = DeviceController(BleKeeper.instance, maxLogLines: 3);
    addTearDown(small.dispose);
    for (var i = 0; i < 5; i++) {
      fake.controller.add(
        Reconnecting(deviceId: id, attempt: i, timestamp: DateTime(2026)),
      );
    }
    await pumpEventQueue();
    expect(small.state.value.log, hasLength(3));
    expect(small.state.value.log.last, contains('attempt 4'));
  });
}
