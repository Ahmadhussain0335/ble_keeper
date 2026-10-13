# PROGRESS

Resume point for "continue from PROGRESS.md". Updated after every step.

Branch: `feat/v0.1.0` (no commits on `main`; nothing pushed).

## Verification-and-fix pass (2026-10-13, after the first push)

Brief: confirm each review finding in code, fix with a test where possible, or reject with a
reason. Local commits only; the user pushes. Status per finding:

| ID | Status | Change | Test |
|---|---|---|---|
| H1 iOS pending connect | Confirmed, fixed | PeripheralSession: `ReconnectDecision` (delay only in foreground), `appDidEnterBackground`, failure counter + Blocked at 5; holder/runtime track foreground | ReconnectDecisionTests |
| H2 Android direct-connect forever | pending | | |
| H3 Dart attach/detach race | pending | | |
| H4 publish workflow | pending | | |
| M1 short-lived link loop | pending | | |
| M2 startForeground before stop | pending | | |
| M3 duplicate CONNECTED | pending | | |
| M4 log aggregation | pending | | |
| M5 iOS restore delegates | Confirmed (CentralManagerHolder.swift:83 set delegate from an empty `sessions`), fixed | willRestoreState creates sessions from stored sessions and sets delegates; connect waits for poweredOn; also Low: no cancelPeripheralConnection when not powered on | hardware (checklist R-M5) |
| M6 iOS headless gate | pending | | |
| M7 iOS notify failure | pending | | |
| M8 never evict non-Data | pending | | |
| M9 force-quit wording | pending | | |
| M10 min Flutter CI | pending | | |
| M11 CI XCTest/dry-run/timeouts | pending | | |
| M12 move Pigeon impl to src | pending | | |
| Low items | pending | | |
| Part 2 docs | pending | | |
| Part 3 gates | pending | | |
| Consumer app test | pending | | |

## Phase status

| Phase | Status |
|---|---|
| 1. Scaffold, Pigeon, Dart API, Android single connection, minimal example | done |
| 2. Android robustness (reconnect, BT on/off, 133, headless, log, Blocked, multi-device) | code done with phase 1 (one commit; the pieces depend on each other); hardware verification pending |
| 3. iOS (restoration, pending connect, buffering, force-quit heuristic, log, debug kill) | done; hardware verification pending |
| 4. Example app + Dart tests | done |
| 5. Publishing prep | done except the items under "Before publishing I must" |

### Step log

- 1.1 done: `FLUTTER_SWIFT_PACKAGE_MANAGER=true flutter create --template=plugin --platforms=android,ios --org com.ahmadhussain -a kotlin ble_keeper`, git init on `feat/v0.1.0`.
- 1.2-1.4 done: Pigeon contract + generated code, Dart API (sealed events, mapper, platform interface, Pigeon implementation, background dispatcher), 61 Dart tests.
- 1.6-1.7 + phase 2 done: Android runtime, KeeperService, GattManager, EventHub, SessionStore, KeeperState, BootReceiver, HeadlessEngineRunner, RotatingEventLog, LogFormatter, 55 JVM unit tests (`./gradlew :ble_keeper:testDebugUnitTest`).
- 1.8 done: minimal example (device ID, keep connected, counter) + widget test.
- Checks: `dart format` clean, `flutter analyze` 0 issues, `flutter test` 61 pass, example widget test pass, `flutter build apk --debug` OK.
- Phase 1 iOS check: `flutter build ios --no-codesign --debug` OK (Swift Package Manager, the 3.47 default).
- 3.x done: Swift KeeperRuntime, CentralManagerHolder (restore identifier only when bluetooth-central is declared), PeripheralSession (pending connect, discovery, notify, read/write with timeouts, write-without-response flow control), EventHub, SessionStore, KeeperState, ForceQuitDetector, ConfigurationChecker, HeadlessEngineRunner, LogFormatter, RotatingEventLog, privacy manifest enabled for CocoaPods and SPM. XCTests in example/ios/RunnerTests (run on the iOS 18.4 simulator).
- 3.7 done: example Info.plist keys, AppDelegate `BleKeeperPlugin.bootstrap`, debug-only `simulateSystemKill` channel.
- 4 done: example app (scan via universal_ble, keep/stop, live counter, gap/reset detection, link state, event log, 3 ESP32 commands, export/clear log, Android permission helper, iOS debug kill button), 19 example tests.
- 5 done: pubspec (0.1.0, description 150 chars, topics, screenshots, `meta` dependency for generated code), README, LICENSE (BSD-3), CHANGELOG, CONTRIBUTING, SECURITY.md, .pubignore, CI (SHA-pinned actions) and publish workflows, ESP32 sketch in tools/.
- Review pass: `reviewer` and `security-auditor` agents. Fixed: event delivery stopped for good after one failed ack (now retried every 5 s); reconnect loop without backoff when setup failed; API 26-32 notification value race (handler only on API 33+); `keepConnected` right after the last `stop` hit the dying service; headless engine started during UI start-up or after the service stopped; timed-out read/write left the GATT stack busy (now drops the link); restartOnBoot=false sessions not resumed by the UI; permission checked before `startForeground`; iOS write-without-response ordering; orphaned restored peripherals cancelled; duplicate Connected after a service change; queued writes failing slowly; clearLog now rotates the salt and removes the corrupt-session backup; only the newest export is kept (iOS export file protection complete); iOS backup exclusion re-applied every launch; Dart caps on subscriptions (32) and notification strings (256); example no longer prints raw IDs.

## Verification results (last run 2026-10-13, Flutter 3.47.7, Xcode 16.3)

| Check | Result |
|---|---|
| `dart format --set-exit-if-changed .` | clean |
| `flutter analyze` (plugin + example) | 0 issues |
| `flutter test` (plugin) | 63 passed |
| `flutter test` (example) | 19 passed |
| Kotlin unit tests (`:ble_keeper:testDebugUnitTest`) | 55 passed |
| XCTest (example RunnerTests, iOS 18.4 simulator) | 31 passed |
| `flutter build apk --debug` | OK |
| `flutter build ios --no-codesign` (Swift Package Manager) | OK |
| CocoaPods build (fresh app with SPM disabled, plugin by path, in a scratch clone) | OK |
| `flutter pub publish --dry-run` | 0 warnings, 135 KB |
| pana 0.23.19 | 150/160. Lost 10: screenshot check needs `cwebp`/`gif2webp`/`webpinfo` (not installed here; `brew install webp`). Repository URL warning (placeholder) costs no points yet |

Not run: integration tests on a device, the CI workflows on GitHub, any hardware test (see tools/HARDWARE_CHECKLIST.md).

## Environment

- Flutter 3.47.7 / Dart 3.13.5 (upgraded from 3.41.6 at the start of this work).
- Xcode 16.3 on an Intel Mac (macOS 15.7.5). Flutter 3.47 warns that Intel Mac support is being deprecated.
- Template: AGP 9.1.0, Kotlin 2.4.0, compileSdk 36, minSdk 24, iOS 15.0, Swift tools 5.9.
- Pigeon 29.0.8, mocktail (dev).
- Android SDK licences not all accepted (`flutter doctor --android-licenses`, interactive; you run it).
- pana 0.23.19 installed with `dart pub global activate pana` (binary in `~/.pub-cache/bin`, not on PATH).
- Example pins permission_handler ^12.0.1: 13.x requires compileSdk 37 (not bumped; ask before SDK changes).

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
11. The template's platform interface is kept as the test seam. The template's `ble_keeper_method_channel.dart` (which held the Pigeon implementation) was moved with `git mv` to `lib/src/pigeon_ble_keeper.dart` in the verification pass (M12), so it is no longer public API; its test moved to `test/pigeon_ble_keeper_test.dart`.
12. iOS kill button (debug only) lives in the example app's AppDelegate behind a method channel, not in the plugin, and not via Dart `Process.killPid` (dart:io process APIs are not reliable on iOS).
13. iOS example scanning uses `universal_ble` (BSD-3) in the example only; `flutter_blue_plus` is not used (non-standard licence).
14. Kotlin coroutines pinned to 1.10.2 (not 1.11.0) so host apps on older Kotlin versions can still read its metadata.
15. Minimum Flutter 3.44.0 / Dart 3.12: the 3.47 plugin template relies on built-in Kotlin (no `kotlin-android` plugin in the plugin's build file). Flutter 3.44.0 is the first release whose Gradle plugin applies `kotlin-android` to such plugins when the app disables built-in Kotlin. Only 3.47.7 is actually tested.
16. Background callback handles are stored in a file in `noBackupFilesDir`, not SharedPreferences as the brief suggested: handles are only valid for the installed build, and Auto Backup would restore stale handles on a new device. A plugin cannot change the host app's backup rules.
17. Android first connection attempt is direct (`autoConnect=false`), later reconnects use `autoConnect=true`. `autoConnect=true` only finds devices already in the stack cache and can wait forever for one it has never seen.
18. A lost link reconnects immediately (autoConnect waits without timeout); immediate failures (status 133, connect timeout) back off 1 s, 2 s, 4 s ... 60 s with +/-20 % jitter.
19. The service runs all GATT work on one HandlerThread; `connectGatt(..., handler)` (API 26+) delivers callbacks there. API 24-25 callbacks arrive on binder threads and are re-posted.
20. Event delivery to Dart: a UI listener gets priority; the headless engine starts only when no UI engine has an activity and a handler is registered. If the headless isolate does not attach within 20 s, `Blocked(misconfigured)` is emitted and no restart is attempted until `registerBackgroundHandler` is called again.
21. When the UI attaches and sessions exist but the service is not running (for example after a force-stop), the plugin restarts the service. Rationale: `keepConnected` means "until stop()".
22. Force-stop is detected on the next launch with `ApplicationExitInfo.REASON_USER_REQUESTED` (API 30+), reported once as `Blocked(userForceQuit)`.
23. Write limits: without response MTU - 3; with response up to 512 bytes (Android performs a long write).
24. New error code `read_unsupported` (characteristic without the read property).
25. Notification text and channel name are string resources (`ble_keeper_strings.xml`) so apps can translate them by overriding the resource names.
26. Plugin manifest adds `RECEIVE_BOOT_COMPLETED` (restart after reboot). Apps that do not want it can remove it with `tools:node="remove"`.
27. Fallback notification icon path is from Material Icons "bluetooth" (Apache 2.0), attributed in the XML.

## Deferred review findings (not fixed in 0.1.0)

- Android pseudonym salt is stored as a file next to the log; with sandbox access the 24-bit MAC suffix space can be brute-forced. Fix: AndroidKeyStore HMAC key (security-auditor C-04). Documented in README.
- Optional `logRawDeviceIds` flag instead of following the debuggable/DEBUG build (C-06). Documented in README.
- No cap on the number of devices (C-05 partly): connection limits differ per controller.
- Android `update()` does not unsubscribe characteristics removed from a session (they keep notifying until the next reconnect).
- Android `everConnected` is in memory only, so after a sticky restart or boot the first reconnect is a direct connect (30 s) before autoConnect takes over.
- Small file reads (sessions.json) on the Android main thread.
- iOS: a notification arriving while a read is pending on the same characteristic completes the read (Core Bluetooth delivers both through one callback).
- Dart: events arriving between the last listener cancelling and native `detach` are acknowledged but dropped.

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

1. Done: GitHub username `Ahmadhussain0335`, repository https://github.com/Ahmadhussain0335/ble_keeper (remote `origin` added, nothing pushed yet). Push the repository so pana can verify the URL.
2. Decide the final package name and rename before 0.1.0 (checklist in CONTRIBUTING.md). The restore identifier and storage names change with it; renaming after release would orphan existing users' sessions.
3. Replace `doc/screenshot.png` with a real screenshot.
4. Install Xcode 26 (iOS 26 device testing) and run the hardware checklist.
5. Accept Android SDK licences if a build asks for it.
6. Replace `SECURITY_CONTACT_EMAIL` in SECURITY.md and enable private vulnerability reporting on GitHub.
7. Review README privacy, App Store guideline 2.5.4 and Play Console foreground-service declaration text.
9. Run CI once on GitHub (macOS job included) after pushing; the workflows were not executed locally.
10. Enable automated publishing on pub.dev (Admin > Automated publishing > GitHub Actions, repository `<you>/ble_keeper`, tag pattern `v{{version}}`) after the first manual publish.
