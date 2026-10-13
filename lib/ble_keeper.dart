/// Keeps a BLE peripheral connected in the background, after the app is
/// killed by the OS, and after a reboot, on Android and iOS.
library;

import 'dart:typed_data';

import 'ble_keeper_platform_interface.dart';
import 'src/keeper_event.dart';
import 'src/models.dart';

export 'ble_keeper_platform_interface.dart' show BackgroundHandler;
export 'src/exceptions.dart' show BleKeeperException;
export 'src/keeper_event.dart';
export 'src/models.dart'
    show AndroidOptions, CharacteristicRef, IosOptions, normalizeUuid;

/// Entry point of the plugin. Use [BleKeeper.instance].
///
/// The connection is owned by native code (an Android foreground service, a
/// restorable iOS `CBCentralManager`), so it survives the Flutter UI going
/// away. Dart only sends commands and receives events.
class BleKeeper {
  BleKeeper._();

  /// The shared instance.
  static final BleKeeper instance = BleKeeper._();

  BleKeeperPlatform get _platform => BleKeeperPlatform.instance;

  /// Starts keeping [deviceId] connected and subscribes to [subscribe].
  ///
  /// [deviceId] is the Bluetooth MAC address on Android (for example
  /// `24:6F:28:AA:BB:CC`) and the `CBPeripheral.identifier` UUID on iOS.
  ///
  /// The request is persisted: the plugin keeps reconnecting until [stop] is
  /// called, including after the OS kills and restarts the app. Calling it
  /// again for the same device replaces the subscriptions and options.
  ///
  /// The returned future completes once the request is accepted, not when the
  /// device is connected; watch [events] for [Connected]. When the OS does not
  /// allow the connection (permission missing, Bluetooth off, background start
  /// restriction) a [Blocked] event is emitted instead of an error.
  ///
  /// On Android this must be called while the app is visible, because
  /// Android 12 and later do not allow starting a foreground service from the
  /// background.
  ///
  /// Throws [ArgumentError] for an empty [deviceId] or [subscribe] list and
  /// [BleKeeperException] when the platform rejects the request.
  Future<void> keepConnected({
    required String deviceId,
    required List<CharacteristicRef> subscribe,
    AndroidOptions? android,
    IosOptions? ios,
  }) => _platform.keepConnected(
    deviceId: deviceId,
    subscribe: subscribe,
    android: android,
    ios: ios,
  );

  /// Stops keeping [deviceId] connected, disconnects it and forgets the
  /// persisted request. On Android the foreground service stops when no
  /// devices are left.
  Future<void> stop(String deviceId) => _platform.stop(deviceId);

  /// Writes [value] to [characteristic]. Fails with code `not_connected` when
  /// the device is not currently connected; writes are not queued across
  /// disconnects.
  Future<void> write(
    String deviceId,
    CharacteristicRef characteristic,
    Uint8List value, {
    bool withResponse = true,
  }) => _platform.write(
    deviceId,
    characteristic,
    value,
    withResponse: withResponse,
  );

  /// Reads [characteristic]. Fails with code `not_connected` when the device
  /// is not currently connected.
  Future<Uint8List> read(String deviceId, CharacteristicRef characteristic) =>
      _platform.read(deviceId, characteristic);

  /// Events for all kept devices.
  ///
  /// Native code buffers events while nobody listens and delivers them when
  /// the first listener subscribes. While a listener exists, events are not
  /// sent to the background handler.
  Stream<KeeperEvent> get events => _platform.events;

  /// Registers [handler] to receive events when no UI is running, for example
  /// after the OS restarted the app in the background.
  ///
  /// [handler] must be a top-level or static function annotated with
  /// `@pragma('vm:entry-point')`. It runs in a separate isolate without UI;
  /// it cannot share memory with the UI isolate. Call this on every app start,
  /// because callback handles can change when the app is updated.
  ///
  /// If [handler] returns a future, the plugin waits for it before handling
  /// the next batch. Keep the work short: iOS gives a background app only a
  /// few seconds per Bluetooth event.
  ///
  /// Throws [ArgumentError] when [handler] is a closure or instance method.
  Future<void> registerBackgroundHandler(BackgroundHandler handler) =>
      _platform.registerBackgroundHandler(handler);

  /// Writes the event log to a single file and returns its path, for sharing
  /// or attaching to a bug report.
  ///
  /// The log holds at most about 2 MB (two rotating 1 MB files), one event
  /// per line with an ISO-8601 UTC timestamp. In release builds device IDs
  /// are pseudonymised and payloads are logged by length only.
  Future<String> exportLog() => _platform.exportLog();

  /// Deletes the event log, including exported copies.
  Future<void> clearLog() => _platform.clearLog();

  /// Devices the plugin is currently keeping connected (persisted requests).
  Future<List<String>> activeDeviceIds() => _platform.activeDeviceIds();
}
