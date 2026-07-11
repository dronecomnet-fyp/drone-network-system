#!/usr/bin/env python3
"""
aux_sim.py: bench-side simulator of the Pi for the aux module serial
protocol (file 03 test 2; also useful against aux_bridge.py with a pty).

Connect the XIAO over USB and run:

    python3 tools/aux_sim.py --port /dev/ttyACM0

It pings every 5 s (like aux_bridge), pretty-prints every JSON line the
module sends, and takes interactive commands:

    p                  send one ping now
    stop               stop automatic pings (triggers fallback in 15 s)
    start              resume automatic pings
    m <text>           send last_msg with the given content
    l <payload>        send lora_tx
    b <node_id> <ssid> send ble_update
    n <node_id>        send set_node_id (per-board provisioning)
    raw <json>         send a raw JSON line
    q                  quit

--log FILE appends every received line as JSON-lines (test 6 logging).
"""

import argparse
import json
import sys
import threading
import time
import uuid
from datetime import datetime, timezone

try:
    import serial
except ImportError:
    print("pyserial required: pip install pyserial")
    sys.exit(1)


def iso_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class AuxSim:
    def __init__(self, port, baud, log_path):
        self.ser = serial.Serial(port, baud, timeout=0.5)
        self.pinging = True
        self.log = open(log_path, "a") if log_path else None
        self.running = True

    def send(self, obj):
        line = json.dumps(obj, separators=(",", ":"))
        self.ser.write((line + "\n").encode())
        print(f"  -> {line}")

    def reader(self):
        while self.running:
            try:
                raw = self.ser.readline().decode(errors="replace").strip()
            except (OSError, serial.SerialException):
                print("[serial gone]")
                self.running = False
                return
            if not raw:
                continue
            try:
                obj = json.loads(raw)
                print(f"<- {json.dumps(obj, indent=None)}")
            except json.JSONDecodeError:
                print(f"<- (not json) {raw!r}")
                obj = {"raw": raw}
            if self.log:
                self.log.write(json.dumps({"ts": iso_now(), "line": obj}) + "\n")
                self.log.flush()

    def pinger(self):
        while self.running:
            if self.pinging:
                self.send({"type": "ping"})
            time.sleep(5)

    def repl(self):
        print(__doc__)
        while self.running:
            try:
                cmd = input().strip()
            except (EOFError, KeyboardInterrupt):
                self.running = False
                return
            if not cmd:
                continue
            parts = cmd.split(" ", 1)
            op = parts[0]
            arg = parts[1] if len(parts) > 1 else ""
            if op == "q":
                self.running = False
            elif op == "p":
                self.send({"type": "ping"})
            elif op == "stop":
                self.pinging = False
                print("[pings stopped: fallback expected in ~15 s]")
            elif op == "start":
                self.pinging = True
            elif op == "m":
                self.send({"type": "last_msg", "msg_id": str(uuid.uuid4())[:8],
                           "content": arg or "test message", "timestamp": iso_now()})
            elif op == "l":
                self.send({"type": "lora_tx", "payload": arg or "hello-bench"})
            elif op == "b":
                bits = arg.split()
                node = bits[0] if bits else "DRONE_A"
                ssid = bits[1] if len(bits) > 1 else "RESCUE_A"
                self.send({"type": "ble_update", "node_id": node, "ssid": ssid})
            elif op == "n":
                self.send({"type": "set_node_id", "node_id": arg or "DRONE_A"})
            elif op == "raw":
                try:
                    self.send(json.loads(arg))
                except json.JSONDecodeError:
                    print("[not valid json]")
            else:
                print("[unknown command; p/stop/start/m/l/b/n/raw/q]")


def main():
    ap = argparse.ArgumentParser(description="Aux module protocol simulator")
    ap.add_argument("--port", required=True, help="serial port, e.g. /dev/ttyACM0")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--log", default="", help="append received lines to this JSONL file")
    args = ap.parse_args()

    sim = AuxSim(args.port, args.baud, args.log)
    threading.Thread(target=sim.reader, daemon=True).start()
    threading.Thread(target=sim.pinger, daemon=True).start()
    try:
        sim.repl()
    finally:
        sim.running = False
        time.sleep(0.2)


if __name__ == "__main__":
    main()
