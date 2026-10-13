import 'package:ble_keeper/ble_keeper.dart';

String _two(int v) => v.toString().padLeft(2, '0');
String _three(int v) => v.toString().padLeft(3, '0');

/// `HH:mm:ss.SSS` in local time.
String formatTime(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${_three(t.millisecond)}';

/// One line for the example's event log view.
String formatEvent(KeeperEvent e) {
  final body = switch (e) {
    Connected(:final deviceId) => 'connected $deviceId',
    Disconnected(:final deviceId, :final reason, :final platformCode) =>
      'disconnected $deviceId: ${reason.name}'
          '${platformCode == null ? '' : ' (code $platformCode)'}',
    Reconnecting(:final deviceId, :final attempt) =>
      'reconnecting $deviceId, attempt $attempt',
    Data(:final deviceId, :final bytes) =>
      'data $deviceId: ${bytes.length} bytes',
    RestoredAfterKill(:final deviceIds) =>
      'restored after kill: ${deviceIds.join(', ')}',
    Blocked(:final reason, :final deviceId) =>
      'BLOCKED ${_reason(reason)}${deviceId == null ? '' : ' ($deviceId)'}',
  };
  return '${formatTime(e.timestamp)}  $body';
}

String _reason(BlockedReason r) => switch (r) {
  BluetoothOff() => 'Bluetooth is off',
  PermissionMissing(:final name) => 'permission missing: $name',
  ForegroundStartNotAllowed() =>
    'Android did not allow starting the service from the background',
  UserForceQuit() => 'app was force-quit by the user',
  Misconfigured(:final detail) => 'misconfigured: $detail',
  UnknownBlockedReason(:final detail) =>
    'unknown${detail == null ? '' : ': $detail'}',
};
