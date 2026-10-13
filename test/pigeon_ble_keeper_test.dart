import 'dart:async';
import 'dart:ui';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:ble_keeper/src/pigeon_ble_keeper.dart';
import 'package:ble_keeper/src/messages.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockHostApi extends Mock implements BleKeeperHostApi {}

void _topLevelHandler(KeeperEvent event) {}

const _device = 'AA:BB:CC:DD:EE:FF';

PEvent _connected(int seq) => PEvent(
  seq: seq,
  timestampMs: 1760000000000,
  type: PEventType.connected,
  deviceId: _device,
);

void main() {
  late _MockHostApi host;
  late PigeonBleKeeper platform;
  late List<BleKeeperEventApi?> eventApiSetUps;
  final handles = <Function, CallbackHandle>{};
  final char = CharacteristicRef(
    serviceUuid: '180d',
    characteristicUuid: '2a37',
  );

  setUpAll(() {
    registerFallbackValue(PKeepRequest(deviceId: '', subscribe: []));
    registerFallbackValue(
      PCharacteristicRef(serviceUuid: '', characteristicUuid: ''),
    );
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    host = _MockHostApi();
    eventApiSetUps = [];
    handles.clear();
    platform = PigeonBleKeeper(
      hostApi: host,
      callbackHandleOf: (f) => handles[f],
      setUpEventApi: eventApiSetUps.add,
    );
    when(() => host.attach(any())).thenAnswer((_) async {});
    when(() => host.detach()).thenAnswer((_) async {});
  });

  group('keepConnected', () {
    test('sends a request with normalised UUIDs and options', () async {
      when(() => host.keepConnected(any())).thenAnswer((_) async {});

      await platform.keepConnected(
        deviceId: ' $_device ',
        subscribe: [char],
        android: const AndroidOptions(
          notificationTitle: 'title',
          notificationText: 'text',
          notificationIcon: 'ic_stat',
          restartOnBoot: false,
        ),
        ios: const IosOptions(notifyOnDisconnection: true),
      );

      final request =
          verify(() => host.keepConnected(captureAny())).captured.single
              as PKeepRequest;
      expect(request.deviceId, _device);
      expect(
        request.subscribe.single.serviceUuid,
        '0000180d-0000-1000-8000-00805f9b34fb',
      );
      expect(request.android?.notificationTitle, 'title');
      expect(request.android?.notificationText, 'text');
      expect(request.android?.notificationIcon, 'ic_stat');
      expect(request.android?.restartOnBoot, isFalse);
      expect(request.ios?.notifyOnDisconnection, isTrue);
      expect(request.ios?.enableAutoReconnect, isFalse);
    });

    test('omits options that were not given', () async {
      when(() => host.keepConnected(any())).thenAnswer((_) async {});
      await platform.keepConnected(deviceId: _device, subscribe: [char]);
      final request =
          verify(() => host.keepConnected(captureAny())).captured.single
              as PKeepRequest;
      expect(request.android, isNull);
      expect(request.ios, isNull);
    });

    test('rejects an empty device id', () {
      expect(
        () => platform.keepConnected(deviceId: ' ', subscribe: [char]),
        throwsArgumentError,
      );
    });

    test('rejects an empty subscribe list', () {
      expect(
        () => platform.keepConnected(deviceId: _device, subscribe: []),
        throwsArgumentError,
      );
    });

    test('rejects too many subscriptions', () {
      expect(
        () => platform.keepConnected(
          deviceId: _device,
          subscribe: List.filled(PigeonBleKeeper.maxSubscriptions + 1, char),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an over-long notification option', () {
      expect(
        () => platform.keepConnected(
          deviceId: _device,
          subscribe: [char],
          android: AndroidOptions(
            notificationText: 'x' * (PigeonBleKeeper.maxOptionLength + 1),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('converts PlatformException to BleKeeperException', () async {
      when(() => host.keepConnected(any())).thenThrow(
        PlatformException(code: 'invalid_argument', message: 'bad MAC'),
      );
      await expectLater(
        platform.keepConnected(deviceId: _device, subscribe: [char]),
        throwsA(
          isA<BleKeeperException>()
              .having((e) => e.code, 'code', 'invalid_argument')
              .having((e) => e.message, 'message', 'bad MAC'),
        ),
      );
    });
  });

  test('write and read forward to the host', () async {
    when(() => host.write(any(), any(), any(), any())).thenAnswer((_) async {});
    when(
      () => host.read(any(), any()),
    ).thenAnswer((_) async => Uint8List.fromList([5]));

    await platform.write(_device, char, Uint8List.fromList([1, 2]));
    expect(await platform.read(_device, char), [5]);

    final captured = verify(
      () => host.write(_device, captureAny(), any(), true),
    ).captured;
    expect(
      (captured.single as PCharacteristicRef).characteristicUuid,
      '00002a37-0000-1000-8000-00805f9b34fb',
    );
  });

  test('stop, exportLog, clearLog and activeDeviceIds forward', () async {
    when(() => host.stop(any())).thenAnswer((_) async {});
    when(() => host.exportLog()).thenAnswer((_) async => '/x/log.txt');
    when(() => host.clearLog()).thenAnswer((_) async {});
    when(() => host.activeDeviceIds()).thenAnswer((_) async => [_device]);

    await platform.stop(_device);
    expect(await platform.exportLog(), '/x/log.txt');
    await platform.clearLog();
    expect(await platform.activeDeviceIds(), [_device]);
    verify(() => host.stop(_device)).called(1);
  });

  group('registerBackgroundHandler', () {
    test('stores both raw handles', () async {
      when(
        () => host.registerBackgroundHandler(any(), any()),
      ).thenAnswer((_) async {});
      handles[_topLevelHandler] = CallbackHandle.fromRawHandle(11);
      // Any non-null handle for the dispatcher works in this test.
      final realLookup = PigeonBleKeeper(
        hostApi: host,
        callbackHandleOf: (f) => handles[f] ?? CallbackHandle.fromRawHandle(22),
      );

      await realLookup.registerBackgroundHandler(_topLevelHandler);

      verify(() => host.registerBackgroundHandler(22, 11)).called(1);
    });

    test('rejects a closure', () {
      expect(
        () => platform.registerBackgroundHandler((_) {}),
        throwsArgumentError,
      );
      verifyNever(() => host.registerBackgroundHandler(any(), any()));
    });
  });

  group('events', () {
    test('attaches on first listen and detaches on last cancel', () async {
      final sub1 = platform.events.listen((_) {});
      final sub2 = platform.events.listen((_) {});
      await pumpEventQueue();

      verify(() => host.attach(false)).called(1);
      expect(eventApiSetUps, [platform]);

      await sub1.cancel();
      verifyNever(() => host.detach());
      await sub2.cancel();
      await pumpEventQueue();

      verify(() => host.detach()).called(1);
      expect(eventApiSetUps, [platform, null]);
    });

    test(
      'listen, cancel, listen with a slow detach keeps the new listener attached',
      () async {
        final detachGate = Completer<void>();
        when(() => host.detach()).thenAnswer((_) => detachGate.future);

        final sub1 = platform.events.listen((_) {});
        await pumpEventQueue();
        final cancelled = sub1.cancel();
        final received = <KeeperEvent>[];
        final sub2 = platform.events.listen(received.add);
        await pumpEventQueue();

        detachGate.complete();
        await cancelled;
        await pumpEventQueue();

        // The handler must still be installed and native attached.
        expect(eventApiSetUps.last, same(platform));
        verify(() => host.attach(false)).called(greaterThanOrEqualTo(1));
        await platform.onEvents([_connected(1)]);
        await pumpEventQueue();
        expect(received, hasLength(1));
        await sub2.cancel();
      },
    );

    test(
      'a slow detach followed by attach never clears the handler last',
      () async {
        final detachGate = Completer<void>();
        when(() => host.detach()).thenAnswer((_) => detachGate.future);
        final sub1 = platform.events.listen((_) {});
        await pumpEventQueue();
        await sub1.cancel().timeout(Duration.zero, onTimeout: () {});
        final sub2 = platform.events.listen((_) {});
        detachGate.complete();
        await pumpEventQueue();
        expect(eventApiSetUps.last, isNotNull);
        await sub2.cancel();
      },
    );

    test('delivers mapped events and drops duplicates by seq', () async {
      final received = <KeeperEvent>[];
      final sub = platform.events.listen(received.add);

      await platform.onEvents([_connected(1), _connected(2)]);
      await platform.onEvents([_connected(2), _connected(3)]);
      await pumpEventQueue();

      expect(received, hasLength(3));
      expect(received.first, isA<Connected>());
      await sub.cancel();
    });

    test('skips a malformed event and keeps the rest', () async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      final received = <KeeperEvent>[];
      final sub = platform.events.listen(received.add);
      await platform.onEvents([
        PEvent(seq: 1, timestampMs: 0, type: PEventType.connected),
        _connected(2),
      ]);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(errors, hasLength(1));
      await sub.cancel();
    });

    test('attach failure is reported on the stream', () async {
      when(
        () => host.attach(any()),
      ).thenThrow(PlatformException(code: 'channel-error'));
      final completer = Completer<Object>();
      final sub = platform.events.listen(
        (_) {},
        onError: (Object e) => completer.complete(e),
      );

      expect(
        await completer.future,
        isA<BleKeeperException>().having(
          (e) => e.code,
          'code',
          'channel-error',
        ),
      );
      await sub.cancel();
    });
  });
}
