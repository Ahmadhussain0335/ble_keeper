import 'dart:async';
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/pigeon_ble_keeper.dart';
import 'src/keeper_event.dart';
import 'src/models.dart';

/// Signature of a background handler. Must be a top-level or static function
/// so it can be found again from a headless engine.
typedef BackgroundHandler = FutureOr<void> Function(KeeperEvent event);

/// Platform interface for ble_keeper.
///
/// The default implementation is [PigeonBleKeeper]. Tests and alternative
/// implementations can replace [instance].
abstract class BleKeeperPlatform extends PlatformInterface {
  /// Constructs a BleKeeperPlatform.
  BleKeeperPlatform() : super(token: _token);

  static final Object _token = Object();

  static BleKeeperPlatform _instance = PigeonBleKeeper();

  /// The current implementation. Defaults to [PigeonBleKeeper].
  static BleKeeperPlatform get instance => _instance;

  /// Replaces the implementation. The new instance must extend this class.
  static set instance(BleKeeperPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// See [BleKeeper.keepConnected].
  Future<void> keepConnected({
    required String deviceId,
    required List<CharacteristicRef> subscribe,
    AndroidOptions? android,
    IosOptions? ios,
  }) {
    throw UnimplementedError('keepConnected() has not been implemented.');
  }

  /// See [BleKeeper.stop].
  Future<void> stop(String deviceId) {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// See [BleKeeper.write].
  Future<void> write(
    String deviceId,
    CharacteristicRef characteristic,
    Uint8List value, {
    bool withResponse = true,
  }) {
    throw UnimplementedError('write() has not been implemented.');
  }

  /// See [BleKeeper.read].
  Future<Uint8List> read(String deviceId, CharacteristicRef characteristic) {
    throw UnimplementedError('read() has not been implemented.');
  }

  /// See [BleKeeper.events].
  Stream<KeeperEvent> get events {
    throw UnimplementedError('events has not been implemented.');
  }

  /// See [BleKeeper.registerBackgroundHandler].
  Future<void> registerBackgroundHandler(BackgroundHandler handler) {
    throw UnimplementedError(
      'registerBackgroundHandler() has not been implemented.',
    );
  }

  /// See [BleKeeper.exportLog].
  Future<String> exportLog() {
    throw UnimplementedError('exportLog() has not been implemented.');
  }

  /// See [BleKeeper.clearLog].
  Future<void> clearLog() {
    throw UnimplementedError('clearLog() has not been implemented.');
  }

  /// See [BleKeeper.activeDeviceIds].
  Future<List<String>> activeDeviceIds() {
    throw UnimplementedError('activeDeviceIds() has not been implemented.');
  }
}
