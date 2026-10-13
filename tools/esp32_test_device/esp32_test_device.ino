// BLE test peripheral for ble_keeper.
//
// Advertises as "BLE-Test-Device" and exposes one service with:
//   - a notify characteristic carrying a uint32 little-endian counter that
//     increments every second, connected or not, so the app can count gaps;
//   - a command characteristic accepting "disconnect", "reboot" or "silent".
//
// Bench use only: the link is unauthenticated and anyone in range can send
// "reboot". Production firmware should use LE Secure Connections bonding and
// authenticated writes.
//
// Target: Arduino-ESP32 core 3.x (API checked against 3.3.x), built-in BLE
// library with either the Bluedroid (default on ESP32) or NimBLE backend.

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#if defined(CONFIG_BLUEDROID_ENABLED)
#include <BLE2902.h>
#endif

static const char *DEVICE_NAME = "BLE-Test-Device";
static const char *SERVICE_UUID = "12345678-1234-1234-1234-1234567890ab";
static const char *NOTIFY_UUID = "12345678-1234-1234-1234-1234567890ac";
static const char *COMMAND_UUID = "12345678-1234-1234-1234-1234567890ad";

static const uint32_t TICK_MS = 1000;
static const uint32_t SILENT_MAX_MS = 60000;

static BLEServer *server = nullptr;
static BLECharacteristic *notifyChar = nullptr;

static volatile bool connected = false;
static volatile bool silent = false;
static volatile bool rebootRequested = false;
static volatile bool disconnectRequested = false;
static uint32_t silentSinceMs = 0;
static uint32_t counter = 0;
static uint32_t lastTickMs = 0;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *s) override {
    connected = true;
    // "silent" lasts until the next connection.
    silent = false;
    Serial.println("connected");
  }

  void onDisconnect(BLEServer *s) override {
    connected = false;
    Serial.println("disconnected, advertising again");
    BLEDevice::startAdvertising();
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    String cmd = c->getValue();
    cmd.trim();
    Serial.printf("command: %s\n", cmd.c_str());
    // Work is deferred to loop() so the write response is sent first.
    if (cmd == "disconnect") {
      disconnectRequested = true;
    } else if (cmd == "reboot") {
      rebootRequested = true;
    } else if (cmd == "silent") {
      silent = true;
      silentSinceMs = millis();
    }
  }
};

void setup() {
  Serial.begin(115200);
  BLEDevice::init(DEVICE_NAME);

  server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);

  notifyChar = service->createCharacteristic(
      NOTIFY_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
#if defined(CONFIG_BLUEDROID_ENABLED)
  // Bluedroid needs the CCCD added by hand; NimBLE adds it automatically for
  // characteristics with notify/indicate (BLE2902 is deprecated there).
  notifyChar->addDescriptor(new BLE2902());
#endif

  BLECharacteristic *commandChar = service->createCharacteristic(
      COMMAND_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  commandChar->setCallbacks(new CommandCallbacks());

  service->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("advertising as BLE-Test-Device");
}

void loop() {
  uint32_t now = millis();

  if (disconnectRequested) {
    disconnectRequested = false;
    delay(100);
    // The app should see a peer-terminated link (HCI 0x13).
    server->disconnect(server->getConnId());
  }

  if (rebootRequested) {
    delay(100);
    ESP.restart();
  }

  if (silent && now - silentSinceMs >= SILENT_MAX_MS) {
    silent = false;
    Serial.println("silent period over");
  }

  if (now - lastTickMs >= TICK_MS) {
    lastTickMs = now;
    // The counter keeps running while disconnected or silent, so the app can
    // count missed values as (received - previous - 1). It resets to 0 on
    // reboot because it lives in RAM.
    counter++;
    uint8_t bytes[4] = {
        (uint8_t)(counter & 0xFF),
        (uint8_t)((counter >> 8) & 0xFF),
        (uint8_t)((counter >> 16) & 0xFF),
        (uint8_t)((counter >> 24) & 0xFF),
    };
    notifyChar->setValue(bytes, sizeof(bytes));
    if (connected && !silent) {
      notifyChar->notify();
    }
  }

  delay(10);
}
