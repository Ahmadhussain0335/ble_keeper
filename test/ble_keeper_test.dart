import 'package:flutter_test/flutter_test.dart';
import 'package:ble_keeper/ble_keeper.dart';
import 'package:ble_keeper/ble_keeper_platform_interface.dart';
import 'package:ble_keeper/ble_keeper_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBleKeeperPlatform
    with MockPlatformInterfaceMixin
    implements BleKeeperPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final BleKeeperPlatform initialPlatform = BleKeeperPlatform.instance;

  test('$MethodChannelBleKeeper is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBleKeeper>());
  });

  test('getPlatformVersion', () async {
    BleKeeper bleKeeperPlugin = BleKeeper();
    MockBleKeeperPlatform fakePlatform = MockBleKeeperPlatform();
    BleKeeperPlatform.instance = fakePlatform;

    expect(await bleKeeperPlugin.getPlatformVersion(), '42');
  });
}
