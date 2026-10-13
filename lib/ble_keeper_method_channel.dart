import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ble_keeper_platform_interface.dart';

/// An implementation of [BleKeeperPlatform] that uses method channels.
class MethodChannelBleKeeper extends BleKeeperPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('ble_keeper');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
