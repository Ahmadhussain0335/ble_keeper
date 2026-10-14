# Android test peripheral

A small native Android app that turns a spare Android phone into a BLE test
peripheral for ble_keeper, behaving like `tools/esp32_test_device`. It is a
test tool only and is not part of the published package (`tools/` is in
`.pubignore`).

## What it does

| Role | UUID | Properties | Content |
|---|---|---|---|
| Service | `12345678-1234-1234-1234-1234567890ab` | | |
| Counter | `12345678-1234-1234-1234-1234567890ac` | read, notify (CCCD) | uint32 little-endian, +1 every second while the server runs; notified to subscribed centrals |
| Command | `12345678-1234-1234-1234-1234567890ad` | write with response | ASCII command |
| Pairing | `12345678-1234-1234-1234-1234567890ae` | read, encrypted link required | ASCII `paired`; the first read from an unbonded central fails with insufficient encryption, which makes iOS (and Android) pair |

| Command | Effect |
|---|---|
| `disconnect` | `BluetoothGattServer.cancelConnection(device)`; advertising resumes |
| `reboot` | disconnects all centrals, disables advertising for 10 s, resets the counter to 0, then advertises again |
| `silent` | keeps the link, sends no notifications for 30 s (the counter keeps running, so the central sees a gap of about 30) |

Advertising: one legacy, connectable, scannable advertising set (100 ms
interval) with the service UUID in the advertising data and the phone's
Bluetooth name in the scan response. The set is created once and only enabled
or disabled, so the address stays the same as long as the stack allows. The
screen stays on while the app is open.

## Build and install

Requirements: Android SDK (compileSdk 36), JDK 17+, the phone with USB
debugging enabled. Android 8.0 (API 26) or later; tested target Android 13.

```sh
cd tools/android_test_peripheral
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties   # if not present
./gradlew :app:assembleDebug
adb -s <peripheral-phone-serial> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <peripheral-phone-serial> shell am start -n com.ahmadhussain.bletestperipheral/.MainActivity
```

Before starting:

1. Rename the phone's Bluetooth name to `BLE-Test-Device` (Settings >
   Connections > Bluetooth > device name). The example app scans by the
   service UUID or by that name.
2. **Stop advertising and close the GATT server of nRF Connect (or any other
   peripheral app) on the same phone.** Two GATT servers exposing the same
   service confuse the central.
3. Open the app, tap **Start**, grant "Nearby devices" (BLUETOOTH_ADVERTISE and
   BLUETOOTH_CONNECT on Android 12+).

The UI shows whether the server runs and advertises, connected centrals, the
number of subscribers, the counter, the last command and a scrolling log.

## Limitation: rotating private address

Android peripherals advertise with a resolvable private address that the
Bluetooth stack rotates (typically about every 15 minutes, and when
advertising restarts after some pauses). An app cannot request a fixed
public address without system privileges. The central (ble_keeper) keeps
connecting to the address it was given, so:

- absence of the central for more than about 10 minutes,
- the `reboot` command,
- a reboot of the peripheral phone, or Bluetooth toggled on it,

can make the peripheral appear with a **new address, i.e. as a new device**.
A reconnect that fails for this reason is a **setup limitation, not a
plugin failure**. Check the address shown in the example app's scan before
and after such a test. These tests need a fixed-address peripheral (the
ESP32 sketch, or a BLE gadget with a static address); see the "Test device"
column in `tools/HARDWARE_CHECKLIST.md`.

### Workaround: bond the two phones

Pair the central phone with the peripheral phone once in Android Settings >
Bluetooth, then keep the peripheral connected by its **identity address**
(Settings > About phone > Status > Bluetooth address on the peripheral
phone, or the address shown in the central's bonded-devices list). The bond
gives the central the peripheral's identity resolving key, so the rotating
private addresses can be resolved. Seen on 2026-10-14 (Galaxy A53 central,
Galaxy S20 peripheral): without the bond the address changed after the first
disconnect; with the bond the plugin connected by identity address.
Reconnects across address changes are checked by the hardware tests (see
`test-results/RESULTS.md`). The plugin itself never bonds.

### iPhone as central

iOS has no pairing screen for BLE peripherals; it pairs when a read hits a
characteristic that needs encryption. In nRF Connect on the iPhone: connect to
`BLE-Test-Device`, read the pairing characteristic (`...90ae`) once, accept the
pairing request on the iPhone and on the peripheral phone, then disconnect and
close nRF Connect. The bond lets iOS keep the same peripheral identifier
across the peripheral's address changes. The peripheral log shows
"pairing characteristic read by ... (bond bonded)".

