# ESP32 test device

A small BLE peripheral for exercising ble_keeper on real hardware. It is used by
the example app and by the hardware test checklist in the main README.

## What it does

Advertises as `BLE-Test-Device` with one service:

| Role | UUID | Properties | Content |
|---|---|---|---|
| Service | `12345678-1234-1234-1234-1234567890ab` | | |
| Counter | `12345678-1234-1234-1234-1234567890ac` | read, notify | uint32 little-endian, +1 every second |
| Command | `12345678-1234-1234-1234-1234567890ad` | write, write without response | ASCII command |

Commands:

| Command | Effect | What the app should see |
|---|---|---|
| `disconnect` | Device drops the link and keeps advertising | `Disconnected`, then `Reconnecting`, then `Connected` |
| `reboot` | `ESP.restart()` | `Disconnected`, reconnect after ~1-2 s; counter restarts from 1 |
| `silent` | Link stays up, notifications stop for 60 s or until the next connection | No `Data` events; gap of ~60 when notifications resume |

Counter behaviour:

- It keeps incrementing while disconnected or silent, so the number of missed
  values is `received - previous - 1`.
- It lives in RAM and restarts at 1 after a reboot. The example app treats a
  decrease as a reset, not as a gap.

## Build and flash

1. Install the Arduino IDE 2.x (or `arduino-cli`).
2. Add the ESP32 board package (Espressif "esp32", core 3.x) through the Boards
   Manager.
3. Open `esp32_test_device.ino`, select your board (for example "ESP32 Dev
   Module") and the serial port, and upload.
4. Open the serial monitor at 115200 baud. You should see
   `advertising as BLE-Test-Device`.

With `arduino-cli`:

```sh
arduino-cli core install esp32:esp32
arduino-cli compile --fqbn esp32:esp32:esp32 tools/esp32_test_device
arduino-cli upload --fqbn esp32:esp32:esp32 -p /dev/cu.usbserial-XXXX tools/esp32_test_device
```

## Finding the device ID

- Android: the device ID is the Bluetooth MAC address, for example
  `24:6F:28:AA:BB:CC`. The ESP32 uses its public address, which is printed by
  any BLE scanner (the example app's scan button, or nRF Connect).
- iOS: the device ID is a per-app UUID assigned by iOS. Use the scan button in
  the example app; a UUID taken from another app (such as nRF Connect) will not
  work in yours.

## Security note

This sketch is for the bench only. The link is unauthenticated and anyone in
range can write `reboot`. Real products should use LE Secure Connections
bonding, authenticated writes, and an integrity check (for example CRC) on
application payloads.

## Compatibility note

Written against the Arduino-ESP32 core 3.x built-in BLE library. The library
API has changed between minor versions (3.3 added a NimBLE backend). If the
sketch does not compile on your core version, `BLE2902` and
`BLEServer::getConnId()` are the most likely calls to need adjusting.
