import 'package:flutter/foundation.dart';

final RegExp _uuid16 = RegExp(r'^[0-9a-f]{4}$');
final RegExp _uuid32 = RegExp(r'^[0-9a-f]{8}$');
final RegExp _uuid128 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final RegExp _uuid128NoDashes = RegExp(r'^[0-9a-f]{32}$');

const String _baseUuidSuffix = '-0000-1000-8000-00805f9b34fb';

/// Normalises a Bluetooth UUID to its lowercase 128-bit form.
///
/// Accepts 16-bit (`180d`), 32-bit (`0000180d`) and 128-bit UUIDs, with or
/// without dashes. Short forms are expanded with the Bluetooth Base UUID.
/// Throws [ArgumentError] for anything else.
String normalizeUuid(String uuid) {
  final value = uuid.trim().toLowerCase();
  if (_uuid16.hasMatch(value)) return '0000$value$_baseUuidSuffix';
  if (_uuid32.hasMatch(value)) return '$value$_baseUuidSuffix';
  if (_uuid128.hasMatch(value)) return value;
  if (_uuid128NoDashes.hasMatch(value)) {
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
  throw ArgumentError.value(uuid, 'uuid', 'Not a valid Bluetooth UUID');
}

/// Identifies a GATT characteristic by its service and characteristic UUIDs.
@immutable
final class CharacteristicRef {
  /// Creates a reference. Both UUIDs are normalised to lowercase 128-bit form
  /// and validated; an invalid UUID throws [ArgumentError].
  CharacteristicRef({
    required String serviceUuid,
    required String characteristicUuid,
  }) : serviceUuid = normalizeUuid(serviceUuid),
       characteristicUuid = normalizeUuid(characteristicUuid);

  /// Lowercase 128-bit service UUID.
  final String serviceUuid;

  /// Lowercase 128-bit characteristic UUID.
  final String characteristicUuid;

  @override
  bool operator ==(Object other) =>
      other is CharacteristicRef &&
      other.serviceUuid == serviceUuid &&
      other.characteristicUuid == characteristicUuid;

  @override
  int get hashCode => Object.hash(serviceUuid, characteristicUuid);

  @override
  String toString() => 'CharacteristicRef($serviceUuid/$characteristicUuid)';
}

/// Android-specific options for [BleKeeper.keepConnected].
@immutable
final class AndroidOptions {
  /// Creates Android options. Unset values use the plugin defaults.
  const AndroidOptions({
    this.notificationTitle,
    this.notificationText,
    this.notificationIcon,
    this.restartOnBoot = true,
  });

  /// Title of the foreground-service notification.
  final String? notificationTitle;

  /// Body text of the foreground-service notification.
  final String? notificationText;

  /// Name of a drawable resource in the host app, for example
  /// `ic_stat_bluetooth`. Must be a monochrome icon. Falls back to the
  /// plugin's own icon when the resource cannot be found.
  final String? notificationIcon;

  /// Restart the connection after the phone reboots or the app is updated.
  final bool restartOnBoot;
}

/// iOS-specific options for [BleKeeper.keepConnected].
@immutable
final class IosOptions {
  /// Creates iOS options.
  const IosOptions({
    this.notifyOnDisconnection = false,
    this.enableAutoReconnect = false,
  });

  /// Ask iOS to show an alert when the peripheral disconnects while the app
  /// is suspended (`CBConnectPeripheralOptionNotifyOnDisconnectionKey`).
  final bool notifyOnDisconnection;

  /// Use the system auto-reconnect on iOS 17 and later
  /// (`CBConnectPeripheralOptionEnableAutoReconnect`). Ignored on earlier
  /// versions. Off by default; the plugin reconnects with a pending connect.
  final bool enableAutoReconnect;
}
