#!/usr/bin/env python3
"""
node_indicator.py: the beep and lights on a node's front panel
(field backlog #1).

Runs on the Raspberry Pi, not the aux module. The operator chose the Pi,
and it is also the only option: every XIAO signal pin is already allocated
(CHANGES.md item 10), so there was no free GPIO on the aux side.

The honest limit of that choice, worth knowing before you rely on it: this
CANNOT indicate anything once the Pi is dead, which is exactly the LoRa
fallback case. A failed node goes dark locally. The aux module still
reports that condition to the rest of the fleet over LoRa, so the GCC sees
it; nobody standing next to the drone will. That was accepted deliberately.

What it shows:

    READY (green, solid)   the node's own services answered. Safe to walk
                           away from.
    MESH  (amber)          solid when this node can currently see at least
                           one peer, off when it cannot. This is the light
                           that would have saved an evening: a dead USB
                           adapter shows here immediately instead of being
                           found by reading sync logs.
    BEEP                   two short beeps when the node first becomes
                           ready, so you know from across a field without
                           looking. Nothing after that: a device that beeps
                           repeatedly gets muted or unplugged.

Deliberately reads /health over the loopback rather than importing the
backend. If the API is not answering, the node is not ready by definition,
and asking the same way an app would is the honest test.
"""

import json
import signal
import sys
import time
import urllib.request

try:
    from gpiozero import LED, Buzzer
except ImportError:  # pragma: no cover - only on a Pi
    print("gpiozero missing: sudo apt install python3-gpiozero", file=sys.stderr)
    raise SystemExit(1)

# BCM numbering. These four are free on every node: the aux module is on
# USB, and the only GPIO peripheral in the design is DRONE_S's optional
# flight-controller UART on GPIO14/15, which is untouched here.
PIN_BUZZER = 17
PIN_LED_READY = 27
PIN_LED_MESH = 22

HEALTH_URL = "https://127.0.0.1:8443/health"
POLL_SECONDS = 10
READY_TIMEOUT_SECONDS = 180


def _health():
    """The node's own /health, or None. Certificate verification is off on
    purpose: this is loopback to ourselves, the fleet CA is about proving a
    node's identity to REMOTE clients, and there is no remote here."""
    import ssl
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=4, context=ctx) as r:
            return json.loads(r.read().decode())
    except Exception:
        return None


def main():
    buzzer = Buzzer(PIN_BUZZER)
    ready_led = LED(PIN_LED_READY)
    mesh_led = LED(PIN_LED_MESH)

    def cleanup(*_):
        buzzer.off()
        ready_led.off()
        mesh_led.off()
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    # Booting: blink the ready LED so somebody watching knows the Pi is
    # alive and working rather than wondering whether it powered on at all.
    announced = False
    started = time.monotonic()
    while not announced and time.monotonic() - started < READY_TIMEOUT_SECONDS:
        h = _health()
        if h is not None:
            ready_led.on()
            # Two short beeps, once. See the module docstring on why it is
            # not repeated.
            for _ in range(2):
                buzzer.on()
                time.sleep(0.12)
                buzzer.off()
                time.sleep(0.12)
            announced = True
            break
        ready_led.toggle()
        time.sleep(0.5)

    if not announced:
        # Services never came up. Leave the ready light OFF rather than
        # lying, and beep a longer single tone so the difference is audible
        # from a distance.
        ready_led.off()
        buzzer.on()
        time.sleep(0.8)
        buzzer.off()

    # Steady state: the mesh light tracks whether we can see anyone.
    while True:
        h = _health()
        if h is None:
            ready_led.off()
            mesh_led.off()
        else:
            ready_led.on()
            peers = h.get("peers") or []
            if peers:
                mesh_led.on()
            else:
                mesh_led.off()
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
