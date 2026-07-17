#!/usr/bin/env python3
"""
mav_gateway.py: the system drone (DRONE_S) MAVLink gateway (file 08).

Runs on the Pi 4 mounted on the AeroSync 5. The Pi connects to the CC3D
Revo Mini flight controller over a serial wire (the ESP32 DroneBridge is
removed: the Pi is the companion computer now, and no reflash is needed).
This gateway does two jobs at once:

  1. CONTROL BRIDGE (transparent). It forwards raw MAVLink bytes both ways
     between the FC serial link and a UDP endpoint on 0.0.0.0:14550. The
     GCC reaches it two ways, both LIVE (never store-and-forward, per the
     file 08 rule that flight commands only travel over a live link):
       - direct: laptop on RESCUE_S -> 10.42.0.1:14550
       - relay:  laptop on RESCUE_A/B -> volunteer Pi forwards -> mesh ->
                 10.99.0.3:14550
     Raw bytes are forwarded unmodified so a command is never corrupted.

  2. TELEMETRY TAP (read-only). It parses a COPY of the FC->GCC stream to
     harvest the drone's own sensors, since DRONE_S has no aux module
     (no INA3221, no LoRa, no separate GPS): the GPS is on the CC3D.
       - GPS_RAW_INT  -> position + fix + satellites into /health
       - SYS_STATUS   -> flight-battery voltage into /health
       - SYSTEM_TIME  -> set the Pi clock from GPS time (no RTC/NTP in the
                         field, master plan R5), once then hourly, via the
                         same narrow sudoers date command aux_bridge uses.
     Results are written to AUX_STATE_FILE in the schema api.py's /health
     reads (kept in step with backend/aux_state.py; see _write_state).

Config comes from /etc/rescue-mesh/node.env (systemd EnvironmentFile) or
the process environment. Self-contained: stdlib + pyserial + pymavlink.
"""

import json
import os
import select
import shlex
import socket
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import serial  # pyserial
from pymavlink import mavutil


def _env(name, default=""):
    return os.environ.get(name, default)


def _int(name, default):
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError:
        return default


NODE_ID = _env("NODE_ID", "DRONE_S")
FC_SERIAL = _env("FC_SERIAL", "/dev/serial0")
FC_BAUD = _int("FC_BAUD", 57600)
UDP_BIND = _env("MAVLINK_BIND", "0.0.0.0")
UDP_PORT = _int("MAVLINK_UDP_PORT", 14550)
AUX_STATE_FILE = _env("AUX_STATE_FILE", "/run/rescue-mesh/aux_state.json")
CLOCK_RESYNC_INTERVAL = _int("CLOCK_RESYNC_INTERVAL", 3600)
STATE_FLUSH_INTERVAL = _int("MAVGW_STATE_FLUSH_INTERVAL", 5)
# Drop a UDP client we have not heard from in this long (a GCS that left).
CLIENT_EXPIRY = _int("MAVGW_CLIENT_EXPIRY", 30)
# Same sudoers-backed command aux_bridge uses; deploy grants exactly this.
DATE_SET_CMD = _env("DATE_SET_CMD", "sudo -n /bin/date -u -s {utc}")

AUDIT_LOG_FILE = _env("AUDIT_LOG_FILE", "audit.log")


def audit(line):
    """Append one line to the shared audit log (best effort)."""
    try:
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        with open(AUDIT_LOG_FILE, "a") as f:
            f.write(f"{ts} | INFO | {line}\n")
    except OSError:
        pass


class Gateway:
    def __init__(self):
        self.ser = None
        self.sock = None
        self.clients = {}  # addr -> last_seen monotonic
        # aux_state mirror (schema matches backend/aux_state.py DEFAULT_STATE).
        self.state = {
            "aux_present": False,  # no aux MODULE on DRONE_S; GPS is the FC's
            "node_id": NODE_ID,
            "gps": {"lat": None, "lon": None, "fix": 0, "sats": 0, "hdop": None},
            "battery": {"a_v": None, "a_ma": None, "b_v": None, "b_ma": None},
            "gps_time_applied": False,
            "clock_source": "relative",
            "last_rx_ts": None,
            "fc_link": False,
        }
        # Parser for the read-only telemetry tap. srcSystem 0 = listen-only.
        self.mav = mavutil.mavlink.MAVLink(None)
        self.mav.robust_parsing = True
        self.clock_synced_once = False
        self.last_clock_sync = 0.0
        self.last_flush = 0.0
        self.dirty = True

    # -- serial plumbing ------------------------------------------------------

    def open_serial(self):
        backoff = 2
        while True:
            try:
                self.ser = serial.Serial(FC_SERIAL, FC_BAUD, timeout=0)
                self.state["fc_link"] = True
                self._flush_state(force=True)
                audit(f"MAVGW_FC_CONNECT | port={FC_SERIAL} | baud={FC_BAUD}")
                return
            except (serial.SerialException, OSError):
                self.state["fc_link"] = False
                self._flush_state(force=True)
                time.sleep(backoff)
                backoff = min(backoff * 2, 30)

    def open_socket(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((UDP_BIND, UDP_PORT))
        self.sock.setblocking(False)

    # -- forwarding -----------------------------------------------------------

    def _forward_to_clients(self, data):
        now = time.monotonic()
        dead = [a for a, t in self.clients.items() if now - t > CLIENT_EXPIRY]
        for a in dead:
            del self.clients[a]
        for addr in self.clients:
            try:
                self.sock.sendto(data, addr)
            except OSError:
                pass

    def _on_serial(self):
        try:
            data = self.ser.read(4096)
        except (serial.SerialException, OSError):
            raise ConnectionError("serial read failed")
        if not data:
            return
        # 1. transparent control path: raw bytes straight to every GCS.
        self._forward_to_clients(data)
        # 2. telemetry tap: parse a copy, never blocking the control path.
        try:
            msgs = self.mav.parse_buffer(data) or []
        except Exception:  # noqa: BLE001  a bad byte must not kill the bridge
            msgs = []
        for m in msgs:
            self._tap(m)

    def _on_udp(self):
        try:
            data, addr = self.sock.recvfrom(4096)
        except OSError:
            return
        self.clients[addr] = time.monotonic()
        if self.ser is not None:
            try:
                self.ser.write(data)
            except (serial.SerialException, OSError):
                raise ConnectionError("serial write failed")

    # -- telemetry tap --------------------------------------------------------

    def _tap(self, m):
        t = m.get_type()
        if t == "GPS_RAW_INT":
            fix = 1 if m.fix_type >= 3 else 0
            self.state["gps"] = {
                "lat": m.lat / 1e7 if m.lat != 0 else None,
                "lon": m.lon / 1e7 if m.lon != 0 else None,
                "fix": fix,
                "sats": m.satellites_visible,
                "hdop": (m.eph / 100.0) if getattr(m, "eph", 0) not in (0, 65535) else None,
            }
            self.dirty = True
        elif t == "SYS_STATUS":
            mv = m.voltage_battery
            self.state["battery"]["a_v"] = None if mv in (0, 65535) else mv / 1000.0
            ci = m.current_battery
            self.state["battery"]["a_ma"] = None if ci == -1 else ci * 10.0
            self.dirty = True
        elif t == "SYSTEM_TIME":
            self._maybe_set_clock(m.time_unix_usec)

    def _maybe_set_clock(self, unix_usec):
        # The FC only has a real unix time once its GPS has time. 1.5e18 usec
        # is well past 2017, a sane floor to reject boot-time zero/garbage.
        if unix_usec < 1_500_000_000_000_000:
            return
        now_mono = time.monotonic()
        due = (not self.clock_synced_once
               or now_mono - self.last_clock_sync >= CLOCK_RESYNC_INTERVAL)
        if not due:
            return
        utc = datetime.fromtimestamp(unix_usec / 1e6, tz=timezone.utc)
        utc_str = utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        old = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        cmd = [p.replace("{utc}", utc_str) for p in shlex.split(DATE_SET_CMD)]
        try:
            subprocess.run(cmd, check=True, capture_output=True, timeout=10)
        except (subprocess.SubprocessError, OSError) as e:
            audit(f"MAVGW_CLOCK_FAIL | reason={type(e).__name__}")
            return
        self.clock_synced_once = True
        self.last_clock_sync = now_mono
        self.state["gps_time_applied"] = True
        self.state["clock_source"] = "gps"
        self.dirty = True
        audit(f"CLOCK_SYNC | src=fc_mavlink | old={old} | new={utc_str}")

    # -- state file -----------------------------------------------------------

    def _flush_state(self, force=False):
        now = time.monotonic()
        if not force:
            if not self.dirty:
                return
            if now - self.last_flush < STATE_FLUSH_INTERVAL:
                return
        self.state["last_rx_ts"] = datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%S.%fZ")
        path = Path(AUX_STATE_FILE)
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".aux_state_")
            with os.fdopen(fd, "w") as f:
                json.dump(self.state, f)
            os.replace(tmp, path)
        except OSError:
            pass
        self.last_flush = now
        self.dirty = False

    # -- main loop ------------------------------------------------------------

    def run(self):
        self.open_socket()
        audit(f"MAVGW_START | node={NODE_ID} | udp={UDP_BIND}:{UDP_PORT}")
        while True:
            self.open_serial()
            try:
                while True:
                    rlist, _, _ = select.select(
                        [self.ser.fileno(), self.sock.fileno()], [], [], 1.0)
                    if self.ser.fileno() in rlist:
                        self._on_serial()
                    if self.sock.fileno() in rlist:
                        self._on_udp()
                    self._flush_state()
            except ConnectionError:
                audit("MAVGW_FC_DISCONNECT")
                self.state["fc_link"] = False
                self.state["clock_source"] = "relative"
                self._flush_state(force=True)
                try:
                    self.ser.close()
                except (serial.SerialException, OSError):
                    pass


def main():
    if not FC_SERIAL:
        print("[*] FC_SERIAL empty: no flight controller on this node, "
              "gateway not needed. Exiting cleanly.")
        audit("MAVGW_SKIP | reason=no_fc_serial")
        sys.exit(0)
    Gateway().run()


if __name__ == "__main__":
    main()
