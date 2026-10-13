import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'ble_keeper_method_channel.dart';

abstract class BleKeeperPlatform extends PlatformInterface {
  /// Constructs a BleKeeperPlatform.
  BleKeeperPlatform() : super(token: _token);

  static final Object _token = Object();

  static BleKeeperPlatform _instance = MethodChannelBleKeeper();

  /// The default instance of [BleKeeperPlatform] to use.
  ///
  /// Defaults to [MethodChannelBleKeeper].
  static BleKeeperPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [BleKeeperPlatform] when
  /// they register themselves.
  static set instance(BleKeeperPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
