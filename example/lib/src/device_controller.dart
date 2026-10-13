import 'dart:async';
import 'dart:convert';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:flutter/foundation.dart';

import 'event_format.dart';
import 'gap_detector.dart';

/// ESP32 test device characteristics (see tools/esp32_test_device).
const testServiceUuid = '12345678-1234-1234-1234-1234567890ab';
final counterChar = CharacteristicRef(
  serviceUuid: testServiceUuid,
  characteristicUuid: '12345678-1234-1234-1234-1234567890ac',
);
final commandChar = CharacteristicRef(
  serviceUuid: testServiceUuid,
  characteristicUuid: '12345678-1234-1234-1234-1234567890ad',
);

enum LinkState { idle, connecting, connected, reconnecting, blocked }

/// Immutable snapshot rendered by the UI.
@immutable
class DeviceState {
  const DeviceState({
    this.deviceId,
    this.link = LinkState.idle,
    this.counter,
    this.received = 0,
    this.missed = 0,
    this.resets = 0,
    this.lastProblem,
    this.log = const [],
  });

  final String? deviceId;
  final LinkState link;
  final int? counter;
  final int received;
  final int missed;
  final int resets;
  final String? lastProblem;
  final List<String> log;

  DeviceState copyWith({
    String? deviceId,
    LinkState? link,
    int? counter,
    int? received,
    int? missed,
    int? resets,
    String? lastProblem,
    List<String>? log,
  }) => DeviceState(
    deviceId: deviceId ?? this.deviceId,
    link: link ?? this.link,
    counter: counter ?? this.counter,
    received: received ?? this.received,
    missed: missed ?? this.missed,
    resets: resets ?? this.resets,
    lastProblem: lastProblem ?? this.lastProblem,
    log: log ?? this.log,
  );
}

/// Turns plugin events into [DeviceState] and sends commands.
class DeviceController {
  DeviceController(this._keeper, {this.maxLogLines = 500}) {
    _sub = _keeper.events.listen(_onEvent, onError: _onError);
  }

  final BleKeeper _keeper;
  final int maxLogLines;
  final GapDetector _gaps = GapDetector();
  final ValueNotifier<DeviceState> state = ValueNotifier(const DeviceState());
  late final StreamSubscription<KeeperEvent> _sub;

  Future<void> keep(String deviceId) async {
    final id = deviceId.trim();
    _gaps.reset();
    state.value = DeviceState(
      deviceId: id,
      link: LinkState.connecting,
      log: state.value.log,
    );
    try {
      await _keeper.keepConnected(
        deviceId: id,
        subscribe: [counterChar],
        android: const AndroidOptions(
          notificationTitle: 'BLE test device',
          notificationText: 'Keeping the test device connected',
        ),
      );
    } on Object catch (e) {
      _problem('keepConnected failed: $e');
    }
  }

  Future<void> stop() async {
    final id = state.value.deviceId;
    if (id == null) return;
    try {
      await _keeper.stop(id);
      state.value = state.value.copyWith(link: LinkState.idle);
    } on Object catch (e) {
      _problem('stop failed: $e');
    }
  }

  /// Sends `disconnect`, `reboot` or `silent` to the test device.
  Future<void> sendCommand(String command) async {
    final id = state.value.deviceId;
    if (id == null) return;
    try {
      await _keeper.write(
        id,
        commandChar,
        Uint8List.fromList(utf8.encode(command)),
      );
      _append('sent "$command"');
    } on Object catch (e) {
      _problem('write "$command" failed: $e');
    }
  }

  void _onEvent(KeeperEvent e) {
    final s = state.value;
    switch (e) {
      case Data(:final bytes):
        final value = parseCounter(bytes);
        if (value == null) return;
        final resetsBefore = _gaps.resets;
        final gap = _gaps.add(value);
        if (gap > 0) _append('${formatTime(e.timestamp)}  gap: missed $gap');
        if (_gaps.resets > resetsBefore) {
          _append(
            '${formatTime(e.timestamp)}  counter reset (device rebooted)',
          );
        }
        state.value = state.value.copyWith(
          counter: value,
          received: _gaps.received,
          missed: _gaps.missed,
          resets: _gaps.resets,
          link: LinkState.connected,
        );
        return;
      case Connected():
        state.value = s.copyWith(link: LinkState.connected);
      case Disconnected(:final reason) when reason == DisconnectReason.stopped:
        state.value = s.copyWith(link: LinkState.idle);
      case Disconnected() || Reconnecting():
        state.value = s.copyWith(link: LinkState.reconnecting);
      case Blocked():
        state.value = s.copyWith(
          link: LinkState.blocked,
          lastProblem: formatEvent(e),
        );
      case RestoredAfterKill():
        break;
    }
    _append(formatEvent(e));
  }

  void _onError(Object error) => _problem('event stream error: $error');

  void _problem(String text) {
    state.value = state.value.copyWith(lastProblem: text);
    _append(text);
  }

  void _append(String line) {
    final log = [...state.value.log, line];
    final trimmed = log.length > maxLogLines
        ? log.sublist(log.length - maxLogLines)
        : log;
    state.value = state.value.copyWith(log: List.unmodifiable(trimmed));
  }

  Future<void> dispose() async {
    await _sub.cancel();
    state.dispose();
  }
}
