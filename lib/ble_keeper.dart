
import 'ble_keeper_platform_interface.dart';

class BleKeeper {
  Future<String?> getPlatformVersion() {
    return BleKeeperPlatform.instance.getPlatformVersion();
  }
}
