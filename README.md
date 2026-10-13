# ble_keeper

Keeps a BLE peripheral connected while your Flutter app is in the background,
after the OS kills it, and after the phone reboots, on Android and iOS. When
the OS does not allow that (user force-quit, Bluetooth off, missing
permission), it tells you instead of failing silently.

## Why

BLE plugins such as flutter_blue_plus run their connection logic inside the
Flutter engine. When the engine goes away (UI closed, process killed), so does
the connection, and full background support is out of scope for those
plugins (flutter_blue_plus issue #846).

ble_keeper owns the connection in native code that does not depend on the
Flutter UI:

- **Android**: a foreground service of type `connectedDevice` holds the GATT
  connections and restarts after process death, reboot and app updates.
- **iOS**: a `CBCentralManager` with Core Bluetooth state restoration, so iOS
  keeps the connection and relaunches the app in the background.

Dart sends commands and receives events. When no UI is running, events go to
a background handler in a headless Flutter engine.

It is not a general BLE library: no scanning, no GATT server, no OTA. Use it
next to a scanning plugin.

## What the OS allows

Android:

| Situation | Connection kept? | What you get |
|---|---|---|
| App in background, screen off | Yes (foreground service) | Events as usual |
| UI closed / swiped from recents | Yes on stock Android; some OEMs kill the service (see Troubleshooting) | Events in the background handler |
| Process killed by the system (memory) | Restarted by the system (sticky service) | `RestoredAfterKill` |
| `adb shell am kill` | Not affected (a process with a foreground service is not "background") | Nothing |
| Force-stop (Settings, `am force-stop`, Task Manager "Stop") | **No.** Android keeps a force-stopped app stopped until the user opens it | `Blocked(UserForceQuit)` on the next launch (API 30+) |
| Reboot | Yes after first unlock, when `restartOnBoot` is true | `RestoredAfterKill` |
| App update | Yes | `RestoredAfterKill` |
| Bluetooth turned off | Paused, reconnects when turned on | `Disconnected(bluetoothOff)`, `Blocked(BluetoothOff)` |
| `BLUETOOTH_CONNECT` denied (Android 12+) | No | `Blocked(PermissionMissing)` |
| `keepConnected` called while the app is in the background | No (Android 12+ background start restriction) | `Blocked(ForegroundStartNotAllowed)` |

Restart timing after a system kill and boot behaviour on Android 15+ depend on
the vendor build. Verify on the devices you support (the example app and the
ESP32 sketch are made for that).

iOS (per Apple TN3115, "Conditions under which Bluetooth State Restoration
will relaunch an app"):

| Situation | Relaunched by state restoration? | What you get |
|---|---|---|
| App suspended in the background | Connection kept by iOS | Events as usual |
| Terminated by the system (memory) | Yes | `RestoredAfterKill` |
| Crash | Yes | `RestoredAfterKill` |
| Reboot | Yes, after the first unlock, when the peripheral reconnects | `RestoredAfterKill` |
| **User force-quit** (swipe up in the app switcher) | **No** | `Blocked(UserForceQuit)` on the next launch, best effort |
| Bluetooth turned off in Settings | No | `Blocked(BluetoothOff)` while off |
| Bluetooth permission denied | No | `Blocked(PermissionMissing('bluetooth'))` |
| App update | No | Reconnects when the user opens the app |

iOS does not tell an app that the user force-quit it. ble_keeper infers it on
the next launch: connections were being kept, the app was not relaunched by
state restoration, and either `applicationWillTerminate` ran (strong signal)
or nothing else explains it (weak signal, flagged "best effort" in the
event detail). False positives: Bluetooth turned off in Settings while the app
was suspended, a reboot after which the peripheral never came in range before
the user opened the app, or a system termination with no Bluetooth event
before the user opened the app.

## Install

```sh
flutter pub add ble_keeper
```

Requires Flutter 3.44 or later, Android 7.0 (API 24) or later, iOS 15 or
later.

## Android setup

The plugin's manifest adds these permissions to your app:

| Permission | Why |
|---|---|
| `BLUETOOTH_CONNECT` | Connect and use GATT (runtime permission on Android 12+) |
| `BLUETOOTH`, `BLUETOOTH_ADMIN` (`maxSdkVersion=30`) | Same, Android 11 and lower |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` | The foreground service (type `connectedDevice`) |
| `POST_NOTIFICATIONS` | Show the service notification (runtime permission on Android 13+) |
| `RECEIVE_BOOT_COMPLETED` | Restart after reboot (`AndroidOptions.restartOnBoot`) |

It does **not** declare `BLUETOOTH_SCAN` or location: ble_keeper never scans.
Your scanning plugin declares what it needs.

The plugin does not request runtime permissions. Request
`BLUETOOTH_CONNECT` (and `POST_NOTIFICATIONS` on Android 13+) before calling
`keepConnected`, for example with permission_handler. If
`POST_NOTIFICATIONS` is denied the service still runs; Android only hides
its notification.

Call `keepConnected` while your app is visible. Android 12 and later do not
allow starting a foreground service from the background; you get
`Blocked(ForegroundStartNotAllowed)` instead.

**Notification icon.** Pass the name of a monochrome drawable in your app:

```dart
const AndroidOptions(
  notificationTitle: 'Sensor connected',
  notificationText: 'Receiving data in the background',
  notificationIcon: 'ic_stat_bluetooth', // res/drawable/ic_stat_bluetooth.xml
)
```

The icon is looked up by name, so resource shrinking may remove it. Keep it
with `res/raw/keep.xml`:

```xml
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_stat_bluetooth" />
```

Without an icon the plugin uses its own Bluetooth glyph. The default texts
are string resources (`ble_keeper_channel_name`,
`ble_keeper_notification_text`) that you can override or translate.

**Google Play.** Apps targeting Android 14+ must declare foreground service
types in the Play Console (App content > Foreground service permissions).
Declare `connectedDevice` and describe the user-visible feature (for example
"keeps the heart-rate strap connected during a workout").

**Opt out of boot restart.** Set `restartOnBoot: false`, or remove the
permission in your manifest:

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"
    tools:node="remove" />
```

## iOS setup

**Info.plist** (both keys are required; a missing usage description makes
Core Bluetooth terminate the app):

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connects to your sensor and keeps it connected in the background.</string>
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
</array>
```

Without `bluetooth-central` the plugin still connects in the foreground, but
iOS suspends the connection with the app and state restoration is disabled;
you get `Blocked(Misconfigured(...))`.

**AppDelegate.** State restoration requires the central manager to be created
during `application(_:didFinishLaunchingWithOptions:)`. When iOS relaunches
the app in the background, no scene and no Flutter UI engine is created, so
normal plugin registration does not happen. Add one call before `super`:

```swift
import Flutter
import UIKit
import ble_keeper

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    BleKeeperPlugin.bootstrap(launchOptions: launchOptions) { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

The closure registers plugins on the headless engine used for the background
handler. If the call is missing, you get `Blocked(Misconfigured(...))` when
the UI listens to events.

**App Store review.** Guideline 2.5.4 allows background modes only for their
intended purpose. Explain in the review notes which Bluetooth accessory the
app keeps connected and why that needs the background (for example
continuous sensor logging). There are no entitlement changes.

**Device IDs** on iOS are `CBPeripheral.identifier` UUIDs. They are assigned
per app install, so get them from a scan in your own app (a UUID copied from
another app does not work) and store them; after a reinstall you need to scan
again.

## Usage

```dart
import 'package:ble_keeper/ble_keeper.dart';

final counter = CharacteristicRef(
  serviceUuid: '12345678-1234-1234-1234-1234567890ab',
  characteristicUuid: '12345678-1234-1234-1234-1234567890ac',
);

Future<void> start(String deviceId) async {
  // Android: MAC address, e.g. 'AA:BB:CC:DD:EE:FF'. iOS: peripheral UUID.
  await BleKeeper.instance.keepConnected(
    deviceId: deviceId,
    subscribe: [counter],
    android: const AndroidOptions(notificationTitle: 'Sensor connected'),
  );
}

void listen() {
  BleKeeper.instance.events.listen((event) {
    switch (event) {
      case Data(:final bytes):
        print('value: $bytes');
      case Connected(:final deviceId):
        print('connected $deviceId');
      case Disconnected(:final reason):
        print('disconnected: ${reason.name}');
      case Reconnecting(:final attempt):
        print('reconnecting, attempt $attempt');
      case RestoredAfterKill(:final deviceIds):
        print('restored after the OS killed the app: $deviceIds');
      case Blocked(:final reason):
        print('the OS does not allow it: $reason');
    }
  });
}
```

Other calls:

```dart
await BleKeeper.instance.write(deviceId, command, Uint8List.fromList([1]));
final value = await BleKeeper.instance.read(deviceId, someCharacteristic);
await BleKeeper.instance.stop(deviceId);          // disconnect and forget
final ids = await BleKeeper.instance.activeDeviceIds();
```

`keepConnected` is persisted: the plugin keeps reconnecting until you call
`stop`, also across app restarts. Calling it again for the same device
replaces its subscriptions and options. Several devices can be kept at once.

`keepConnected` returns when the request is accepted, not when the device is
connected. `Connected` means services are discovered and every subscription
is enabled. Problems the OS imposes arrive as `Blocked` events; programming
errors (bad UUID, empty subscription list) throw `ArgumentError`; platform
errors on `read`/`write` throw `BleKeeperException` with a `code` such as
`not_connected`, `payload_too_large` or `timeout`.

Events are buffered natively while nobody listens and delivered when the
first listener subscribes.

## Background handler

When no UI is running (for example after Android restarted the service, or
iOS relaunched the app for Bluetooth), events go to a handler you register:

```dart
@pragma('vm:entry-point')
Future<void> onBackgroundEvent(KeeperEvent event) async {
  if (event is Data) {
    // Short work only: store, upload, show a notification.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BleKeeper.instance.registerBackgroundHandler(onBackgroundEvent);
  runApp(const MyApp());
}
```

- It must be a top-level or static function with `@pragma('vm:entry-point')`.
- It runs in its own isolate; it does not share memory with the UI isolate.
  Use plugins (storage, HTTP) inside it as usual.
- Register on every app start: callback handles change when the app is
  updated. Until then you get `Blocked(Misconfigured(...))`.
- If it returns a future, the next batch waits for it. iOS gives a background
  app only a few seconds per Bluetooth event.
- While a UI listener exists, events go to the UI only.

## Event log and privacy

Both platforms keep a rotating log of events (two files of 1 MB, one event
per line, ISO-8601 UTC timestamps):

```
2026-10-13T09:32:33.123Z #42 data device=dev-3f2a91c4 char=12345678-1234-1234-1234-1234567890ac len=4
```

`exportLog()` returns the path of a single file you can share;
`clearLog()` deletes the log and exported copies.

Device identifiers are personal data under GDPR (an Android MAC address is a
persistent hardware identifier). In **release builds** the log replaces them
with a per-install salted hash (`dev-xxxxxxxx`) and never contains payload
bytes, only their length. Debug builds log raw IDs for bench work. Files are
stored in app-private storage excluded from backups. Your app is the data
controller: mention the log in your privacy notice if you export it.

The plugin does no networking and sends nothing off the device.

## Testing with an ESP32

`tools/esp32_test_device/` (in the GitHub repository) contains an Arduino
sketch that advertises as `BLE-Test-Device`, sends a uint32 counter every
second and accepts the commands `disconnect`, `reboot` and `silent`. The
example app connects to it, shows the counter, counts missed values and has
buttons for the commands.

1. Flash the sketch (see its README).
2. Run the example app, tap the scan icon, pick `BLE-Test-Device`, tap
   **Keep connected**.
3. The counter increases every second; **Missed** shows values lost during
   disconnects (the device keeps counting while disconnected).
4. Try the commands, Bluetooth off/on, walking out of range, killing the app.
   **Export log** shares the native event log.

## Troubleshooting

**Connection drops when the screen is off on Xiaomi, Oppo, Vivo, Huawei,
Samsung.** These vendors stop foreground services that stock Android allows.
Ask users to:

- Xiaomi (MIUI/HyperOS): Settings > Apps > your app > Autostart: on; Battery
  saver: No restrictions; lock the app in recents.
- Oppo / OnePlus / Realme (ColorOS): Settings > Battery > App battery
  management > your app: allow background activity and auto launch.
- Samsung (One UI): Settings > Battery > Background usage limits: remove the
  app from "Sleeping apps" and "Deep sleeping apps"; set the app's battery
  usage to "Unrestricted".
- Huawei (EMUI): Settings > Battery > App launch > your app: manage manually,
  allow all three options.

See dontkillmyapp.com for current per-vendor steps.

**Status 133 on Android.** A generic GATT error, frequent on some vendors.
ble_keeper closes the connection and retries with exponential backoff (1 s up
to 60 s). Persistent 133s usually mean the peripheral is out of range, already
connected to another phone, or the phone's Bluetooth stack needs a toggle.

**Android never connects to a new device.** The first attempt is a direct
connection that times out after about 30 s; later attempts use
`autoConnect`, which only finds devices the phone has seen recently. Make
sure the device is advertising and in range for the first connection.

**Stale services after a firmware update (Android).** Android caches the GATT
table for unbonded devices. Turn Bluetooth off and on to clear it.

**iOS: `Misconfigured: iOS does not know this peripheral`.** The identifier
does not belong to this app install. Scan for the device in your app first.

## Limitations

- iOS force-quit detection is a heuristic (see the table above).
- Android OEM battery managers can stop the service regardless.
- Writes are not queued across disconnects; `write` fails with
  `not_connected`.
- No scanning, bonding API, GATT server or OTA.
- Payload integrity (CRC, sequence numbers) is your protocol's job.

## Roadmap

- Android `CompanionDeviceService` (API 31+) so the system binds the app when
  an associated device comes in range.
- iOS AccessorySetupKit (iOS 18+) for pairing and accessory-scoped
  permissions.
- Connection priority and PHY options, bonding helpers.

## FAQ

**Can I use it together with flutter_blue_plus or universal_ble?** Yes, for
scanning. Do not also connect to the same device with the other plugin: two
connection owners in one app interfere (on Android two GATT clients, on iOS
two central managers sharing one system connection).

**Does it keep the app running?** On Android the foreground service keeps the
process alive. On iOS the app is suspended as usual; iOS keeps the connection
and wakes the app for Bluetooth events.

**Why do I get `RestoredAfterKill` on a normal iOS launch?** iOS hands
preserved Bluetooth state back whenever the app starts after it was
terminated in the background; that is a restoration.

**Why is `deviceId` a MAC address on Android and a UUID on iOS?** Those are
what the platforms use. iOS never exposes MAC addresses.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues as described
in [SECURITY.md](SECURITY.md).

## License

BSD 3-Clause. See [LICENSE](LICENSE).
