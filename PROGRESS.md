# PROGRESS

Resume point for "continue from PROGRESS.md". Updated after every step.

Branch: `feat/v0.1.0` (no commits on `main`; nothing pushed).

## Phase status

| Phase | Status |
|---|---|
| 1. Scaffold, Pigeon, Dart API, Android single connection, minimal example | in progress |
| 2. Android robustness (reconnect, BT on/off, 133, headless, log, Blocked, multi-device) | not started |
| 3. iOS (restoration, pending connect, buffering, force-quit heuristic, log, debug kill) | not started |
| 4. Example app + Dart tests | not started |
| 5. Publishing prep | not started |

### Step log

- 1.1 done: `FLUTTER_SWIFT_PACKAGE_MANAGER=true flutter create --template=plugin --platforms=android,ios --org com.ahmadhussain -a kotlin ble_keeper`, git init on `feat/v0.1.0`.

## Environment

- Flutter 3.47.7 / Dart 3.13.5 (upgraded from 3.41.6 at the start of this work).
- Xcode 16.3 on an Intel Mac (macOS 15.7.5). Flutter 3.47 warns that Intel Mac support is being deprecated.
- Template: AGP 9.1.0, Kotlin 2.4.0, compileSdk 36, minSdk 24, iOS 15.0, Swift tools 5.9.
- Pigeon 29.0.8, mocktail (dev).
- Android SDK licences not all accepted (`flutter doctor --android-licenses`, interactive; you run it).
- pana not installed yet (Phase 5 will run `dart pub global activate pana`).

## Decisions (and why)

1. Flutter upgraded to current stable 3.47.7 because the brief says "use current stable versions" and pub.dev scores with current stable.
2. Project created with `FLUTTER_SWIFT_PACKAGE_MANAGER=true` so the template generates `ios/ble_keeper/Package.swift`; the podspec points at the same `Sources/` tree, so CocoaPods and SPM share one code base. `-i swift` dropped (deprecated, no effect).
3. Pigeon 29 generates Kotlin `suspend` and Swift `async throws` for `@async` host methods and for all FlutterApi methods. The Kotlin host handlers run in `CoroutineScope(Dispatchers.Main)`, so the plugin needs `kotlinx-coroutines-android` and must hop to the GATT thread itself.
4. Wire format: one flat `PEvent` envelope instead of Pigeon sealed classes. Native code buffers, persists and logs one uniform record; Pigeon sealed parents cannot carry shared fields. The public Dart API is a hand-written sealed `KeeperEvent` hierarchy.
5. Event delivery goes through a FlutterApi call whose reply is the acknowledgement. Native removes events from its buffer only after the ack (at-least-once; Dart drops duplicate `seq`).
6. API changes against the brief (all recorded here because the brief asked for that):
   - Every device event carries `deviceId` (multi-device support needs it). `Blocked` has an optional `deviceId`; `RestoredAfterKill` carries `deviceIds`.
   - Every event carries a `timestamp` (native time of the BLE callback), not only `Data`.
   - `BlockedReason` gains `misconfigured(detail)` for missing Info.plist keys, a missing iOS bootstrap call, or an unusable background handler.
   - `Disconnected.reason` is a `DisconnectReason` enum plus an optional platform status code.
   - `registerBackgroundHandler` accepts `FutureOr<void> Function(KeeperEvent)`; plain `void` functions still compile. Native waits for the returned future before acknowledging (matters for the ~10 s iOS background window).
   - New `clearLog()` for GDPR erasure of the event log.
   - `AndroidOptions.restartOnBoot` (default `true`).
   - `Connected` means "ready": services discovered and all subscriptions enabled.
7. Plugin manifest does not declare `BLUETOOTH_SCAN`: the plugin never scans, and a library-declared `neverForLocation` flag would merge into host apps and could strip location-derived scan results from apps that use beacons. The example app declares it for its scanner.
8. A denied `POST_NOTIFICATIONS` is not `Blocked`: the foreground service still runs, only the notification is hidden. It is logged as a warning.
9. Foreground service start: try `startForegroundService` and catch `ForegroundServiceStartNotAllowedException` / `SecurityException` instead of pre-checking "app in foreground", because some exemptions are invisible to the app.
10. Event log: device IDs are pseudonymised (salted HMAC, per-install salt) in release builds and written raw in debug builds; payloads are logged as length only. Reason: GDPR data minimisation while keeping bench debugging usable.
11. Template files `lib/ble_keeper_platform_interface.dart`, `lib/ble_keeper_method_channel.dart` and their tests are reused, not deleted (no-delete rule): the platform interface is the test seam and the "method channel" file holds the Pigeon-backed implementation. Optional cleanup for you: rename `ble_keeper_method_channel.dart` to `ble_keeper_pigeon.dart`.
12. iOS kill button (debug only) lives in the example app's AppDelegate behind a method channel, not in the plugin, and not via Dart `Process.killPid` (dart:io process APIs are not reliable on iOS).
13. iOS example scanning uses `universal_ble` (BSD-3) in the example only; `flutter_blue_plus` is not used (non-standard licence).
14. Kotlin coroutines pinned to 1.10.2 (not 1.11.0) so host apps on older Kotlin versions can still read its metadata.

## Open questions

- None blocking. ESP32 behaviour uses the confirmed defaults: `silent` lasts 60 s or until next connection; counter keeps running while disconnected; counter resets on reboot; open link, no pairing; Arduino-ESP32 core 3.x BLE library.

## Needs hardware verification

1. iOS: whether plugin registration happens on a background restoration relaunch without the `bootstrap` call (expected: no, with the UIScene template).
2. iOS: headless engine boot time and memory inside the background window; jetsam risk.
3. iOS 26: restoration after system termination, crash, reboot (after first unlock); no relaunch after force-quit or Settings Bluetooth toggle.
4. iOS: whether notifications survive restoration or must be re-enabled; interplay of `CBConnectPeripheralOptionEnableAutoReconnect` (iOS 17+) with restoration.
5. iOS: false-positive rate of the force-quit heuristic.
6. Android: system restart of a sticky `connectedDevice` foreground service after process death on Android 12-17 (does `startForeground` throw?).
7. Android 15/16/17: starting a `connectedDevice` foreground service from `BOOT_COMPLETED`; force-stop followed by reboot.
8. Android: `adb shell am kill` with a running foreground service (expected: no effect) vs `adb shell run-as <pkg> kill -9 <pid>` (expected: sticky restart and `RestoredAfterKill`).
9. Android: Task Manager "Stop" on 13+ (expected: like force-stop).
10. Android: `autoConnect=true` to an uncached device; status 133 frequency on Samsung/Xiaomi/Oppo; OEM battery killers.
11. Android 14+: user dismisses the foreground-service notification; service keeps running.
12. ESP32 sketch compiles on the installed core 3.x version (`BLE2902`, `getConnId()` changed between minor versions).
13. ESP32 commands and gap counts across reboot and out-of-range; 30 min screen-off on both platforms.

## Before publishing I must

1. Replace `YOUR_GITHUB_USERNAME` everywhere (`grep -rn YOUR_GITHUB_USERNAME .`) and push the repository so pana can verify the URL.
2. Decide the final package name and rename before 0.1.0 (checklist in CONTRIBUTING.md). The restore identifier and storage names change with it; renaming after release would orphan existing users' sessions.
3. Replace `doc/screenshot.png` with a real screenshot.
4. Install Xcode 26 (iOS 26 device testing) and run the hardware checklist.
5. Accept Android SDK licences if a build asks for it.
6. Add a contact address to SECURITY.md.
7. Review README privacy, App Store guideline 2.5.4 and Play Console foreground-service declaration text.
