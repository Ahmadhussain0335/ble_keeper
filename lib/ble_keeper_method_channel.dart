import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'ble_keeper_platform_interface.dart';
import 'src/background_dispatcher.dart';
import 'src/event_mapper.dart';
import 'src/exceptions.dart';
import 'src/keeper_event.dart';
import 'src/messages.g.dart';
import 'src/models.dart';

/// Looks up the callback handle of a top-level or static function.
typedef CallbackHandleLookup = CallbackHandle? Function(Function callback);

/// [BleKeeperPlatform] implementation that talks to native code through the
/// Pigeon-generated channels.
class PigeonBleKeeper extends BleKeeperPlatform implements BleKeeperEventApi {
  /// Creates the implementation. Parameters exist for tests.
  PigeonBleKeeper({
    @visibleForTesting BleKeeperHostApi? hostApi,
    @visibleForTesting CallbackHandleLookup? callbackHandleOf,
    @visibleForTesting void Function(BleKeeperEventApi? api)? setUpEventApi,
  }) : _host = hostApi ?? BleKeeperHostApi(),
       _handleOf = callbackHandleOf ?? PluginUtilities.getCallbackHandle,
       _setUpEventApi = setUpEventApi ?? BleKeeperEventApi.setUp {
    _controller = StreamController<KeeperEvent>.broadcast(
      onListen: _attach,
      onCancel: _detach,
    );
  }

  /// Upper bound for `subscribe` in keepConnected.
  static const int maxSubscriptions = 32;

  /// Upper bound for Android notification option strings.
  static const int maxOptionLength = 256;

  final BleKeeperHostApi _host;
  final CallbackHandleLookup _handleOf;
  final void Function(BleKeeperEventApi? api) _setUpEventApi;
  late final StreamController<KeeperEvent> _controller;
  int _lastSeq = -1;

  @override
  Stream<KeeperEvent> get events => _controller.stream;

  @override
  Future<void> keepConnected({
    required String deviceId,
    required List<CharacteristicRef> subscribe,
    AndroidOptions? android,
    IosOptions? ios,
  }) {
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'must not be empty');
    }
    if (subscribe.isEmpty) {
      throw ArgumentError.value(subscribe, 'subscribe', 'must not be empty');
    }
    // Requests are persisted and restored natively; bound their size.
    if (subscribe.length > maxSubscriptions) {
      throw ArgumentError.value(
        subscribe.length,
        'subscribe',
        'at most $maxSubscriptions characteristics',
      );
    }
    for (final (name, text) in [
      ('notificationTitle', android?.notificationTitle),
      ('notificationText', android?.notificationText),
      ('notificationIcon', android?.notificationIcon),
    ]) {
      if (text != null && text.length > maxOptionLength) {
        throw ArgumentError.value(
          text,
          'android.$name',
          'at most $maxOptionLength characters',
        );
      }
    }
    final request = PKeepRequest(
      deviceId: deviceId.trim(),
      subscribe: subscribe.map(toWire).toList(),
      android: android == null
          ? null
          : PAndroidOptions(
              notificationTitle: android.notificationTitle,
              notificationText: android.notificationText,
              notificationIcon: android.notificationIcon,
              restartOnBoot: android.restartOnBoot,
            ),
      ios: ios == null
          ? null
          : PIosOptions(
              notifyOnDisconnection: ios.notifyOnDisconnection,
              enableAutoReconnect: ios.enableAutoReconnect,
            ),
    );
    return guardPlatform(() => _host.keepConnected(request));
  }

  @override
  Future<void> stop(String deviceId) =>
      guardPlatform(() => _host.stop(deviceId.trim()));

  @override
  Future<void> write(
    String deviceId,
    CharacteristicRef characteristic,
    Uint8List value, {
    bool withResponse = true,
  }) => guardPlatform(
    () => _host.write(
      deviceId.trim(),
      toWire(characteristic),
      value,
      withResponse,
    ),
  );

  @override
  Future<Uint8List> read(String deviceId, CharacteristicRef characteristic) =>
      guardPlatform(() => _host.read(deviceId.trim(), toWire(characteristic)));

  @override
  Future<void> registerBackgroundHandler(BackgroundHandler handler) {
    final handlerHandle = _handleOf(handler);
    if (handlerHandle == null) {
      throw ArgumentError.value(
        handler,
        'handler',
        'must be a top-level or static function (closures and instance '
            'methods cannot be found from a background engine)',
      );
    }
    final dispatcherHandle = _handleOf(bleKeeperBackgroundMain);
    if (dispatcherHandle == null) {
      throw StateError('ble_keeper background dispatcher has no handle');
    }
    return guardPlatform(
      () => _host.registerBackgroundHandler(
        dispatcherHandle.toRawHandle(),
        handlerHandle.toRawHandle(),
      ),
    );
  }

  @override
  Future<String> exportLog() => guardPlatform(_host.exportLog);

  @override
  Future<void> clearLog() => guardPlatform(_host.clearLog);

  @override
  Future<List<String>> activeDeviceIds() =>
      guardPlatform(_host.activeDeviceIds);

  /// Receives event batches from native code. Not for app use.
  @override
  @visibleForTesting
  Future<void> onEvents(List<PEvent> events) async {
    for (final e in events) {
      if (e.seq <= _lastSeq) continue;
      _lastSeq = e.seq;
      try {
        _controller.add(mapEvent(e));
      } on MalformedEventException catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'ble_keeper',
            context: ErrorDescription('while decoding a native event'),
          ),
        );
      }
    }
  }

  Future<void> _attach() async {
    _setUpEventApi(this);
    try {
      await guardPlatform(() => _host.attach(false));
    } catch (error, stack) {
      _controller.addError(error, stack);
    }
  }

  Future<void> _detach() async {
    try {
      await guardPlatform(_host.detach);
    } catch (error, stack) {
      _controller.addError(error, stack);
    }
    _setUpEventApi(null);
  }
}
