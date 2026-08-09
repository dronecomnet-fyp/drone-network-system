#!/usr/bin/env python3
"""
aux_set_battery.py: tell an aux module which batteries are actually wired.

    sudo systemctl stop rescue-mesh-auxbridge
    backend/.venv/bin/python tools/aux_set_battery.py --a yes --b no
    sudo systemctl start rescue-mesh-auxbridge

Why this is needed rather than inferred. An unconnected INA3221 input
floats near the supply rail and reads about 4.18 V with a little drift,
which by voltage alone is indistinguishable from a healthy full cell. The
firmware cannot work out that a battery is missing; it has to be told.

The setting is stored on the module and survives a power cycle, so this
is a one-off per module rather than part of any routine.
"""

import argparse
import json
import sys
import time

sys.path.insert(0, "backend")

try:
    import serial
except ImportError:
    print("Run with the backend virtualenv:")
    print("  backend/.venv/bin/python tools/aux_set_battery.py --a yes --b no")
    raise SystemExit(1)

import config  # noqa: E402


def yesno(v):
    v = v.strip().lower()
    if v in ("yes", "y", "true", "1", "on"):
        return True
    if v in ("no", "n", "false", "0", "off"):
        return False
    raise argparse.ArgumentTypeError(f"expected yes or no, got {v!r}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a", type=yesno, required=True,
                    help="is Battery A wired to INA3221 channel 1?")
    ap.add_argument("--b", type=yesno, required=True,
                    help="is Battery B wired to INA3221 channel 2?")
    ap.add_argument("--port", default=config.AUX_SERIAL or "/dev/ttyACM0")
    args = ap.parse_args()

    print(f"{args.port}: Battery A {'wired' if args.a else 'NOT fitted'}, "
          f"Battery B {'wired' if args.b else 'NOT fitted'}")
    try:
        ser = serial.Serial(args.port, 115200, timeout=2)
    except Exception as e:  # noqa: BLE001
        print(f"Could not open {args.port}: {e}")
        print("Is the bridge still running? "
              "sudo systemctl stop rescue-mesh-auxbridge")
        return 1

    time.sleep(0.3)
    ser.write((json.dumps({"type": "set_batt_present",
                           "a": args.a, "b": args.b}) + "\n").encode())
    ser.flush()

    deadline = time.time() + 5
    while time.time() < deadline:
        line = ser.readline().decode(errors="replace").strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("type") == "batt_present_ack":
            print(f"Module confirmed: A={msg.get('a')}  B={msg.get('b')}")
            print("Stored on the module. Start the bridge again.")
            ser.close()
            return 0

    ser.close()
    print("No acknowledgement in 5 s.")
    print("Old firmware will ignore this command: reflash the module first.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
