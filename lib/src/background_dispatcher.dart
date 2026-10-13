import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'event_mapper.dart';
import 'messages.g.dart';

/// Entry point of the headless engine that native code starts when events
/// arrive and no UI is attached.
///
/// Native code finds this function through the callback handle stored by
/// `registerBackgroundHandler`, so it must stay top-level and keep the
/// `vm:entry-point` pragma (otherwise release builds tree-shake it).
@pragma('vm:entry-point')
Future<void> bleKeeperBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // Any failure here just means "not attached"; native then reports
  // Blocked(misconfigured) when the engine does not attach in time.
  try {
    final host = BleKeeperHostApi();
    final raw = await host.backgroundHandlerHandle();
    final handler = raw == null
        ? null
        : PluginUtilities.getCallbackFromHandle(
            CallbackHandle.fromRawHandle(raw),
          );
    if (handler == null) {
      debugPrint(
        'ble_keeper: background handler not found. It must be a top-level '
        "or static function annotated with @pragma('vm:entry-point'), "
        'registered with registerBackgroundHandler on every app start.',
      );
      return;
    }
    BleKeeperEventApi.setUp(BackgroundEventReceiver(handler));
    await host.attach(true);
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'ble_keeper',
        context: ErrorDescription('while starting the background dispatcher'),
      ),
    );
  }
}

/// Delivers events to the user's background handler, one at a time.
///
/// The returned future completes after every handler call finished, which is
/// the acknowledgement native code waits for. Handler errors are reported but
/// still acknowledged, so a throwing handler cannot cause endless redelivery.
@visibleForTesting
class BackgroundEventReceiver implements BleKeeperEventApi {
  /// Creates a receiver for [handler], which takes one KeeperEvent.
  BackgroundEventReceiver(this._handler);

  final Function _handler;
  int _lastSeq = -1;

  @override
  Future<void> onEvents(List<PEvent> events) async {
    for (final e in events) {
      if (e.seq <= _lastSeq) continue;
      _lastSeq = e.seq;
      try {
        final result = Function.apply(_handler, [mapEvent(e)]);
        if (result is Future) await result;
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'ble_keeper',
            context: ErrorDescription('while running the background handler'),
          ),
        );
      }
    }
  }
}
