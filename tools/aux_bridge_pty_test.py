#!/usr/bin/env python3
"""
aux_bridge_pty_test.py: exercise backend/aux_bridge.py against a fake aux
module on a pty pair, no hardware (file 02 task 2.2 local verification).

Covers: ble_update at connect, pings, gps/battery -> aux_state.json,
gps_time -> (mocked) clock set command + clock_source flip, fallback_rx ->
degraded node_health row + audit entry, last_msg push on new DB rows, and
the clean exit when AUX_SERIAL is empty (DRONE_S case).

Usage: backend/.venv/bin/python tools/aux_bridge_pty_test.py
"""

import json
import os
import pathlib
import pty
import subprocess
import sys
import tempfile
import time

REPO = pathlib.Path(__file__).resolve().parents[1]
BACKEND = REPO / "backend"
PY = str(BACKEND / ".venv" / "bin" / "python")

failures = []


def check(name, ok):
    print(("  ok: " if ok else "FAIL: ") + name)
    if not ok:
        failures.append(name)


def main():
    work = pathlib.Path(tempfile.mkdtemp(prefix="aux_bridge_test_"))
    date_marker = work / "date_set.txt"
    mock_date = work / "mock_date.py"
    mock_date.write_text(
        "import sys, pathlib\n"
        f"pathlib.Path(r'{date_marker}').write_text(' '.join(sys.argv[1:]))\n"
    )
    # DATE_SET_CMD is shlex-split by the bridge; wrap the interpreter in a
    # shell script at a space-free temp path so a repo path containing
    # spaces cannot break the command line.
    date_wrapper = work / "mock_date.sh"
    date_wrapper.write_text(f'#!/bin/sh\nexec "{PY}" "{mock_date}" "$@"\n')
    date_wrapper.chmod(0o755)

    master_fd, slave_fd = pty.openpty()
    slave_name = os.ttyname(slave_fd)

    env_file = work / "node.env"
    env_file.write_text(f"""
NODE_ID=DRONE_T
USER_AP_SSID=RESCUE_T
DB_FILE={work}/mesh.db
AUDIT_LOG_FILE={work}/audit.log
AUX_STATE_FILE={work}/aux_state.json
NODE_MASTER_SECRET=pty_test_secret
AUX_SERIAL={slave_name}
AUX_PING_INTERVAL=2
HEALTH_SNAPSHOT_INTERVAL=5
NEW_MSG_POLL_INTERVAL=1
LORA_SUMMARY_INTERVAL=3600
DATE_SET_CMD={date_wrapper} {{utc}}
""")

    env = dict(os.environ, NODE_ENV_FILE=str(env_file))
    proc = subprocess.Popen([PY, str(BACKEND / "aux_bridge.py")],
                            cwd=str(work), env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(slave_fd)

    def read_lines(timeout_s):
        """Collect JSON lines from the bridge for timeout_s seconds."""
        out = []
        deadline = time.time() + timeout_s
        buf = b""
        os.set_blocking(master_fd, False)
        while time.time() < deadline:
            try:
                chunk = os.read(master_fd, 4096)
                buf += chunk
            except BlockingIOError:
                time.sleep(0.05)
                continue
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    out.append(json.loads(line.decode()))
                except json.JSONDecodeError:
                    pass
        return out

    def send(obj):
        os.write(master_fd, (json.dumps(obj) + "\n").encode())

    def state():
        try:
            return json.loads((work / "aux_state.json").read_text())
        except (OSError, json.JSONDecodeError):
            return {}

    def wait_until(predicate, timeout_s=10):
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            if predicate():
                return True
            time.sleep(0.2)
        return predicate()

    try:
        print("[1] connect behavior: ble_update then pings")
        lines = read_lines(6)
        types = [l.get("type") for l in lines]
        check("ble_update sent at connect", "ble_update" in types)
        check("pings flowing", types.count("ping") >= 1)
        ble = next((l for l in lines if l.get("type") == "ble_update"), {})
        check("ble_update carries node_id + ssid",
              ble.get("node_id") == "DRONE_T" and ble.get("ssid") == "RESCUE_T")

        print("[2] gps + battery update the state file")
        send({"type": "gps", "lat": 6.93, "lon": 79.85, "fix": 1, "sats": 8, "hdop": 1.1})
        send({"type": "battery", "bat_a_v": 7.8, "bat_a_ma": 590.0,
              "bat_b_v": 4.05, "bat_b_ma": 150.0})
        check("gps in aux_state",
              wait_until(lambda: state().get("gps", {}).get("sats") == 8))
        check("battery in aux_state",
              wait_until(lambda: state().get("battery", {}).get("a_v") == 7.8))
        check("aux_present true", state().get("aux_present") is True)

        print("[3] gps_time triggers the clock set command (mocked sudo date)")
        send({"type": "gps_time", "utc": "2026-07-11T09:30:00Z", "fix": 1, "sats": 8})
        check("date command invoked with the UTC string",
              wait_until(lambda: date_marker.exists()
                         and "2026-07-11T09:30:00Z" in date_marker.read_text()))
        check("clock_source flipped to gps",
              wait_until(lambda: state().get("clock_source") == "gps"))
        check("gps_time_applied true", state().get("gps_time_applied") is True)

        print("[4] fallback_rx stores a degraded node_health row")
        fb = ("FB|DRONE_B|6.910000|79.870000|1|2026-07-11T09:31:00Z|7.40|610|3.90|"
              "170|m-77|last cached msg|2026-07-11T09:00:00Z|DOWN")
        send({"type": "fallback_rx", "raw": fb, "rssi": -88, "snr": 7.5})
        import sqlite3

        def degraded_row():
            conn = sqlite3.connect(work / "mesh.db")
            row = conn.execute(
                "SELECT node_id, degraded, bat_a_v, lat FROM node_health "
                "WHERE node_id='DRONE_B' ORDER BY ts DESC LIMIT 1").fetchone()
            conn.close()
            return row
        check("degraded row for DRONE_B",
              wait_until(lambda: (r := degraded_row()) is not None
                         and r[1] == 1 and abs(r[2] - 7.40) < 0.01))
        conn = sqlite3.connect(work / "mesh.db")
        audit = (work / "audit.log").read_text()
        check("FALLBACK_BEACON audit entry", "FALLBACK_BEACON" in audit)
        check("CLOCK_SYNC audit entry", "CLOCK_SYNC | old=" in audit)

        print("[5] new message row pushes last_msg over serial")
        conn.execute(
            "INSERT INTO messages (msg_id, content, timestamp, time_source, node_id, "
            "status, local_ts) VALUES ('m-push-1', 'cache|this message', "
            "'2026-07-11T09:32:00.000000Z', 'gps', 'DRONE_T', 'NEW', "
            "'2026-07-11T09:32:00.000000Z')")
        conn.commit()
        conn.close()
        lines = read_lines(4)
        push = next((l for l in lines if l.get("type") == "last_msg"), None)
        check("last_msg pushed", push is not None and push.get("msg_id") == "m-push-1")
        check("pipes stripped from pushed content",
              push is not None and "|" not in push.get("content", "|"))

    finally:
        proc.kill()
        proc.wait()
        os.close(master_fd)

    print("[6] empty AUX_SERIAL exits cleanly (DRONE_S case)")
    env2_file = work / "node2.env"
    env2_file.write_text(f"""
NODE_ID=DRONE_S
DB_FILE={work}/mesh2.db
AUDIT_LOG_FILE={work}/audit2.log
AUX_STATE_FILE={work}/aux_state2.json
NODE_MASTER_SECRET=pty_test_secret
AUX_SERIAL=
""")
    r = subprocess.run([PY, str(BACKEND / "aux_bridge.py")],
                       cwd=str(work), env=dict(os.environ, NODE_ENV_FILE=str(env2_file)),
                       capture_output=True, timeout=30)
    check("exit code 0", r.returncode == 0)
    st2 = json.loads((work / "aux_state2.json").read_text())
    check("state reports aux absent", st2.get("aux_present") is False)

    print()
    if failures:
        print(f"=== AUX BRIDGE PTY TEST: FAIL ({len(failures)}) : {failures}")
        sys.exit(1)
    print(f"=== AUX BRIDGE PTY TEST: PASS (workdir {work}) ===")


if __name__ == "__main__":
    main()
