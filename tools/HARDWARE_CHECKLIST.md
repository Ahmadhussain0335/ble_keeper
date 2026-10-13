# Hardware test checklist

Setup for every test:

1. Flash `tools/esp32_test_device` (see its README); serial monitor at 115200.
2. Install the example app in **debug** (raw device IDs in the log) and in
   **release** once (pseudonymised log).
3. Android: tap **Permissions**, grant all. iOS: accept the Bluetooth prompt.
4. Scan, pick `BLE-Test-Device`, tap **Keep connected**. Expect
   `connected`, counter increasing every second, Missed 0.
5. After each test tap **Export log** and keep the file.

Android logcat filter, if needed: `adb logcat | grep -i -E "ble_keeper|BluetoothGatt"`.
`adb` lives in `~/Library/Android/sdk/platform-tools/`.

Devices: one stock-ish Android (Pixel), one aggressive-battery phone
(Xiaomi, Oppo or Samsung), an iPhone on iOS 26 (needs Xcode 26 to install).

| # | Test | Steps | Expected |
|---|---|---|---|
| 1 | Screen off 30 min | Connected, lock the phone, wait 30 min, unlock | Counter kept increasing; Missed 0 (or small, only at link drops). Android: notification shown the whole time. iOS: data arrived while locked (check the per-minute data summary lines in the exported log) |
| 2 | `am kill` (Android) | `adb shell am kill com.ahmadhussain.ble_keeper_example` | No effect: a process with a foreground service is not killable this way. Counter continues |
| 3 | Real process kill (Android) | `adb shell run-as com.ahmadhussain.ble_keeper_example kill -9 $(adb shell pidof com.ahmadhussain.ble_keeper_example)` | Within seconds to minutes the system restarts the sticky service: log shows `service restarted by the system`, `restoredAfterKill`, `connected`. Missed = values during the gap. Background handler line in logcat (`ble_keeper background: RestoredAfterKill`). Record the restart delay |
| 4 | Force-stop (Android) | `adb shell am force-stop com.ahmadhussain.ble_keeper_example` (or Settings > Force stop) | Connection ends; no restart, also not after reboot. Open the app: `Blocked(userForceQuit)` (API 30+), then the service resumes and `connected` |
| 5 | Out of range and back | Walk away until `disconnected` (linkLoss/code 8), wait 2 min, come back | `reconnecting attempt 1`, then `connected` on return without user action. Missed ~= seconds away |
| 6 | ESP32 `disconnect` | Tap **disconnect** | `disconnected ... peerTerminated (code 19)` (Android) / `peerTerminated (code 7)` (iOS), then `connected` within a few seconds |
| 7 | ESP32 `reboot` | Tap **reboot** | `disconnected`, reconnect after ~2 s, "counter reset (device rebooted)", Resets +1, Missed unchanged |
| 8 | ESP32 `silent` | Tap **silent** | Link stays up, no data for 60 s, then "gap: missed ~60" |
| 9 | Bluetooth off/on | Turn Bluetooth off 30 s (Android quick settings; iOS Control Center **and** separately Settings) | `disconnected bluetoothOff`, `BLOCKED Bluetooth is off`; after turning on: `connected` without user action. iOS Control Center may not report off: record what happens |
| 10 | Phone reboot | Reboot, unlock once, do not open the app | Android: within ~1 min `service started after boot`, `restoredAfterKill`, `connected` (export log after opening). iOS: app relaunched when the device reconnects; open the app: `restored after kill` in the event list |
| 11 | iOS debug kill | Tap **Simulate system kill (debug)** (run from Xcode or detached; the debugger keeps a killed app stopped otherwise) | App terminates; within seconds iOS relaunches it in the background when the peripheral sends data. Open the app: `restored after kill`, counter continues, Missed = gap |
| 12 | iOS swipe force-quit | Open the app switcher, swipe the app away, wait 2 min, open the app | Not restored while closed (no data in the log for that period). On launch: `BLOCKED app was force-quit by the user` (best effort), then reconnects |
| 13 | OEM battery killer | On Xiaomi/Oppo/Samsung with default battery settings: connect, swipe from recents, screen off 30 min | Record whether the service survives. Repeat after applying the README Troubleshooting settings |
| 14 | Permission revoked (Android 12+) | Settings > Apps > Nearby devices: deny, return to the app | `BLOCKED permission missing: android.permission.BLUETOOTH_CONNECT`; service stops |
| 15 | Background start (Android 12+) | Put the app in background, trigger `keepConnected` via a timer in a debug build | `BLOCKED ... from the background` |
| 16 | Notification dismissed (Android 14+) | Swipe the service notification away | Service keeps running, counter continues |

## Tests added in the verification pass

| # | Test | Steps | Expected |
|---|---|---|---|
| 17 (H1) | iOS background reconnect after a failed connect | ESP32 off. Connect in the app, then background it (home screen) and lock. Wait 5 min, switch the ESP32 on, wait 2 min, unlock and open the app | While locked the app was woken: exported log shows `connected` and data summaries with timestamps before you opened the app. Also repeat with the ESP32 in range but `reboot` looping (tap reboot 5 times quickly in foreground first): after 5 setup failures one `BLOCKED unknown: connection setup failed 5 times`, still retrying |
| 18 (H2) | Android device absent for 2+ hours, battery | Fully charge, unplug. `adb shell dumpsys batterystats --reset`. ESP32 off. Keep connected, screen off for 2 h. Then `adb shell dumpsys batterystats > stats.txt` and export the log | Log: about 3 direct attempts or 2 min of them, then waiting with autoConnect (no `reconnecting` lines every ~30-60 s for 2 h; at most one watchdog note per 30 min). Battery: the app is not among the top Bluetooth/wakelock consumers. Record % drop per hour. Switch the ESP32 on: reconnects without user action |
| 19 (H3) | UI listen / cancel / listen | In a debug build, navigate away from and back to a screen that listens to `BleKeeper.instance.events` 10 times quickly (or hot-restart repeatedly) while connected | The counter keeps updating after every return; no "frozen" UI until an app restart |
| 20 | Random static address peripheral | Use a peripheral that advertises with a random static address (many nRF52/ESP32-C3 setups; check with nRF Connect: address type "random"). Connect, then toggle phone Bluetooth off/on, then power-cycle the peripheral | Android and iOS reconnect after both actions. If a peripheral regenerates its address on boot, record that a reconnect is not possible (expected; README Limitations) |
| 21 (M5) | Notification during an iOS restoration relaunch | Connected; tap **Simulate system kill (debug)** (app not attached to the debugger). Wait 30 s, open the app | The exported log shows `restoredAfterKill` followed by data summaries whose first sequence starts right after the relaunch; Missed in the UI is close to the seconds the app was dead, not more (the triggering notification was not lost) |

Write results (device, OS version, pass/fail, timings) into the README
"Verified on" table and PROGRESS.md "Needs hardware verification".
