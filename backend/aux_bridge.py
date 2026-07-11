"""
aux_bridge.py: the Pi side of the design v3 serial protocol (file 02 task
2.2). Runs as rescue-mesh-auxbridge.service. Speaks newline-delimited JSON
both directions with the ESP32-C3 aux module on AUX_SERIAL at 115200.

If AUX_SERIAL is empty (DRONE_S flies without an aux module, file 08), the
service writes an "aux absent" state file and exits cleanly; everything
else on the node works unchanged with time_source staying "relative".

Inbound (module -> Pi):
  gps          cache latest fix; goes into aux_state and health snapshots
  gps_time     set the system clock ONCE at startup then re-sync every
               CLOCK_RESYNC_INTERVAL (design v3 3.3) via the narrow sudoers
               date command; every sync is audit-logged with old/new time
  battery      cache for the next health snapshot
  fallback_rx  another node's LoRa fallback beacon: store a node_health row
               with degraded=1 for the REPORTING node and audit-log it
  lora_rx      non-fallback LoRa traffic: log only
  last_msg_ack cache acknowledgement: log at debug level

Outbound (Pi -> module):
  ping         every AUX_PING_INTERVAL (5 s); the module declares the Pi
               dead after 15 s without pings and enters fallback (file 03)
  ble_update   once per (re)connect: node_id + SSID for BLE advertising
  last_msg     newest message (content <= 100 chars, pipes stripped) when a
               new row appears; polled by rowid every NEW_MSG_POLL_INTERVAL
  lora_tx      periodic status summary relayed over LoRa. Interval and
               format: LORA_SUMMARY_INTERVAL, payload
               "SUM|node_id|msg_count|ts". Design v3 step 6 describes LoRa
               summary forwarding; the exact payload format there should be
               cross-checked against the design doc during bench testing
               (estimate to verify, project rule 1).
"""

import json
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone

import serial  # pyserial

import audit
import aux_state
import config
import models

audit_logger = audit.get_audit_logger()


def _uptime_s() -> int:
    try:
        with open("/proc/uptime") as f:
            return int(float(f.read().split()[0]))
    except (OSError, ValueError, IndexError):
        return 0


class AuxBridge:
    def __init__(self):
        self.ser = None
        self.state = dict(aux_state.DEFAULT_STATE)
        self.state["node_id"] = config.NODE_ID
        self.last_ping = 0.0
        self.last_health = 0.0
        self.last_clock_sync = 0.0
        self.clock_synced_once = False
        self.last_msg_rowid = models.latest_message_rowid()
        self.last_msg_poll = 0.0
        self.last_lora_summary = time.monotonic()

    # -- serial plumbing ----------------------------------------------------

    def connect(self):
        """Reconnect loop with backoff (file 02: reconnect if the port
        disappears; acceptance 3 requires recovery without a restart)."""
        backoff = 2
        while True:
            try:
                self.ser = serial.Serial(config.AUX_SERIAL, config.AUX_BAUD, timeout=1)
                audit_logger.info(f"AUX_CONNECT | port={config.AUX_SERIAL}")
                self.state["aux_present"] = True
                self._write_state()
                self.send({"type": "ble_update", "node_id": config.NODE_ID,
                           "ssid": config.USER_AP_SSID})
                return
            except (serial.SerialException, OSError):
                if self.state.get("aux_present"):
                    audit_logger.warning("AUX_DISCONNECT | reason=open_failed")
                self.state["aux_present"] = False
                self._write_state()
                time.sleep(backoff)
                backoff = min(backoff * 2, 30)

    def send(self, obj: dict):
        try:
            self.ser.write((json.dumps(obj, separators=(",", ":")) + "\n").encode())
        except (serial.SerialException, OSError):
            raise ConnectionError("serial write failed")

    def _write_state(self):
        self.state["last_rx_ts"] = models.iso_now()
        aux_state.write_state(self.state)

    # -- inbound handlers -----------------------------------------------------

    def handle_line(self, line: str):
        line = line.strip()
        if not line:
            return
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            return
        mtype = msg.get("type", "")
        if mtype == "gps":
            self.state["gps"] = {
                "lat": msg.get("lat"),
                "lon": msg.get("lon"),
                "fix": msg.get("fix", 0),
                "sats": msg.get("sats", 0),
                "hdop": msg.get("hdop"),
            }
            self._write_state()
        elif mtype == "battery":
            self.state["battery"] = {
                "a_v": msg.get("bat_a_v"),
                "a_ma": msg.get("bat_a_ma"),
                "b_v": msg.get("bat_b_v"),
                "b_ma": msg.get("bat_b_ma"),
            }
            self._write_state()
        elif mtype == "gps_time":
            self.handle_gps_time(msg)
        elif mtype == "fallback_rx":
            self.handle_fallback_rx(msg)
        elif mtype == "lora_rx":
            audit_logger.info(
                f"LORA_RX | rssi={msg.get('rssi')} | snr={msg.get('snr')} | "
                f"len={len(str(msg.get('payload', '')))}"
            )
        elif mtype == "last_msg_ack":
            pass  # cache acknowledged; nothing to persist

    def handle_gps_time(self, msg: dict):
        """Set the system clock from GPS once at startup, then re-sync every
        CLOCK_RESYNC_INTERVAL (design v3 3.3, master plan R5: no RTC, no NTP
        in the field). Uses the narrow sudoers entry installed by deploy/."""
        if not msg.get("fix"):
            return
        utc = msg.get("utc", "")
        if not utc:
            return
        now_mono = time.monotonic()
        due = (not self.clock_synced_once
               or now_mono - self.last_clock_sync >= config.CLOCK_RESYNC_INTERVAL)
        if not due:
            return
        old = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        cmd = [part.replace("{utc}", utc) for part in shlex.split(config.DATE_SET_CMD)]
        try:
            subprocess.run(cmd, check=True, capture_output=True, timeout=10)
        except (subprocess.SubprocessError, OSError) as e:
            audit_logger.warning(f"CLOCK_SYNC_FAIL | reason={type(e).__name__}")
            return
        self.clock_synced_once = True
        self.last_clock_sync = now_mono
        self.state["gps_time_applied"] = True
        self.state["clock_source"] = "gps"
        self._write_state()
        audit_logger.info(f"CLOCK_SYNC | old={old} | new={utc} | sats={msg.get('sats')}")

    def handle_fallback_rx(self, msg: dict):
        """A LoRa fallback beacon from another node whose Pi died (design v3
        step 8). Format (file 03): FB|node_id|lat|lon|gps_fix|utc|bat_a_v|
        bat_a_mA|bat_b_v|bat_b_mA|msg_id|msg_content|msg_time|DOWN"""
        raw = msg.get("raw", "")
        parts = raw.split("|")
        if len(parts) < 14 or parts[0] != "FB":
            audit_logger.warning("FALLBACK_RX_MALFORMED")
            return

        def _f(idx):
            try:
                return float(parts[idx])
            except (ValueError, IndexError):
                return None

        node_id = parts[1]
        models.save_node_health(
            node_id=node_id,
            lat=_f(2), lon=_f(3),
            gps_fix=int(_f(4) or 0),
            bat_a_v=_f(6), bat_a_ma=_f(7), bat_b_v=_f(8), bat_b_ma=_f(9),
            clock_source="gps" if parts[5] else "relative",
            degraded=1,
        )
        audit_logger.warning(
            f"FALLBACK_BEACON | node={node_id} | rssi={msg.get('rssi')} | "
            f"last_msg={parts[10]}"
        )

    # -- outbound timers ------------------------------------------------------

    def tick(self):
        now = time.monotonic()
        if now - self.last_ping >= config.AUX_PING_INTERVAL:
            self.send({"type": "ping"})
            self.last_ping = now
        if now - self.last_health >= config.HEALTH_SNAPSHOT_INTERVAL:
            gps = self.state["gps"]
            bat = self.state["battery"]
            models.save_node_health(
                node_id=config.NODE_ID,
                lat=gps["lat"], lon=gps["lon"], gps_fix=gps["fix"],
                bat_a_v=bat["a_v"], bat_a_ma=bat["a_ma"],
                bat_b_v=bat["b_v"], bat_b_ma=bat["b_ma"],
                uptime_s=_uptime_s(),
                clock_source=self.state["clock_source"],
                degraded=0,
            )
            self.last_health = now
        if now - self.last_msg_poll >= config.NEW_MSG_POLL_INTERVAL:
            self.push_new_message()
            self.last_msg_poll = now
        if now - self.last_lora_summary >= config.LORA_SUMMARY_INTERVAL:
            counts = models.message_counts()
            total = sum(counts.values())
            self.send({"type": "lora_tx",
                       "payload": f"SUM|{config.NODE_ID}|{total}|{models.iso_now()}"})
            self.last_lora_summary = now

    def push_new_message(self):
        """Forward the newest message to the module's flash cache so the
        fallback beacon can carry it after a Pi failure (design v3 layer 8)."""
        row = models.get_message_after_rowid(self.last_msg_rowid)
        if not row:
            return
        content = (row.get("content") or "").replace("|", " ")[:100]
        self.send({
            "type": "last_msg",
            "msg_id": row["msg_id"],
            "content": content,
            "timestamp": row.get("timestamp", ""),
        })
        self.last_msg_rowid = row["rid"]

    # -- main loop ------------------------------------------------------------

    def run(self):
        self._write_state()
        while True:
            self.connect()
            try:
                while True:
                    try:
                        line = self.ser.readline().decode(errors="replace")
                    except (serial.SerialException, OSError):
                        raise ConnectionError("serial read failed")
                    if line:
                        self.handle_line(line)
                    self.tick()
            except ConnectionError:
                audit_logger.warning("AUX_DISCONNECT | reason=io_error")
                self.state["aux_present"] = False
                self._write_state()
                try:
                    self.ser.close()
                except (serial.SerialException, OSError):
                    pass


def main():
    if not config.AUX_SERIAL:
        # DRONE_S case (file 08): no aux module, exit cleanly, /health will
        # report aux absent from the state file written here.
        state = dict(aux_state.DEFAULT_STATE)
        state["node_id"] = config.NODE_ID
        aux_state.write_state(state)
        print("[*] AUX_SERIAL empty: no aux module on this node, exiting cleanly.")
        audit_logger.info("AUX_BRIDGE_SKIP | reason=no_aux_serial_configured")
        sys.exit(0)
    # init_db BEFORE constructing the bridge: __init__ reads the messages
    # table for the last rowid, which must exist on a fresh node.
    models.init_db()
    AuxBridge().run()


if __name__ == "__main__":
    main()
