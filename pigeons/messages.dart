// Pigeon contract between Dart and the native ble_keeper implementations.
//
// Regenerate with:
//   dart run pigeon --input pigeons/messages.dart
// then run `dart format .`. The generated files are committed.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/ahmadhussain/ble_keeper/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.ahmadhussain.ble_keeper',
      errorClassName: 'BleKeeperFlutterError',
    ),
    swiftOut: 'ios/ble_keeper/Sources/ble_keeper/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'BleKeeperPigeonError'),
    dartPackageName: 'ble_keeper',
  ),
)
enum PEventType {
  connected,
  disconnected,
  reconnecting,
  data,
  restoredAfterKill,
  blocked,
}

enum PBlockedReason {
  bluetoothOff,
  permissionMissing,
  foregroundStartNotAllowed,
  userForceQuit,
  misconfigured,
  unknown,
}

enum PDisconnectReason {
  peerTerminated,
  linkLoss,
  localTerminated,
  bluetoothOff,
  stopped,
  connectFailed,
  unknown,
}

class PCharacteristicRef {
  PCharacteristicRef({
    required this.serviceUuid,
    required this.characteristicUuid,
  });

  String serviceUuid;
  String characteristicUuid;
}

class PAndroidOptions {
  String? notificationTitle;
  String? notificationText;
  String? notificationIcon;
  bool? restartOnBoot;
}

class PIosOptions {
  bool? notifyOnDisconnection;
  bool? enableAutoReconnect;
}

class PKeepRequest {
  PKeepRequest({required this.deviceId, required this.subscribe});

  String deviceId;
  List<PCharacteristicRef> subscribe;
  PAndroidOptions? android;
  PIosOptions? ios;
}

/// Flat event envelope. Which optional fields are set depends on [type];
/// `lib/src/event_mapper.dart` validates and converts it to a KeeperEvent.
class PEvent {
  PEvent({required this.seq, required this.timestampMs, required this.type});

  /// Monotonic per native process; Dart drops duplicates.
  int seq;

  /// Milliseconds since the Unix epoch, taken when the native callback fired.
  int timestampMs;
  PEventType type;
  String? deviceId;
  PDisconnectReason? disconnectReason;

  /// Android GATT status or iOS CBError code, when one exists.
  int? platformCode;
  int? attempt;
  PCharacteristicRef? characteristic;
  Uint8List? value;
  PBlockedReason? blockedReason;

  /// Permission name for permissionMissing, explanation for misconfigured.
  String? detail;
  List<String>? deviceIds;
}

@HostApi()
abstract class BleKeeperHostApi {
  @async
  void keepConnected(PKeepRequest request);

  @async
  void stop(String deviceId);

  @async
  void write(
    String deviceId,
    PCharacteristicRef characteristic,
    Uint8List value,
    bool withResponse,
  );

  @async
  Uint8List read(String deviceId, PCharacteristicRef characteristic);

  /// Stores the raw callback handles of the background dispatcher and the
  /// user's handler so a headless engine can be started later.
  void registerBackgroundHandler(int dispatcherHandle, int handlerHandle);

  /// Handle of the user's background handler, read by the dispatcher.
  int? backgroundHandlerHandle();

  @async
  String exportLog();

  @async
  void clearLog();

  /// Dart in this engine is ready to receive events; native flushes buffered
  /// events to it. [isBackground] is true for the headless dispatcher.
  void attach(bool isBackground);

  void detach();

  List<String> activeDeviceIds();
}

@FlutterApi()
abstract class BleKeeperEventApi {
  /// The reply acknowledges the batch; native drops it from its buffer only
  /// after this returns.
  @async
  void onEvents(List<PEvent> events);
}
