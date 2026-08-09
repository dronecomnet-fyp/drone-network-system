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
 *   Batt A    INA3221 CH1 (shunt in the Battery A line)
 *   Batt B    INA3221 CH2 (shunt in the Battery B line); BOTH channels are
 *                   bidirectional: a battery that is being charged reads a
 *                   NEGATIVE current. See the sign convention below.
 *   Pi link   USB-C native CDC @ 115200 (no GPIO used)
 *   (all signal pins now allocated; D0 was the former spare)
 *
 * State machine: INIT -> NORMAL <-> FALLBACK. Entering fallback takes 15 s
 * of Pi silence; LEAVING it takes 3 consecutive pings (also 15 s), so the
 * transition is symmetric and cannot flap. This replaces design v3's
 * one-way-per-boot rule, which latched a healthy drone into permanent
 * LoRa beaconing after nothing worse than a service restart
 * (CHANGES.md item 31; TESTS.md test 3).
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
// sketch). Channel map: CH1 = Battery A, CH2 = Battery B, CH3 unused.
// Register math per the TI INA3221 datasheet (SBOS576): bus LSB 8 mV,
// shunt LSB 40 uV, values are 13-bit left-aligned (>> 3) two's complement.
// Confidence: High (manufacturer datasheet).
static const uint8_t INA3221_ADDR = 0x40;
static const float SHUNT_OHMS = 0.100f;

// BIDIRECTIONAL CURRENT (both batteries charge as well as discharge).
// The INA3221 shunt register is SIGNED, so current has a direction, and a
// battery on charge genuinely reads negative. The convention this firmware
// publishes, fleet-wide:
//
//     current > 0  ->  DISCHARGING (battery is supplying the load)
//     current < 0  ->  CHARGING    (current flowing into the battery)
//     current ~ 0  ->  idle / float (see the noise floor below)
//
// That holds when the shunt is wired with IN+ on the battery side and IN-
// on the load side. If a channel is soldered the other way round, every
// reading on it is inverted: rather than re-solder, flip the matching flag
// below. Verify per board with TESTS.md test 1 (a known load must read
// positive) before trusting the sign.
static const bool BATT_A_SHUNT_INVERT = false;   // CH1 wired IN+ to battery
static const bool BATT_B_SHUNT_INVERT = false;   // CH2 wired IN+ to battery

// IS EACH CHANNEL ACTUALLY WIRED TO A BATTERY?
//
// An INA3221 input with nothing attached FLOATS, and on the usual breakout
// boards it floats up near the supply rail. Field testing found Battery B
// reporting a confident 4.18 V with no battery connected at all, which
// reads exactly like a healthy full pack (field backlog #8). Believing a
// battery is fine when there is no battery is worse than reporting nothing.
//
// The firmware cannot tell a floating input from a real 4.18 V pack by
// voltage alone, so it is told instead. Set the flag false for a channel
// that is not wired and it reports null rather than a number.
//
// PROPER HARDWARE FIX, do this when convenient: tie an unused channel's
// IN+ and IN- to GND. It then reads about 0 V instead of floating, and the
// plausibility floor below catches it automatically with no flag to
// remember.
// Whether a battery is actually wired to each INA3221 channel.
//
// These CANNOT be inferred. An unconnected input floats near the supply
// rail and reads about 4.18 V with a little noise, which is
// indistinguishable from a healthy full cell by voltage alone. The
// existing plausibility floor only catches an input pulled to ground.
//
// They were compile-time constants, which meant a module whose wiring
// differed from the build reported a battery that was not there, and the
// only fix was recompiling. They now live in NVS alongside the node id,
// so a module can be told what is fitted, and the boot message reports
// what it believes so the operator can check.
bool battAPresent = true;
bool battBPresent = true;

// Below this a channel is treated as not connected. No pack we use sits
// under 1 V while actually attached (a 1S LiPo is dead by 3.0 V and a 2S
// pack far higher), so this only ever fires on a grounded or dead input.
static const float BATT_MIN_PLAUSIBLE_V = 1.0f;

// Measurement limits worth knowing when reading these numbers (both come
// straight from the datasheet plus the 0.100 ohm shunt, confidence High):
//   Range:       13-bit signed x 40 uV = +/-163.8 mV across the shunt,
//                which is +/-1638 mA. A charge or load current beyond that
//                CLIPS at the rail; it does not wrap.
//   Resolution:  one count = 40 uV = 0.4 mA, so readings near zero jitter
//                by a few tenths of a mA. Consumers must treat a small
//                magnitude as "idle", not as a real direction; the apps do
//                this with a shared threshold (kBatteryIdleMa).

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

// FALLBACK auto-recovery (CHANGES.md item 31). Design v3 originally made
// fallback terminal until a power cycle, for simplicity. Operationally that
// was wrong: the Pi only has to go quiet for PING_TIMEOUT_MS (15 s) for the
// module to latch, and an ordinary `systemctl restart rescue-mesh-auxbridge`
// can exceed that. The module then beacons over LoRa forever and stays
// BLE-dark, so a perfectly healthy drone looks DOWN to the whole fleet and
// is invisible to the emergency app until someone power-cycles it by hand.
//
// So recovery is on, with hysteresis: the Pi must deliver
// FALLBACK_RECOVERY_PINGS consecutive pings (5 s apart) before we trust it
// again. 3 pings = 15 s of steady contact, deliberately the mirror of the
// 15 s it takes to declare the Pi dead, so a flapping Pi cannot make the
// module oscillate between modes.
static const bool FALLBACK_IS_TERMINAL = false;
static const uint8_t FALLBACK_RECOVERY_PINGS = 3;

// Planned shutdown (front panel work, field backlog #1).
//
// The two sub-units are powered SEPARATELY on purpose, which is the whole
// fault-tolerance design. The side effect nobody thought about until the
// panel was designed: switching a node off deliberately kills the Pi while
// this module is still running, so it misses heartbeats, concludes the Pi
// has crashed, and starts telling the entire fleet that this node has
// FAILED. An intentional power-down was indistinguishable from a failure.
//
// The Pi now says goodbye before it halts, and we suppress fallback for a
// grace window rather than forever. Forever would mean one stray message
// could silently disable the fallback beacon for the rest of the flight,
// which is the one thing this module exists to do.
//
// The window has to cover a clean halt plus somebody reaching over to
// flip the switch. In practice that is under a minute: the Pi takes about
// 20 s to go down and the operator is standing next to it.
//
// It was five minutes first, and that was too generous in a way that bit
// during testing. EVERY ordinary reboot arms this window, so a fallback
// test performed within five minutes of a reboot produced no beacon and
// looked exactly like the fallback feature being broken. 90 s covers the
// real sequence with room to spare, and stops the suppression quietly
// swallowing a genuine failure that happens shortly after maintenance.
static const uint32_t SHUTDOWN_GRACE_MS = 90000;

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
uint8_t recoveryPings = 0;   // consecutive pings heard while in FALLBACK

// Non-zero while a planned shutdown is being honoured. Absolute millis()
// deadline, not a countdown, so it needs no servicing in the loop.
uint32_t shutdownGraceUntilMs = 0;

// Receiver evidence. A deaf radio and a silent transmitter look
// identical from the far end, and that ambiguity has cost more time on
// this project than any actual bug. The receiver now says out loud that
// it is armed and how much it has ever heard, so "nothing arrived" can
// be told apart from "nothing was listening".
uint32_t loraRxTotal = 0;      // every LoRa frame, of any kind
uint32_t loraRxBeacons = 0;    // just the FB| fallback beacons
uint32_t lastLoraStatusMs = 0;
static const uint32_t LORA_STATUS_MS = 30000;
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

// Both data registers hold a 13-bit two's complement value in bits 15:3.
// The sign is load-bearing here (it is what distinguishes charging from
// discharging), so extend it EXPLICITLY rather than relying on ">>" of a
// negative signed value, which is implementation-defined before C++20.
static int16_t ina13Bit(uint16_t raw) {
  int16_t v = (int16_t)((raw >> 3) & 0x1FFF);
  if (v & 0x1000) v -= 0x2000;   // bit 12 set: negative
  return v;
}

// channel: 1..3. Returns false if the chip did not answer, OR if this
// channel has no battery on it, so a caller that gets true always has a
// number worth publishing.
// currentMa is SIGNED: positive discharging, negative charging (see the
// convention above). invert flips a channel whose shunt is wired backwards.
static bool inaReadChannel(uint8_t ch, float& busV, float& currentMa,
                           bool invert = false, bool present = true) {
  if (!present) return false;
  uint16_t rawShunt, rawBus;
  uint8_t shuntReg = 0x01 + 2 * (ch - 1);
  uint8_t busReg = 0x02 + 2 * (ch - 1);
  if (!inaRead16(shuntReg, rawShunt) || !inaRead16(busReg, rawBus)) return false;
  float shuntV = ina13Bit(rawShunt) * 40e-6f;   // LSB 40 uV, may be negative
  busV = ina13Bit(rawBus) * 8e-3f;              // LSB 8 mV
  currentMa = (shuntV / SHUNT_OHMS) * 1000.0f;
  if (invert) currentMa = -currentMa;
  // A grounded or unwired input: report nothing rather than a number that
  // looks like a reading.
  if (busV < BATT_MIN_PLAUSIBLE_V) return false;
  return true;
}

// ---------------------------------------------------------------------------
// BLE advertising (replaces the failed Phase 1 Pi approach, master plan D3)
// ---------------------------------------------------------------------------

static void bleStart() {
  // The 128-bit service UUID MUST go in the ADVERTISEMENT packet, as a
  // "complete list of service UUIDs" (AD type 0x07). Bench finding
  // 2026-07-14: it was previously only present INSIDE the service-data AD
  // structure (type 0x21), and a phone's scan filter
  // (Android ScanFilter.setServiceUuid) matches 0x07, never 0x21. So the
  // filter never fired and the emergency app never saw the module.
  //
  // The filter is not optional: Android refuses UNFILTERED background scans
  // while the screen is off, and a locked phone is exactly the case we need.
  //
  // Legacy advertising gives 31 payload bytes per packet, so we split:
  //   ADV       flags                       1 + 1 + 1        =  3
  //             complete 128-bit UUID list  1 + 1 + 16       = 18
  //                                                     total = 21  (<= 31)
  //   SCAN RSP  service data (128-bit)      1 + 1 + 16 + 10  = 28  (<= 31)
  // The 10 payload bytes are "nodeLetter|ssid" (e.g. "A|RESCUE_A").
  // A local name no longer fits alongside the service data (28 + 10 = 38),
  // so it is dropped: file 03 anticipated exactly this tradeoff. Scanners
  // identify the module by the service UUID, which is what matters.
  String nodeLetter = nodeId.length() ? String(nodeId[nodeId.length() - 1]) : "?";
  String payload = nodeLetter + "|" + apSsid;
  if (payload.length() > 10) payload = payload.substring(0, 10);

  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  advData.setCompleteServices(NimBLEUUID(BLE_SERVICE_UUID));

  NimBLEAdvertisementData scanData;
  scanData.setServiceData(NimBLEUUID(BLE_SERVICE_UUID),
                          std::string(payload.c_str(), payload.length()));

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

// Both batteries: voltage plus SIGNED current (negative while charging).
// A channel the chip cannot answer for reports null rather than 0, so the
// Pi and the apps can tell "no reading" from "no current".
static void sendBattery() {
  JsonDocument doc;
  doc["type"] = "battery";
  float v, ma;
  if (inaOk && inaReadChannel(1, v, ma, BATT_A_SHUNT_INVERT, battAPresent)) {
    doc["bat_a_v"] = v;
    doc["bat_a_ma"] = ma;
  } else {
    doc["bat_a_v"] = nullptr;
    doc["bat_a_ma"] = nullptr;
  }
  if (inaOk && inaReadChannel(2, v, ma, BATT_B_SHUNT_INVERT, battBPresent)) {
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
  // Default true so an existing module behaves exactly as before until
  // somebody tells it otherwise.
  battAPresent = prefs.getBool("batt_a", true);
  battBPresent = prefs.getBool("batt_b", true);
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
    // A ping means the Pi is alive after all, so whatever shutdown it
    // announced either did not happen or it has already come back.
    shutdownGraceUntilMs = 0;
    // In FALLBACK these count toward recovery. Consecutive is the point:
    // the counter resets on the timeout check below, so one stray ping
    // from a Pi that is still flapping cannot pull us back to NORMAL.
    if (mode == Mode::FALLBACK && recoveryPings < 255) recoveryPings++;

  } else if (strcmp(type, "shutdown") == 0) {
    // The Pi is going down on purpose. Do not treat the coming silence as
    // a failure. Acknowledged so the bridge can log that we heard it: a
    // shutdown notice that never arrived is exactly the case where the
    // operator will wonder why the fleet reported a failure anyway.
    shutdownGraceUntilMs = millis() + SHUTDOWN_GRACE_MS;
    JsonDocument ack;
    ack["type"] = "shutdown_ack";
    ack["grace_s"] = SHUTDOWN_GRACE_MS / 1000;
    sendJson(ack);

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

  } else if (strcmp(type, "set_batt_present") == 0) {
    // Tell the module what is physically wired. Persisted, so it survives
    // a power cycle and does not need a rebuild per module.
    if (doc["a"].is<bool>()) {
      battAPresent = doc["a"].as<bool>();
      prefs.putBool("batt_a", battAPresent);
    }
    if (doc["b"].is<bool>()) {
      battBPresent = doc["b"].as<bool>();
      prefs.putBool("batt_b", battBPresent);
    }
    JsonDocument ack;
    ack["type"] = "batt_present_ack";
    ack["a"] = battAPresent;
    ack["b"] = battBPresent;
    sendJson(ack);

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

  loraRxTotal++;

  JsonDocument doc;
  if (payload.startsWith("FB|")) {
    loraRxBeacons++;
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
  bool haveA = inaOk && inaReadChannel(1, aV, aMa, BATT_A_SHUNT_INVERT, battAPresent);
  bool haveB = inaOk && inaReadChannel(2, bV, bMa, BATT_B_SHUNT_INVERT, battBPresent);
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
  // Signed, so a node beaconing while on charge sends a negative figure
  // here. String(float, 0) keeps the minus sign; the Pi parses with float().
  beacon += haveB ? String(bMa, 0) : "";
  beacon += "|" + cachedMsgId + "|" + cachedMsgContent + "|" + cachedMsgTime + "|DOWN";

  if (beacon.length() > 255) beacon = beacon.substring(0, 255);
  LoRa.beginPacket();
  LoRa.print(beacon);
  LoRa.endPacket();

  // Announce it on the serial line as well as the radio. During a real
  // failure the Pi is dead and nobody reads this, but it is what makes a
  // BENCH test conclusive: plug the module into a laptop, watch
  // "pio device monitor", and you can see it enter fallback and transmit
  // rather than guessing whether the silence is the module or the radio.
  static uint32_t beaconCount = 0;
  beaconCount++;
  JsonDocument sent;
  sent["type"] = "beacon_sent";
  sent["n"] = beaconCount;
  sent["len"] = beacon.length();
  sendJson(sent);
}

// ---------------------------------------------------------------------------
// Setup / loop
// ---------------------------------------------------------------------------

// Announce which part of startup we are about to attempt.
//
// This exists because the module was completely silent on a bench and
// there was no way to tell whether it had crashed, hung, or simply had
// nothing to say. The first output used to be the "boot" summary at the
// very END of setup, after NVS, I2C, SPI, the LoRa radio and the whole
// BLE stack. Anything that hung in there produced no output at all, and
// a silent module is indistinguishable from a dead one.
//
// Now every step announces itself first, so silence has an address: the
// last stage printed is the one that did not return.
static void stage(const char* name) {
  JsonDocument doc;
  doc["type"] = "stage";
  doc["at"] = name;
  doc["ms"] = millis();
  sendJson(doc);
}

void setup() {
  Serial.begin(115200);  // native USB CDC to the Pi

  // NEVER block on a serial write. This is a correctness requirement for
  // the whole fallback feature, not a tuning knob.
  //
  // On native USB, a write goes into a buffer the HOST drains. When the
  // Pi dies, which is exactly the case this module exists to survive,
  // there is no host and nothing drains it. With the default timeout,
  // every telemetry write then stalls the loop for as long as the
  // timeout, five seconds after the Pi dies and every five seconds
  // after that. The module can end up spending its time blocked on
  // writes nobody will ever read, at the precise moment it is supposed
  // to be noticing the Pi is gone and beaconing over LoRa.
  //
  // Zero makes writes non-blocking: they are discarded when no host is
  // attached. Losing telemetry to a dead Pi costs nothing, because the
  // dead Pi was the only reader. The LoRa beacon does not go through
  // here and is unaffected.
  Serial.setTxTimeoutMs(0);

  // Native USB enumerates AFTER the sketch starts, so anything written
  // before the host attaches is simply discarded. Wait briefly for it.
  // Bounded, because on a real node the Pi may not have opened the port
  // yet and the module must never wait on a host that is not coming.
  const uint32_t usbWaitStart = millis();
  while (!Serial && millis() - usbWaitStart < 2000) {
    delay(10);
  }

  bootMs = millis();
  // A Pi that boots slowly must not be declared dead instantly: require
  // the FIRST ping within FIRST_PING_GRACE_MS, then apply the 15 s rule.
  lastPingMs = bootMs;

  // Proof of life before anything that can block. If you see this and
  // nothing else, the firmware is running and a peripheral is at fault.
  stage("alive");

  stage("nvs");
  loadCache();

  stage("gps_serial");
  Serial1.begin(9600, SERIAL_8N1, PIN_GPS_RX, PIN_GPS_TX);

  stage("i2c");
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  inaOk = inaInit();

  stage("lora");
  loraSPI.begin(PIN_LORA_SCK, PIN_LORA_MISO, PIN_LORA_MOSI, PIN_LORA_CS);
  LoRa.setSPI(loraSPI);
  LoRa.setPins(PIN_LORA_CS, PIN_LORA_RST, PIN_LORA_DIO0);
  loraOk = LoRa.begin(LORA_FREQ);
  if (loraOk) {
    LoRa.setTxPower(LORA_TX_POWER_DBM);
    LoRa.setSpreadingFactor(7);
    LoRa.setSignalBandwidth(125E3);
  }

  stage("ble");
  NimBLEDevice::init("");
  bleStart();

  JsonDocument doc;
  doc["type"] = "boot";
  doc["node_id"] = nodeId;
  doc["lora"] = loraOk;
  doc["ina3221"] = inaOk;
  doc["batt_a_present"] = battAPresent;
  doc["batt_b_present"] = battBPresent;
  doc["boot_ms"] = millis();
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

    // Prove the receiver is alive and armed, whether or not anything has
    // arrived. Without this a working-but-lonely receiver is
    // indistinguishable from a dead one.
    if (now - lastLoraStatusMs >= LORA_STATUS_MS) {
      lastLoraStatusMs = now;
      JsonDocument st;
      st["type"] = "lora_status";
      st["ok"] = loraOk;
      st["rx_total"] = loraRxTotal;
      st["rx_beacons"] = loraRxBeacons;
      sendJson(st);
    }

    // An announced shutdown suppresses the transition, but only until the
    // grace window expires. See SHUTDOWN_GRACE_MS on why it is bounded.
    if (shutdownGraceUntilMs != 0) {
      if ((int32_t)(now - shutdownGraceUntilMs) < 0) return;
      shutdownGraceUntilMs = 0;  // window expired, resume normal behaviour
    }

    uint32_t timeout = firstPingSeen ? PING_TIMEOUT_MS : FIRST_PING_GRACE_MS;
    if (now - lastPingMs > timeout) {
      mode = Mode::FALLBACK;
      recoveryPings = 0;
      bleStop();  // conserve Battery B (design v3)
      lastBeaconMs = 0;  // beacon immediately
      JsonDocument doc;
      doc["type"] = "fallback_enter";
      sendJson(doc);
    }
  } else {  // FALLBACK
    // Any gap longer than the dead-Pi timeout means the pings were not
    // consecutive after all, so recovery progress is discarded.
    if (now - lastPingMs > PING_TIMEOUT_MS) recoveryPings = 0;

    if (!FALLBACK_IS_TERMINAL && recoveryPings >= FALLBACK_RECOVERY_PINGS) {
      // The Pi is back and has stayed back. Stop beaconing, resume BLE and
      // the sensor feed, and tell the Pi so it can log the recovery.
      mode = Mode::NORMAL;
      recoveryPings = 0;
      lastSensorSendMs = 0;   // send fresh gps + battery immediately
      bleStart();
      JsonDocument doc;
      doc["type"] = "fallback_exit";
      sendJson(doc);
      return;
    }

    if (lastBeaconMs == 0 || now - lastBeaconMs >= FALLBACK_BEACON_MS) {
      lastBeaconMs = now;
      sendFallbackBeacon();
    }
  }
}
