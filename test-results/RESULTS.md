# Hardware test results

Phones are referred to by model and OS version only (no serial numbers or IMEIs).
Test IDs refer to `tools/HARDWARE_CHECKLIST.md` (numbers) and to the session plan
(S = smoke, A = Android core, B = Android extra, C = iOS).

## Session setup (2026-10-14)

- Phone B runs `tools/android_test_peripheral` (nRF Connect force-stopped; only the test app's GATT server registered).
- Phone A and Phone B are **bonded** (paired once in Android Settings > Bluetooth; dual-mode bond). The example app keeps Phone B connected by its **identity (public) address**, which the bond lets Phone A resolve although Phone B advertises with rotating private addresses (see SL3). Addresses are not written to this repo.
- Phone A runs the example app as a debug APK installed with `adb install` (not `flutter run`, so kill tests do not detach the tool). Logcat on Phone A is captured continuously (tags BluetoothGatt, ActivityManager, ActivityTaskManager, flutter, AndroidRuntime); the plugin itself writes nothing to logcat, so its exported event log is the primary evidence.
- Phone B's clock is about 4.5 s behind Phone A's.

| Test ID | Date | Test phone | Peripheral | Build type | Result | Evidence | Notes |
|---|---|---|---|---|---|---|---|
| S1 Smoke test | 2026-10-14 | Phone A Galaxy A53 5G, Android 16 | Phone B Galaxy S20 5G (Android 13) via nRF Connect | debug | PASS | manual screenshots | Connected; notifications enabled (CCCD written by plugin); sent 01,02,03,06 as uint32 LE; app showed counter 6, received 4, missed 2, "gap: missed 2" event. |
| O1 Leftover S1 session (observation, not a planned test) | 2026-10-14 | Phone A Galaxy A53 5G, Android 16 | Phone B Galaxy S20 5G (Android 13): nRF Connect stopped, then the BLE Test Peripheral app started | debug | NOT A PLUGIN FAILURE - setup limitation (SL2, SL3) | 2026-10-14/O1-plugin-log.txt, 2026-10-14/O1-logcat.txt | Two persisted sessions. The S1 session (Phone B's address under nRF Connect) retries autoConnect, failing at once with status 135 (address gone, see SL1). The newer session connected at 11:51:56 while nRF Connect's service was still registered; after Phone B's service change (11:52:18) the plugin rediscovered and called setCharacteristicNotification, but the peripheral never received a CCCD write (Subscribed 0, no data) and the plugin reported no problem. |

## Failures

### F1 (withdrawn): no notifications after a peripheral service change

Recorded from O1, then reproduced under control at 11:58 (nRF Connect force-stopped while Phone A was connected): after `onServiceChanged` the plugin rediscovered and the peripheral app logged "notifications enabled" (11:58:26 Phone B clock, about 4.5 s behind Phone A). Subscribing after a service change works. In O1 the plugin had subscribed to nRF Connect's identical service (see SL2). Not a plugin failure; nothing to fix.

## Setup limitations

### SL1: peripheral address changed between S1 and the test session

- The S1 session targeted Phone B's address while nRF Connect advertised. After nRF Connect stopped, Phone B advertises from the test app with a different private address, so the S1 session can never reconnect (Android returns status 135 immediately for autoConnect to that address). This is the rotating-address limitation of a phone peripheral, not a plugin failure. Side note for the example app: it has no way to stop sessions whose ID is not in the text field (only `activeDeviceIds()` + `stop()` from code).

### SL2: two GATT servers on the peripheral phone expose the same service

nRF Connect was reopened on Phone B and its GATT server (Heart Rate, two other services and its own static copy of `12345678-...90ab`) ran next to the test app's server (`dumpsys bluetooth_manager`: Server app_if 6 nRF Connect, app_if 8 test app). The plugin subscribed to the first matching service, nRF Connect's static characteristic, so the counter stayed at 1. Fix: force-stop nRF Connect before every session (`adb shell am force-stop no.nordicsemi.android.mcp`) and check that only the test app is listed under "Server". Killing nRF Connect also dropped the link (status 19 on Phone A) because nRF Connect held its own client connection to Phone A.

### SL3: the phone peripheral's address changes after every advertising restart

After the link dropped at 11:58:28 (Phone B clock), Phone B re-enabled the same advertising set and appeared with a new private address (scan at 12:01: different address than the session's). Every reconnect then failed instantly with status 135 (autoConnect to an address that no longer exists). So with Phone B as peripheral, any test that needs a reconnect after a disconnect is setup-limited unless Phone A can resolve Phone B's rotating address (bonding) or a fixed-address peripheral is used. Evidence: 2026-10-14/S2-logcat.txt, 2026-10-14/S2-plugin-log.txt.

