#!/usr/bin/env python3
"""Does the bridge actually announce a planned shutdown on SIGTERM?

Run from the repository root:  python3 tools/aux_shutdown_notice_test.py

Background. The two sub-units of a node have SEPARATE batteries, which is
the whole fault-tolerance design. The side effect: switching a node off
kills the Pi while the aux module keeps running, so it misses heartbeats,
concludes the Pi crashed, and starts telling the fleet this node FAILED.
An intentional power-down was indistinguishable from a failure.

The fix is that the Pi says goodbye first. This runs the real bridge
against a pty, sends SIGTERM the way systemd does on halt, and checks the
module received {"type":"shutdown"} before the process exited. Without
this test the whole front-panel fix is untested wiring.

No hardware needed. AUX_STATE_FILE is redirected because /run is not
writable on a development machine.
"""
import json, os, pty, signal, subprocess, sys, time

sys.path.insert(0, "backend")

master, slave = pty.openpty()
slave_name = os.ttyname(slave)

env = dict(os.environ)
env["AUX_SERIAL"] = slave_name
env["NODE_ID"] = "DRONE_T"
env["DB_FILE"] = "/tmp/shutdown_notice_test.db"
env["AUX_STATE_FILE"] = "/tmp/aux_state_test.json"

proc = subprocess.Popen(
    [".venv/bin/python", "aux_bridge.py"],
    cwd="backend", env=env,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
)
time.sleep(3)

os.set_blocking(master, False)
try:
    os.read(master, 65536)  # drain pings
except BlockingIOError:
    pass

proc.send_signal(signal.SIGTERM)
deadline = time.time() + 8
seen = ""
while time.time() < deadline:
    try:
        seen += os.read(master, 65536).decode(errors="replace")
    except (BlockingIOError, OSError):
        time.sleep(0.1)
    if '"shutdown"' in seen:
        break

proc.wait(timeout=10)
os.close(master); os.close(slave)

types = []
for line in seen.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        types.append(json.loads(line).get("type"))
    except Exception:
        pass

print("message types received by the module after SIGTERM:", types)
if "shutdown" in types:
    print("PASS: the module was told the shutdown was planned")
    sys.exit(0)
print("FAIL: no shutdown notice; a deliberate power-off would look like a crash")
sys.exit(1)
