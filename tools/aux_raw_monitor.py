#!/usr/bin/env python3
"""
aux_raw_monitor.py: print exactly what the aux module is sending, with
nothing in between.

Run on a node:
    sudo systemctl stop rescue-mesh-auxbridge
    python3 tools/aux_raw_monitor.py
    (Ctrl+C to stop, then start the bridge again)

Why this exists. A module went silent on a Windows serial monitor after a
successful flash and a confirmed reset, and there was no way to tell
whether the firmware was dead or the host was at fault. This reads the
same port the bridge reads, using the same library, so it settles that
question with the hardware already in the field.

It parses nothing and interprets nothing. Whatever arrives is printed.
"""

import sys
import time

sys.path.insert(0, "backend")

try:
    import serial  # noqa: E402
except ImportError:
    print("pyserial missing. Run this from the repo root so it picks up")
    print("the backend virtualenv, or: backend/.venv/bin/python "
          "tools/aux_raw_monitor.py")
    raise SystemExit(1)

import config  # noqa: E402

PORT = config.AUX_SERIAL or "/dev/ttyACM0"


def main():
    print(f"Opening {PORT} at 115200. Ctrl+C to stop.")
    print("If the bridge is still running it holds the port and this will")
    print("fail: sudo systemctl stop rescue-mesh-auxbridge\n")
    try:
        # dtr True is what pyserial does by default and what the bridge
        # therefore does too. Stated explicitly because whether DTR is
        # asserted is exactly the thing under suspicion when a monitor on
        # another machine shows nothing.
        ser = serial.Serial(PORT, 115200, timeout=1)
        ser.dtr = True
    except Exception as e:  # noqa: BLE001
        print(f"Could not open {PORT}: {e}")
        return 1

    print("Port open. Press the RESET button on the module now.\n")
    started = time.time()
    lines = 0
    try:
        while True:
            raw = ser.readline()
            if not raw:
                waited = int(time.time() - started)
                if waited and waited % 10 == 0 and lines == 0:
                    print(f"  ... {waited}s, nothing received yet")
                    time.sleep(1)
                continue
            lines += 1
            text = raw.decode(errors="backslashreplace").rstrip()
            print(f"[{time.time() - started:6.1f}s] {text}")
    except KeyboardInterrupt:
        pass
    finally:
        ser.close()

    print(f"\n{lines} lines in {int(time.time() - started)}s.")
    if lines == 0:
        print("\nNothing at all. The module is not sending on this port.")
        print("  - Is it the right port? ls -l /dev/ttyACM*")
        print("  - Reflash it, then press RESET with this running.")
        print("  - If a laptop monitor is also silent, the firmware is not")
        print("    running and the fault is on the module, not the host.")
    else:
        print("\nThe module IS talking. If a laptop monitor showed nothing,")
        print("the fault is that host's serial setup, not the firmware.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
