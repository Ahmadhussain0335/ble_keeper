import 'dart:typed_data';

import 'keeper_event.dart';
import 'messages.g.dart';
import 'models.dart';

/// Thrown when a native event envelope is missing a field its type requires.
class MalformedEventException implements Exception {
  /// Creates the exception.
  MalformedEventException(this.message);

  /// What is wrong with the envelope.
  final String message;

  @override
  String toString() => 'MalformedEventException: $message';
}

/// Converts a wire envelope to the public [KeeperEvent] type.
///
/// Throws [MalformedEventException] when a field required by the event type
/// is missing, so a mismatched native side fails loudly instead of producing
/// half-filled events.
KeeperEvent mapEvent(PEvent e) {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(e.timestampMs);
  switch (e.type) {
    case PEventType.connected:
      return Connected(deviceId: _device(e), timestamp: timestamp);
    case PEventType.disconnected:
      return Disconnected(
        deviceId: _device(e),
        reason: _disconnectReason(e.disconnectReason),
        platformCode: e.platformCode,
        timestamp: timestamp,
      );
    case PEventType.reconnecting:
      final attempt = e.attempt;
      if (attempt == null) {
        throw MalformedEventException('reconnecting without attempt');
      }
      return Reconnecting(
        deviceId: _device(e),
        attempt: attempt,
        timestamp: timestamp,
      );
    case PEventType.data:
      final c = e.characteristic;
      if (c == null) {
        throw MalformedEventException('data without characteristic');
      }
      return Data(
        deviceId: _device(e),
        characteristic: CharacteristicRef(
          serviceUuid: c.serviceUuid,
          characteristicUuid: c.characteristicUuid,
        ),
        bytes: e.value ?? Uint8List(0),
        timestamp: timestamp,
      );
    case PEventType.restoredAfterKill:
      return RestoredAfterKill(
        deviceIds: List.unmodifiable(e.deviceIds ?? const <String>[]),
        timestamp: timestamp,
      );
    case PEventType.blocked:
      return Blocked(
        reason: _blockedReason(e),
        deviceId: e.deviceId,
        timestamp: timestamp,
      );
  }
}

/// Converts a public reference to its wire form.
PCharacteristicRef toWire(CharacteristicRef c) => PCharacteristicRef(
  serviceUuid: c.serviceUuid,
  characteristicUuid: c.characteristicUuid,
);

String _device(PEvent e) {
  final id = e.deviceId;
  if (id == null || id.isEmpty) {
    throw MalformedEventException('${e.type.name} without deviceId');
  }
  return id;
}

DisconnectReason _disconnectReason(PDisconnectReason? r) => switch (r) {
  PDisconnectReason.peerTerminated => DisconnectReason.peerTerminated,
  PDisconnectReason.linkLoss => DisconnectReason.linkLoss,
  PDisconnectReason.localTerminated => DisconnectReason.localTerminated,
  PDisconnectReason.bluetoothOff => DisconnectReason.bluetoothOff,
  PDisconnectReason.stopped => DisconnectReason.stopped,
  PDisconnectReason.connectFailed => DisconnectReason.connectFailed,
  PDisconnectReason.unknown || null => DisconnectReason.unknown,
};

BlockedReason _blockedReason(PEvent e) => switch (e.blockedReason) {
  PBlockedReason.bluetoothOff => const BluetoothOff(),
  PBlockedReason.permissionMissing => PermissionMissing(e.detail ?? 'unknown'),
  PBlockedReason.foregroundStartNotAllowed => const ForegroundStartNotAllowed(),
  PBlockedReason.userForceQuit => const UserForceQuit(),
  PBlockedReason.misconfigured => Misconfigured(e.detail ?? 'unknown'),
  PBlockedReason.unknown || null => UnknownBlockedReason(e.detail),
};
