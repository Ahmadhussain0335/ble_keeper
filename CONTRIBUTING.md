# Contributing

Issues and pull requests are welcome at
https://github.com/Ahmadhussain0335/ble_keeper.

## Before you open a pull request

Run from the repository root:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
(cd example && flutter test)
```

Native unit tests:

```sh
# Android (JUnit + MockK). Needs the example's Gradle project once:
(cd example && flutter build apk --config-only)
(cd example/android && ./gradlew :ble_keeper:testDebugUnitTest)

# iOS (XCTest), on macOS with Xcode. Pick any installed simulator
# (`xcrun simctl list devices available`):
(cd example && flutter build ios --simulator --debug)
xcodebuild test -workspace example/ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,OS=18.4,name=iPad (A16)'
```

Build the example on both platforms:

```sh
(cd example && flutter build apk --debug && flutter build apk --release)
(cd example && flutter build ios --no-codesign)
```

Behaviour that depends on real hardware (reconnects, OS kills, reboots)
cannot be unit-tested. Use the ESP32 test device in `tools/esp32_test_device/`
and the checklist in `tools/HARDWARE_CHECKLIST.md`; record results in the
README "Verified on" table.

## Dart / native contract (Pigeon)

The channel contract lives in `pigeons/messages.dart`. After changing it,
regenerate and format the bindings, and commit the generated files:

```sh
dart run pigeon --input pigeons/messages.dart
dart format .
```

Generated files (do not edit by hand):

- `lib/src/messages.g.dart`
- `android/src/main/kotlin/com/ahmadhussain/ble_keeper/Messages.g.kt`
- `ios/ble_keeper/Sources/ble_keeper/Messages.g.swift`

The event envelope `PEvent` is flat on purpose: native code buffers, persists
and logs one record type. `lib/src/event_mapper.dart` turns it into the
public sealed `KeeperEvent` classes.

## Code layout

- `lib/`: public Dart API (`ble_keeper.dart`), platform interface, Pigeon
  implementation, background dispatcher.
- `android/src/main/kotlin/.../`: `core/` (runtime, event hub, persistence),
  `gatt/` (connection per device), `service/` (foreground service, boot
  receiver, notification), `headless/` (background Flutter engine), `log/`.
- `ios/ble_keeper/Sources/ble_keeper/`: Swift implementation, shared by
  CocoaPods (`ios/ble_keeper.podspec`) and Swift Package Manager
  (`ios/ble_keeper/Package.swift`).

## Log format

Both platforms write the same one-line format; the golden tests in
`android/src/test/.../log/LogFormatterTest.kt` and the iOS
`LogFormatterTests.swift` must stay in sync.

## Renaming the package

The package name appears where Flutter tooling requires it. To rename
`ble_keeper` to `new_name`, change:

1. `pubspec.yaml` `name`, and every `package:ble_keeper/` import.
2. `pigeons/messages.dart`: `dartPackageName`, output paths, Kotlin package;
   then regenerate.
3. Android: `android/build.gradle.kts` (`group`, `namespace`),
   `android/settings.gradle.kts`, the Kotlin package directory
   `com/ahmadhussain/ble_keeper`, and `pubspec.yaml` `flutter.plugin.platforms.android.package`.
4. iOS: `ios/ble_keeper/` directory, `Package.swift` (package, product and
   target names), `ios/ble_keeper.podspec` (file name, `s.name`,
   `source_files`, resource bundle), and the module import in the example
   `AppDelegate.swift`.
5. `KeeperConstants` (Kotlin and Swift) and `ble_keeper_strings.xml` /
   `ic_ble_keeper_notification.xml` resource names.
6. README, CHANGELOG, CONTRIBUTING, workflows.

Find leftovers with `grep -rni "ble_keeper\|blekeeper" --exclude-dir=build --exclude-dir=.dart_tool .`

Rename before the first release. `KeeperConstants` values (storage
directories, iOS restore identifier, notification channel) are persisted on
users' devices; changing them later orphans existing sessions.

## Releasing

1. Update `version` in `pubspec.yaml` and `ios/ble_keeper.podspec`, and
   `CHANGELOG.md`.
2. Merge to `main` with CI green.
3. The first release (0.1.0-beta.1) is published manually: `flutter pub publish`.
4. Later releases: push a tag `vX.Y.Z` (pre-releases: `vX.Y.Z-beta.N`). `.github/workflows/publish.yml` uses
   the reusable `dart-lang/setup-dart` publish workflow (it installs Dart for
   the OIDC token and Flutter to resolve the plugin) in the GitHub environment
   `pub.dev`. One-time setup: create that environment in the repository
   settings, and on pub.dev > Admin > Automated publishing enable GitHub
   Actions for `Ahmadhussain0335/ble_keeper` with tag pattern `v{{version}}`
   and required environment `pub.dev`.

## Commit messages

Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`,
`chore:`, `ci:`.
