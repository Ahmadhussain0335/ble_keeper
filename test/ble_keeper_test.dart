import 'dart:typed_data';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:ble_keeper/ble_keeper_method_channel.dart';
import 'package:ble_keeper/ble_keeper_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _MockPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements BleKeeperPlatform {}

void _handler(KeeperEvent event) {}

void main() {
  final initialPlatform = BleKeeperPlatform.instance;
  late _MockPlatform platform;
  final char = CharacteristicRef(
    serviceUuid: '12345678-1234-1234-1234-1234567890ab',
    characteristicUuid: '12345678-1234-1234-1234-1234567890ac',
  );

  setUpAll(() {
    registerFallbackValue(char);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    platform = _MockPlatform();
    BleKeeperPlatform.instance = platform;
  });

  test('$PigeonBleKeeper is the default instance', () {
    expect(initialPlatform, isA<PigeonBleKeeper>());
  });

  test('keepConnected forwards all arguments', () async {
    when(
      () => platform.keepConnected(
        deviceId: any(named: 'deviceId'),
        subscribe: any(named: 'subscribe'),
        android: any(named: 'android'),
        ios: any(named: 'ios'),
      ),
    ).thenAnswer((_) async {});
    const android = AndroidOptions(notificationTitle: 't');
    const ios = IosOptions(notifyOnDisconnection: true);

    await BleKeeper.instance.keepConnected(
      deviceId: 'id',
      subscribe: [char],
      android: android,
      ios: ios,
    );

    verify(
      () => platform.keepConnected(
        deviceId: 'id',
        subscribe: [char],
        android: android,
        ios: ios,
      ),
    ).called(1);
  });

  test('stop forwards', () async {
    when(() => platform.stop(any())).thenAnswer((_) async {});
    await BleKeeper.instance.stop('id');
    verify(() => platform.stop('id')).called(1);
  });

  test('write forwards withResponse', () async {
    when(
      () => platform.write(
        any(),
        any(),
        any(),
        withResponse: any(named: 'withResponse'),
      ),
    ).thenAnswer((_) async {});
    final value = Uint8List.fromList([1]);

    await BleKeeper.instance.write('id', char, value, withResponse: false);

    verify(() => platform.write('id', char, value, withResponse: false))
        .called(1);
  });

  test('read returns the platform value', () async {
    when(() => platform.read(any(), any()))
        .thenAnswer((_) async => Uint8List.fromList([7]));
    expect(await BleKeeper.instance.read('id', char), [7]);
  });

  test('events is the platform stream', () async {
    final event = Connected(deviceId: 'id', timestamp: DateTime(2026));
    when(() => platform.events).thenAnswer((_) => Stream.value(event));
    expect(await BleKeeper.instance.events.first, same(event));
  });

  test('registerBackgroundHandler forwards', () async {
    when(() => platform.registerBackgroundHandler(any()))
        .thenAnswer((_) async {});
    await BleKeeper.instance.registerBackgroundHandler(_handler);
    verify(() => platform.registerBackgroundHandler(_handler)).called(1);
  });

  test('log and device queries forward', () async {
    when(() => platform.exportLog()).thenAnswer((_) async => '/tmp/log.txt');
    when(() => platform.clearLog()).thenAnswer((_) async {});
    when(() => platform.activeDeviceIds()).thenAnswer((_) async => ['id']);

    expect(await BleKeeper.instance.exportLog(), '/tmp/log.txt');
    await BleKeeper.instance.clearLog();
    expect(await BleKeeper.instance.activeDeviceIds(), ['id']);
    verify(() => platform.clearLog()).called(1);
  });
}
