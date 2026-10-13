## 0.1.0

First release.

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
  payloads in release builds.
