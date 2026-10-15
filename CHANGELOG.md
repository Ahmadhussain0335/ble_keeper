## 0.1.0-beta.2

Status: Android verified on real hardware. iOS tested on an iPhone 13
(iOS 26.6) with profile and release builds made with Xcode 16.3; see
"Verified on" in the README. The two iOS issues found there are fixed below
and covered by unit tests, but not yet re-tested on the device.

Fixed (iOS):

* A session could report `Connected` without notifications after the
  peripheral changed its GATT table. Service Changed is now handled during
  setup too (not only when ready), notifications are re-enabled on every
  new link instead of trusting a cached `isNotifying`, and a subscribed
  characteristic that is missing after discovery is rediscovered once
  (after 2 s) before `Blocked(misconfigured)` is reported. Problems are
  reported once per connection instead of once per session. The message
  says when the whole service is missing, which points to iOS's GATT cache
  for bonded devices (see Troubleshooting in the README).
* The background handler did not start after a Core Bluetooth relaunch on
  iOS 26 when the launch options lacked `.bluetoothCentrals`. A state
  restoration (`willRestoreState`) now also counts as a Bluetooth launch for
  the headless-engine decision.

Example app:

* **Simulate system kill** never worked (the Runner target had no Swift
  `DEBUG` condition); it is now available in debug and profile builds and
  compiled out of release builds.

## 0.1.0-beta.1

First public pre-release.

Status: Android is verified on real hardware (Samsung Galaxy A53 5G,
Android 16, debug and release builds; see "Verified on" in the README).
iOS builds and passes its unit tests on the simulator but is **not yet
verified on a real iPhone**; 0.1.0 follows after iOS hardware testing.

* Keeps BLE peripherals connected from native code that does not depend on
  the Flutter UI: an Android foreground service (`connectedDevice`) and an
  iOS `CBCentralManager` with Core Bluetooth state restoration.
* Automatic reconnect: Android `autoConnect` with status 133 backoff, iOS
  pending connect. Reconnects after Bluetooth is turned back on.
* Restarts after Android process death (sticky service), reboot and app
  update (`BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`), and after iOS system
  termination via state restoration.
* Sealed `KeeperEvent` stream: `Connected`, `Disconnected`, `Reconnecting`,
  `Data`, `RestoredAfterKill`, `Blocked`.
* `Blocked` reasons for what the OS does not allow: Bluetooth off, missing
  permission, Android background foreground-service start, user force-quit
  (Android exact, iOS best effort), app misconfiguration.
* Background handler that runs in a headless engine when no UI is running.
* Notifications/indications, read, write with and without response.
* Rotating event log (2 x 1 MB) with export; pseudonymised device IDs and no
  payloads in release builds; Data events summarised per minute.

Fixed during hardware testing (Android 16):

* `BOOT_COMPLETED` delivered when a force-stopped app is opened again is no
  longer treated as a reboot (no misleading `RestoredAfterKill`).
* A force-stop shortly after an app update is reported as `userForceQuit`.
* The event log writes the open Data summary before each state event.
