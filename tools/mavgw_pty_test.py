#!/usr/bin/env python3
"""
mavgw_pty_test.py: exercise mavlink_gateway/mav_gateway.py against a fake
flight controller on a pty and a fake GCS on a UDP socket, no hardware
(file 08 local verification).

Covers:
  - FC serial bytes are forwarded verbatim to a UDP GCS (control telemetry
    path, and proves the transparent bridge does not corrupt bytes)
  - GCS UDP bytes are forwarded verbatim to the FC serial (command path)
  - the telemetry tap decodes GPS_RAW_INT and SYS_STATUS into aux_state.json
  - SYSTEM_TIME triggers the (mocked) clock-set command and flips
    clock_source to gps

Usage: backend/.venv/bin/python tools/mavgw_pty_test.py
"""

import json
import os
import pathlib
import pty
import socket
import subprocess
import sys
import tempfile
import time

REPO = pathlib.Path(__file__).resolve().parents[1]
GW = REPO / "mavlink_gateway" / "mav_gateway.py"
PY = str(REPO / "backend" / ".venv" / "bin" / "python")

from pymavlink import mavutil  # noqa: E402  (after path setup is fine here)

failures = []


def check(name, ok):
    print(("  ok: " if ok else "FAIL: ") + name)
    if not ok:
        failures.append(name)


def main():
    work = pathlib.Path(tempfile.mkdtemp(prefix="mavgw_test_"))
    date_marker = work / "date_set.txt"
    mock_date = work / "mock_date.py"
    mock_date.write_text(
        "import sys, pathlib\n"
        f"pathlib.Path(r'{date_marker}').write_text(' '.join(sys.argv[1:]))\n")
    date_wrapper = work / "mock_date.sh"
    date_wrapper.write_text(f'#!/bin/sh\nexec "{PY}" "{mock_date}" "$@"\n')
    date_wrapper.chmod(0o755)

    master_fd, slave_fd = pty.openpty()
    fc_serial = os.ttyname(slave_fd)
    udp_port = 14577

    env = dict(
        os.environ,
        NODE_ID="DRONE_S",
        FC_SERIAL=fc_serial,
        FC_BAUD="57600",
        MAVLINK_BIND="127.0.0.1",
        MAVLINK_UDP_PORT=str(udp_port),
        AUX_STATE_FILE=str(work / "aux_state.json"),
        AUDIT_LOG_FILE=str(work / "audit.log"),
        MAVGW_STATE_FLUSH_INTERVAL="1",
        DATE_SET_CMD=f"{date_wrapper} {{utc}}",
    )
    proc = subprocess.Popen([PY, str(GW)], env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(slave_fd)

    # Fake GCS socket.
    gcs = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    gcs.bind(("127.0.0.1", 0))
    gcs.settimeout(2)
    gw_addr = ("127.0.0.1", udp_port)

    # MAVLink encoders (act as the FC).
    fc = mavutil.mavlink.MAVLink(None)
    fc.srcSystem = 1
    fc.srcComponent = 1

    def read_state():
        try:
            return json.loads((work / "aux_state.json").read_text())
        except (OSError, json.JSONDecodeError):
            return {}

    def wait_until(pred, timeout=8):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if pred():
                return True
            time.sleep(0.1)
        return pred()

    try:
        # The gateway only learns a GCS address once that GCS has sent it
        # something. Send a GCS heartbeat first so replies come back to us.
        gcs_mav = mavutil.mavlink.MAVLink(None)
        gcs_mav.srcSystem = 255
        hb = gcs_mav.heartbeat_encode(6, 8, 0, 0, 0)  # GCS heartbeat
        gcs.sendto(hb.pack(gcs_mav), gw_addr)
        time.sleep(0.5)

        print("[1] command path: GCS UDP bytes reach the FC serial verbatim")
        payload = gcs_mav.command_long_encode(1, 1, 400, 0, 1, 0, 0, 0, 0, 0, 0)
        raw_cmd = payload.pack(gcs_mav)
        gcs.sendto(raw_cmd, gw_addr)
        got = b""
        deadline = time.time() + 3
        os.set_blocking(master_fd, False)
        while time.time() < deadline and raw_cmd not in got:
            try:
                got += os.read(master_fd, 4096)
            except BlockingIOError:
                time.sleep(0.05)
        check("arm COMMAND_LONG bytes arrived at the FC unmodified",
              raw_cmd in got)

        print("[2] telemetry path: FC serial bytes reach the GCS verbatim")
        gps = fc.gps_raw_int_encode(0, 3, 69271000, 798612000, 500, 120, 0,
                                    0, 0, 9)
        raw_gps = gps.pack(fc)
        os.write(master_fd, raw_gps)
        received = b""
        try:
            for _ in range(20):
                data, _ = gcs.recvfrom(4096)
                received += data
                if raw_gps in received:
                    break
        except socket.timeout:
            pass
        check("GPS_RAW_INT bytes forwarded to the GCS unmodified",
              raw_gps in received)

        print("[3] telemetry tap: GPS decodes into aux_state")
        check("gps fix + sats in aux_state",
              wait_until(lambda: read_state().get("gps", {}).get("sats") == 9
                         and read_state().get("gps", {}).get("fix") == 1))
        st = read_state()
        check("gps lat is the drone position",
              abs((st.get("gps", {}).get("lat") or 0) - 6.9271) < 0.001)

        print("[4] telemetry tap: SYS_STATUS battery into aux_state")
        ss = fc.sys_status_encode(0, 0, 0, 0, 11100, -1, 0, 0, 0, 0, 0, 0, 87)
        os.write(master_fd, ss.pack(fc))
        check("flight-battery voltage in aux_state",
              wait_until(lambda: abs((read_state().get("battery", {}).get("a_v") or 0) - 11.1) < 0.01))

        print("[5] SYSTEM_TIME sets the clock and flips clock_source")
        # A realistic GPS unix time (2026-ish) in microseconds.
        unix_usec = 1_775_000_000 * 1_000_000
        stime = fc.system_time_encode(unix_usec, 100000)
        os.write(master_fd, stime.pack(fc))
        check("mocked date command invoked",
              wait_until(lambda: date_marker.exists()))
        check("clock_source flipped to gps",
              wait_until(lambda: read_state().get("clock_source") == "gps"))
        audit = (work / "audit.log").read_text()
        check("CLOCK_SYNC audit line from the FC source",
              "CLOCK_SYNC | src=fc_mavlink" in audit)

    finally:
        proc.kill()
        proc.wait()
        os.close(master_fd)
        gcs.close()

    print("[6] empty FC_SERIAL exits cleanly (a node with no FC)")
    r = subprocess.run([PY, str(GW)],
                       env=dict(os.environ, FC_SERIAL="", AUX_STATE_FILE=str(work / "x.json"),
                                AUDIT_LOG_FILE=str(work / "audit.log")),
                       capture_output=True, timeout=30)
    check("exit code 0 with no FC_SERIAL", r.returncode == 0)

    print()
    if failures:
        print(f"=== MAVGW PTY TEST: FAIL ({len(failures)}): {failures}")
        sys.exit(1)
    print(f"=== MAVGW PTY TEST: PASS (workdir {work}) ===")


if __name__ == "__main__":
    main()
