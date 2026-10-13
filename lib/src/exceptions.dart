import 'package:flutter/services.dart';

/// Error returned by a [BleKeeper] call.
///
/// [code] is one of: `invalid_argument`, `not_connected`, `unknown_device`,
/// `characteristic_not_found`, `payload_too_large`, `write_type_unsupported`,
/// `gatt_error`, `timeout`, `permission_missing`, `bluetooth_off`,
/// `misconfigured`, `unimplemented`, or `channel-error` when the native side
/// is not reachable.
class BleKeeperException implements Exception {
  /// Creates the exception.
  const BleKeeperException(this.code, [this.message]);

  /// Machine-readable error code.
  final String code;

  /// Human-readable explanation from the platform.
  final String? message;

  @override
  String toString() =>
      'BleKeeperException($code${message == null ? '' : ': $message'})';
}

/// Runs [call] and converts platform errors to [BleKeeperException].
Future<T> guardPlatform<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (e) {
    throw BleKeeperException(e.code, e.message);
  }
}
