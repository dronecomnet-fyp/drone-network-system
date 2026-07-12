/*
 * Rescue mesh aux module: unified firmware for the Seeed XIAO ESP32-C3
 * (file 03). Merges the three Phase 1 test sketches (LoRa, GPS, INA3221)
 * and implements design v3 sections 3.1-3.4: sensor feeder in NORMAL mode,
 * independent LoRa beacon in FALLBACK mode, BLE advertising, last-message
 * flash cache, and the newline-delimited JSON serial protocol to the Pi.
 *
 * Pin map (single source of truth, file 03; the CORRECTED set from
 * com_module_gps, NOT the superseded com_module_lora mapping):
 *
 *   LoRa CS   D3    RFM95 NSS
 *   LoRa DIO0 D1
 *   LoRa RST  D2
 *   LoRa SCK  D8    custom SPI (FSPI)
 *   LoRa MISO D0    (GPIO2) bench-confirmed 2026-07-13; D9 failed SPI
 *   LoRa MOSI D10
 *   GPS RX    D7    (GPIO20, module TX) Serial1 @ 9600
 *   GPS TX    D6    (GPIO21, module RX)
 *   I2C SDA   D4    (GPIO6) INA3221 @ 0x40 (A0 to GND)
 *   I2C SCL   D5    (GPIO7)
 *   Pi link   USB-C native CDC @ 115200 (no GPIO used)
 *   (all signal pins now allocated; D0 was the former spare)
 *
 * State machine: INIT -> NORMAL -> FALLBACK, one-way per boot (design v3
 * default: stay in fallback until power cycle; simpler to reason about.
 * If the team later wants auto-recovery on a fresh ping, change
 * FALLBACK_IS_TERMINAL below and re-run TESTS.md test 3).
 *
 * Power/duty figures to verify on the bench (TESTS.md test 6): the
 * battery decision doc assumes a 177 mA class average draw; measured
 * NORMAL/FALLBACK averages that diverge materially must be flagged
 * (project rule 5), not silently absorbed.
 */

#include <Arduino.h>
#include <ArduinoJson.h>
#include <LoRa.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <SPI.h>
#include <TinyGPSPlus.h>
#include <Wire.h>

// ---------------------------------------------------------------------------
// Pins and constants
// ---------------------------------------------------------------------------

static const int PIN_LORA_CS = D3;
static const int PIN_LORA_DIO0 = D1;
static const int PIN_LORA_RST = D2;
static const int PIN_LORA_SCK = D8;
// MISO is on D0 (GPIO2), NOT D9: confirmed on the bench 2026-07-13 when
// D9 failed SPI reads and D0 worked (docs/CHANGES.md). This uses every
// signal pin; D0 is no longer spare.
static const int PIN_LORA_MISO = D0;
static const int PIN_LORA_MOSI = D10;
static const int PIN_GPS_RX = D7;  // module TX -> our RX
static const int PIN_GPS_TX = D6;  // module RX <- our TX
static const int PIN_I2C_SDA = D4;
static const int PIN_I2C_SCL = D5;

// LoRa: 915 MHz, SF7, BW 125 kHz (file 03). TX power at the LIBRARY
// MINIMUM (2 dBm on PA_BOOST per the sandeepmistry LoRa API, confidence
// Moderate) until the TRCSL regulatory question is resolved (master plan
// R1). Do NOT raise this for range tests before clearance.
static const long LORA_FREQ = 915E6;
static const int LORA_TX_POWER_DBM = 2;

// INA3221 at 0x40, 100 milliohm shunts (from the working Phase 1 test
// sketch). Channel map per design v3: CH1 = Battery A (Pi side),
// CH2 = Battery B (aux), CH3 = spare. Register math per the TI INA3221
// datasheet (SBOS576): bus LSB 8 mV, shunt LSB 40 uV, values are 13-bit
// left-aligned (>> 3). Confidence: High (manufacturer datasheet).
static const uint8_t INA3221_ADDR = 0x40;
static const float SHUNT_OHMS = 0.100f;

// Timing (file 03)
static const uint32_t SENSOR_SEND_MS = 5000;     // gps + battery every 5 s
static const uint32_t FIRST_PING_GRACE_MS = 60000;  // slow Pi boot allowance
static const uint32_t PING_TIMEOUT_MS = 15000;   // then the 15 s dead-Pi rule
static const uint32_t FALLBACK_BEACON_MS = 30000;
static const uint32_t GPS_TIME_RESEND_MS = 60000;  // re-offer gps_time each minute

// BLE (file 03): project-fixed 128-bit service UUID, generated once
// 2026-07-11, hardcoded FLEET-WIDE. The emergency app (file 06) filters
// scans by this UUID; also goes into design v4.
static const char* BLE_SERVICE_UUID = "2b57461c-1c04-49c4-944a-13643c1618da";
static const uint16_t BLE_ADV_MIN = 800;   // 0.625 ms units -> 500 ms
static const uint16_t BLE_ADV_MAX = 1600;  // -> 1000 ms

// One-way state machine per boot (see header comment).
static const bool FALLBACK_IS_TERMINAL = true;

enum class Mode { NORMAL, FALLBACK };

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------

SPIClass loraSPI(FSPI);
TinyGPSPlus gps;
Preferences prefs;
NimBLEAdvertising* bleAdv = nullptr;

Mode mode = Mode::NORMAL;
String nodeId = "UNSET";
String apSsid = "RESCUE_X";
String cachedMsgId = "none";
String cachedMsgContent = "no messages yet";
String cachedMsgTime = "";

uint32_t bootMs = 0;
uint32_t lastPingMs = 0;
bool firstPingSeen = false;
uint32_t lastSensorSendMs = 0;
uint32_t lastBeaconMs = 0;
uint32_t lastGpsTimeSendMs = 0;
bool loraOk = false;
bool inaOk = false;
String serialLine;

// ---------------------------------------------------------------------------
// INA3221 minimal driver (register math per TI datasheet, see above)
// ---------------------------------------------------------------------------

static bool inaWrite16(uint8_t reg, uint16_t value) {
  Wire.beginTransmission(INA3221_ADDR);
  Wire.write(reg);
  Wire.write(value >> 8);
  Wire.write(value & 0xFF);
  return Wire.endTransmission() == 0;
}

static bool inaRead16(uint8_t reg, uint16_t& out) {
  Wire.beginTransmission(INA3221_ADDR);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom((int)INA3221_ADDR, 2) != 2) return false;
  out = ((uint16_t)Wire.read() << 8) | Wire.read();
  return true;
}

static bool inaInit() {
  // Config 0x7127: all channels on, 1.1 ms conversions, 16-sample average,
  // continuous shunt+bus (TI datasheet defaults with averaging).
  return inaWrite16(0x00, 0x7127);
}

// channel: 1..3. Returns false if the chip did not answer.
static bool inaReadChannel(uint8_t ch, float& busV, float& currentMa) {
  uint16_t rawShunt, rawBus;
  uint8_t shuntReg = 0x01 + 2 * (ch - 1);
  uint8_t busReg = 0x02 + 2 * (ch - 1);
  if (!inaRead16(shuntReg, rawShunt) || !inaRead16(busReg, rawBus)) return false;
  int16_t sShunt = (int16_t)rawShunt >> 3;  // 13-bit signed, LSB 40 uV
  int16_t sBus = (int16_t)rawBus >> 3;      // 13-bit signed, LSB 8 mV
  float shuntV = sShunt * 40e-6f;
  busV = sBus * 8e-3f;
  currentMa = (shuntV / SHUNT_OHMS) * 1000.0f;
  return true;
}

// ---------------------------------------------------------------------------
// BLE advertising (replaces the failed Phase 1 Pi approach, master plan D3)
// ---------------------------------------------------------------------------

static void bleStart() {
  // Service data payload "nodeLetter|ssid" (e.g. "A|RESCUE_A" = 10 bytes)
  // fits the legacy 31-byte ADV budget next to flags + 16-byte UUID; the
  // human-readable name goes in the scan response (file 03).
  String nodeLetter = nodeId.length() ? String(nodeId[nodeId.length() - 1]) : "?";
  String payload = nodeLetter + "|" + apSsid;
  if (payload.length() > 10) payload = payload.substring(0, 10);

  String localName = "RESCUE-" + nodeLetter;

  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  advData.setServiceData(NimBLEUUID(BLE_SERVICE_UUID),
                         std::string(payload.c_str(), payload.length()));
  NimBLEAdvertisementData scanData;
  scanData.setName(localName.c_str());

  bleAdv = NimBLEDevice::getAdvertising();
  bleAdv->stop();
  bleAdv->setAdvertisementData(advData);
  bleAdv->setScanResponseData(scanData);
  bleAdv->setAdvertisementType(BLE_GAP_CONN_MODE_NON);  // not connectable
  bleAdv->setMinInterval(BLE_ADV_MIN);
  bleAdv->setMaxInterval(BLE_ADV_MAX);
  bleAdv->start();
}

static void bleStop() {
  if (bleAdv != nullptr) bleAdv->stop();
}

// ---------------------------------------------------------------------------
// Serial protocol out (Pi direction)
// ---------------------------------------------------------------------------

static void sendJson(JsonDocument& doc) {
  serializeJson(doc, Serial);
  Serial.println();
}

static void sendGps() {
  JsonDocument doc;
  doc["type"] = "gps";
  bool fix = gps.location.isValid();
  doc["fix"] = fix ? 1 : 0;
  if (fix) {
    doc["lat"] = gps.location.lat();
    doc["lon"] = gps.location.lng();
  } else {
    doc["lat"] = nullptr;
    doc["lon"] = nullptr;
  }
  doc["sats"] = gps.satellites.isValid() ? (int)gps.satellites.value() : 0;
  if (gps.hdop.isValid()) doc["hdop"] = gps.hdop.hdop();
  sendJson(doc);
}

static void sendBattery() {
  JsonDocument doc;
  doc["type"] = "battery";
  float v, ma;
  if (inaOk && inaReadChannel(1, v, ma)) {
    doc["bat_a_v"] = v;
    doc["bat_a_ma"] = ma;
  } else {
    doc["bat_a_v"] = nullptr;
    doc["bat_a_ma"] = nullptr;
  }
  if (inaOk && inaReadChannel(2, v, ma)) {
    doc["bat_b_v"] = v;
    doc["bat_b_ma"] = ma;
  } else {
    doc["bat_b_v"] = nullptr;
    doc["bat_b_ma"] = nullptr;
  }
  sendJson(doc);
}

static String gpsUtcIso() {
  char buf[24];
  snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02dZ",
           gps.date.year(), gps.date.month(), gps.date.day(),
           gps.time.hour(), gps.time.minute(), gps.time.second());
  return String(buf);
}

static void sendGpsTimeIfValid() {
  // On first valid date+time and every re-fix (file 03): the Pi applies it
  // once at startup then hourly (aux_bridge decides; we just keep offering
  // at most once a minute to keep serial traffic low).
  if (!(gps.date.isValid() && gps.time.isValid() && gps.location.isValid())) return;
  if (millis() - lastGpsTimeSendMs < GPS_TIME_RESEND_MS) return;
  lastGpsTimeSendMs = millis();
  JsonDocument doc;
  doc["type"] = "gps_time";
  doc["utc"] = gpsUtcIso();
  doc["fix"] = 1;
  doc["sats"] = gps.satellites.isValid() ? (int)gps.satellites.value() : 0;
  sendJson(doc);
}

// ---------------------------------------------------------------------------
// Flash cache (design v3 layer 8)
// ---------------------------------------------------------------------------

static void loadCache() {
  prefs.begin("aux", false);
  nodeId = prefs.getString("node_id", "UNSET");
  cachedMsgId = prefs.getString("msg_id", "none");
  cachedMsgContent = prefs.getString("msg_content", "no messages yet");
  cachedMsgTime = prefs.getString("msg_time", "");
}

static String sanitizeForBeacon(String s) {
  s.replace("|", " ");  // pipe is the beacon separator (file 03)
  if (s.length() > 100) s = s.substring(0, 100);
  return s;
}

// ---------------------------------------------------------------------------
// Serial protocol in (Pi -> module)
// ---------------------------------------------------------------------------

static void handleLine(const String& line) {
  JsonDocument doc;
  if (deserializeJson(doc, line) != DeserializationError::Ok) return;
  const char* type = doc["type"] | "";

  if (strcmp(type, "ping") == 0) {
    lastPingMs = millis();
    firstPingSeen = true;

  } else if (strcmp(type, "last_msg") == 0) {
    cachedMsgId = doc["msg_id"] | "none";
    cachedMsgContent = sanitizeForBeacon(String((const char*)(doc["content"] | "")));
    cachedMsgTime = doc["timestamp"] | "";
    prefs.putString("msg_id", cachedMsgId);
    prefs.putString("msg_content", cachedMsgContent);
    prefs.putString("msg_time", cachedMsgTime);
    JsonDocument ack;
    ack["type"] = "last_msg_ack";
    ack["msg_id"] = cachedMsgId;
    sendJson(ack);

  } else if (strcmp(type, "lora_tx") == 0) {
    const char* payload = doc["payload"] | "";
    if (loraOk && strlen(payload) > 0) {
      LoRa.beginPacket();
      LoRa.print(payload);
      LoRa.endPacket();
    }

  } else if (strcmp(type, "ble_update") == 0) {
    nodeId = String((const char*)(doc["node_id"] | nodeId.c_str()));
    apSsid = String((const char*)(doc["ssid"] | apSsid.c_str()));
    if (mode == Mode::NORMAL) bleStart();

  } else if (strcmp(type, "set_node_id") == 0) {
    // Per-board provisioning: one binary serves all modules (file 03).
    nodeId = String((const char*)(doc["node_id"] | "UNSET"));
    prefs.putString("node_id", nodeId);
    JsonDocument ack;
    ack["type"] = "set_node_id_ack";
    ack["node_id"] = nodeId;
    sendJson(ack);
    if (mode == Mode::NORMAL) bleStart();
  }
}

static void pollPiSerial() {
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\n') {
      handleLine(serialLine);
      serialLine = "";
    } else if (serialLine.length() < 512) {
      serialLine += c;
    }
  }
}

// ---------------------------------------------------------------------------
// LoRa receive (both modes)
// ---------------------------------------------------------------------------

static void pollLora() {
  if (!loraOk) return;
  int packetSize = LoRa.parsePacket();
  if (packetSize <= 0) return;
  String payload;
  payload.reserve(packetSize);
  while (LoRa.available()) payload += (char)LoRa.read();

  JsonDocument doc;
  if (payload.startsWith("FB|")) {
    doc["type"] = "fallback_rx";
    doc["raw"] = payload;
  } else {
    doc["type"] = "lora_rx";
    doc["payload"] = payload;
  }
  doc["rssi"] = LoRa.packetRssi();
  doc["snr"] = LoRa.packetSnr();
  sendJson(doc);
}

// ---------------------------------------------------------------------------
// Fallback beacon (design v3 exact format, file 03; <= 255 bytes)
// ---------------------------------------------------------------------------

static void sendFallbackBeacon() {
  if (!loraOk) return;
  float aV = 0, aMa = 0, bV = 0, bMa = 0;
  bool haveA = inaOk && inaReadChannel(1, aV, aMa);
  bool haveB = inaOk && inaReadChannel(2, bV, bMa);
  bool fix = gps.location.isValid();

  String beacon = "FB|" + nodeId + "|";
  beacon += fix ? String(gps.location.lat(), 6) : "";
  beacon += "|";
  beacon += fix ? String(gps.location.lng(), 6) : "";
  beacon += "|";
  beacon += fix ? "1" : "0";
  beacon += "|";
  beacon += (gps.date.isValid() && gps.time.isValid()) ? gpsUtcIso() : "";
  beacon += "|";
  beacon += haveA ? String(aV, 2) : "";
  beacon += "|";
  beacon += haveA ? String(aMa, 0) : "";
  beacon += "|";
  beacon += haveB ? String(bV, 2) : "";
  beacon += "|";
  beacon += haveB ? String(bMa, 0) : "";
  beacon += "|" + cachedMsgId + "|" + cachedMsgContent + "|" + cachedMsgTime + "|DOWN";

  if (beacon.length() > 255) beacon = beacon.substring(0, 255);
  LoRa.beginPacket();
  LoRa.print(beacon);
  LoRa.endPacket();
}

// ---------------------------------------------------------------------------
// Setup / loop
// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);  // native USB CDC to the Pi
  bootMs = millis();
  // A Pi that boots slowly must not be declared dead instantly: require
  // the FIRST ping within FIRST_PING_GRACE_MS, then apply the 15 s rule.
  lastPingMs = bootMs;

  loadCache();

  Serial1.begin(9600, SERIAL_8N1, PIN_GPS_RX, PIN_GPS_TX);

  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  inaOk = inaInit();

  loraSPI.begin(PIN_LORA_SCK, PIN_LORA_MISO, PIN_LORA_MOSI, PIN_LORA_CS);
  LoRa.setSPI(loraSPI);
  LoRa.setPins(PIN_LORA_CS, PIN_LORA_RST, PIN_LORA_DIO0);
  loraOk = LoRa.begin(LORA_FREQ);
  if (loraOk) {
    LoRa.setTxPower(LORA_TX_POWER_DBM);
    LoRa.setSpreadingFactor(7);
    LoRa.setSignalBandwidth(125E3);
  }

  NimBLEDevice::init("");
  bleStart();

  JsonDocument doc;
  doc["type"] = "boot";
  doc["node_id"] = nodeId;
  doc["lora"] = loraOk;
  doc["ina3221"] = inaOk;
  sendJson(doc);
}

void loop() {
  // Continuous, non-blocking (file 03): GPS bytes, Pi serial, LoRa rx.
  while (Serial1.available()) gps.encode((char)Serial1.read());
  pollPiSerial();
  pollLora();

  uint32_t now = millis();

  if (mode == Mode::NORMAL) {
    if (now - lastSensorSendMs >= SENSOR_SEND_MS) {
      lastSensorSendMs = now;
      sendGps();
      sendBattery();
    }
    sendGpsTimeIfValid();

    uint32_t timeout = firstPingSeen ? PING_TIMEOUT_MS : FIRST_PING_GRACE_MS;
    if (now - lastPingMs > timeout) {
      mode = Mode::FALLBACK;
      bleStop();  // conserve Battery B (design v3)
      lastBeaconMs = 0;  // beacon immediately
      JsonDocument doc;
      doc["type"] = "fallback_enter";
      sendJson(doc);
    }
  } else {  // FALLBACK
    if (lastBeaconMs == 0 || now - lastBeaconMs >= FALLBACK_BEACON_MS) {
      lastBeaconMs = now;
      sendFallbackBeacon();
    }
    if (!FALLBACK_IS_TERMINAL && Serial) {
      // Optional future path: a fresh ping could return us to NORMAL.
      // Disabled by default (design v3: stay in fallback until power
      // cycle). handleLine still updates lastPingMs if pings arrive.
      if (now - lastPingMs < PING_TIMEOUT_MS) {
        mode = Mode::NORMAL;
        bleStart();
      }
    }
  }
}
