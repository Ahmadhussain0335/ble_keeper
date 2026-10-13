import 'package:flutter/foundation.dart';

import 'models.dart';

/// Why a connection ended.
enum DisconnectReason {
  /// The peripheral closed the link.
  peerTerminated,

  /// The link was lost, for example out of range or supervision timeout.
  linkLoss,

  /// The phone closed the link, for example after a GATT error.
  localTerminated,

  /// Bluetooth was turned off.
  bluetoothOff,

  /// [BleKeeper.stop] was called.
  stopped,

  /// A connection attempt failed before the link was established.
  connectFailed,

  /// Any other cause; see [Disconnected.platformCode].
  unknown,
}

/// Something the plugin reports about a kept connection.
///
/// Events are delivered on [BleKeeper.events] while a listener exists, and to
/// the handler registered with [BleKeeper.registerBackgroundHandler] when the
/// UI is gone.
@immutable
sealed class KeeperEvent {
  const KeeperEvent({required this.timestamp});

  /// When the native callback fired.
  final DateTime timestamp;
}

/// The device is connected, services are discovered and every requested
/// characteristic is subscribed.
final class Connected extends KeeperEvent {
  /// Creates a [Connected] event.
  const Connected({required this.deviceId, required super.timestamp});

  /// Android MAC address or iOS peripheral identifier.
  final String deviceId;

  @override
  String toString() => 'Connected($deviceId)';
}

/// The link to the device ended. A reconnect follows unless [reason] is
/// [DisconnectReason.stopped].
final class Disconnected extends KeeperEvent {
  /// Creates a [Disconnected] event.
  const Disconnected({
    required this.deviceId,
    required this.reason,
    this.platformCode,
    required super.timestamp,
  });

  /// Android MAC address or iOS peripheral identifier.
  final String deviceId;

  /// Why the link ended.
  final DisconnectReason reason;

  /// Android GATT status or iOS `CBError` code, when the OS reported one.
  final int? platformCode;

  @override
  String toString() =>
      'Disconnected($deviceId, ${reason.name}'
      '${platformCode == null ? '' : ', code $platformCode'})';
}

/// A reconnect attempt is scheduled or in progress.
final class Reconnecting extends KeeperEvent {
  /// Creates a [Reconnecting] event.
  const Reconnecting({
    required this.deviceId,
    required this.attempt,
    required super.timestamp,
  });

  /// Android MAC address or iOS peripheral identifier.
  final String deviceId;

  /// 1 for the first attempt after a disconnect.
  final int attempt;

  @override
  String toString() => 'Reconnecting($deviceId, attempt $attempt)';
}

/// A notification or indication arrived.
final class Data extends KeeperEvent {
  /// Creates a [Data] event.
  const Data({
    required this.deviceId,
    required this.characteristic,
    required this.bytes,
    required super.timestamp,
  });

  /// Android MAC address or iOS peripheral identifier.
  final String deviceId;

  /// The characteristic that changed.
  final CharacteristicRef characteristic;

  /// The new value.
  final Uint8List bytes;

  @override
  String toString() =>
      'Data($deviceId, ${characteristic.characteristicUuid}, '
      '${bytes.length} bytes)';
}

/// The OS restarted the app (or the plugin's service) after it was killed,
/// and the plugin resumed keeping these devices connected.
///
/// On Android this follows a process kill with the service restarted by the
/// system, a reboot, or an app update. On iOS it follows a relaunch by
/// Core Bluetooth state restoration.
final class RestoredAfterKill extends KeeperEvent {
  /// Creates a [RestoredAfterKill] event.
  const RestoredAfterKill({required this.deviceIds, required super.timestamp});

  /// The devices being kept connected after the restart.
  final List<String> deviceIds;

  @override
  String toString() => 'RestoredAfterKill(${deviceIds.join(', ')})';
}

/// The OS does not allow the plugin to keep the connection right now.
final class Blocked extends KeeperEvent {
  /// Creates a [Blocked] event.
  const Blocked({
    required this.reason,
    this.deviceId,
    required super.timestamp,
  });

  /// What is blocking.
  final BlockedReason reason;

  /// The affected device, or null when every device is affected.
  final String? deviceId;

  @override
  String toString() =>
      'Blocked($reason${deviceId == null ? '' : ', $deviceId'})';
}

/// Why the connection cannot be kept. See [Blocked].
@immutable
sealed class BlockedReason {
  const BlockedReason();
}

/// Bluetooth is off. The plugin reconnects when it is turned on again.
final class BluetoothOff extends BlockedReason {
  /// Creates the reason.
  const BluetoothOff();

  @override
  bool operator ==(Object other) => other is BluetoothOff;

  @override
  int get hashCode => (BluetoothOff).hashCode;

  @override
  String toString() => 'bluetoothOff';
}

/// A runtime permission is missing. The plugin does not request permissions;
/// the app must request [name] and call [BleKeeper.keepConnected] again.
final class PermissionMissing extends BlockedReason {
  /// Creates the reason.
  const PermissionMissing(this.name);

  /// Platform permission name, for example
  /// `android.permission.BLUETOOTH_CONNECT` or `bluetooth` on iOS.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is PermissionMissing && other.name == name;

  @override
  int get hashCode => Object.hash(PermissionMissing, name);

  @override
  String toString() => 'permissionMissing($name)';
}

/// Android refused to start the foreground service, usually because the app
/// was in the background (Android 12 and later). Call
/// [BleKeeper.keepConnected] again while the app is visible.
final class ForegroundStartNotAllowed extends BlockedReason {
  /// Creates the reason.
  const ForegroundStartNotAllowed();

  @override
  bool operator ==(Object other) => other is ForegroundStartNotAllowed;

  @override
  int get hashCode => (ForegroundStartNotAllowed).hashCode;

  @override
  String toString() => 'foregroundStartNotAllowed';
}

/// The user stopped the app (Android force-stop, or iOS swipe-away from the
/// app switcher) while a connection was being kept. Neither OS restarts the
/// app after this. Reported on the next launch.
///
/// On iOS this is a best-effort guess; see the README for false positives.
final class UserForceQuit extends BlockedReason {
  /// Creates the reason.
  const UserForceQuit();

  @override
  bool operator ==(Object other) => other is UserForceQuit;

  @override
  int get hashCode => (UserForceQuit).hashCode;

  @override
  String toString() => 'userForceQuit';
}

/// The app is not set up correctly, for example a missing Info.plist key or a
/// background handler that can no longer be found after an app update.
final class Misconfigured extends BlockedReason {
  /// Creates the reason.
  const Misconfigured(this.detail);

  /// What is wrong and how to fix it.
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is Misconfigured && other.detail == detail;

  @override
  int get hashCode => Object.hash(Misconfigured, detail);

  @override
  String toString() => 'misconfigured($detail)';
}

/// Any other reason.
final class UnknownBlockedReason extends BlockedReason {
  /// Creates the reason.
  const UnknownBlockedReason([this.detail]);

  /// Extra information from the platform, if any.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is UnknownBlockedReason && other.detail == detail;

  @override
  int get hashCode => Object.hash(UnknownBlockedReason, detail);

  @override
  String toString() => 'unknown${detail == null ? '' : '($detail)'}';
}
