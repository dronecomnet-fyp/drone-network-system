#!/usr/bin/env python3
"""
seed_demo_data.py: fill a node with plausible demo data so UI screenshots
are not screenshots of empty screens.

Why this exists: a report figure showing "No messages yet" proves nothing.
Every screen worth capturing needs data behind it, and typing fifteen
victim messages into a phone by hand before a screenshot session is an
hour nobody has.

WHAT THIS IS NOT: this does not fabricate RESULTS. It creates the same
records a victim's phone or browser would create, through the same public
endpoints, with the same validation and the same signing. Nothing here
bypasses the backend. The content is invented, and the report must say
that any screenshot showing this data is populated with demo content.

Deliberately paced: the victim plane rate-limits to 5 writes per IP per
60 seconds (config.RATE_LIMIT_COUNT). Seeding faster gets you HTTP 429,
which is the limiter doing its job. The script waits instead of fighting
it, and prints the pacing so nobody thinks it has hung.

Usage:
    python3 tools/seed_demo_data.py                    # against 10.42.0.1
    python3 tools/seed_demo_data.py --host 127.0.0.1   # against a local dev node
    python3 tools/seed_demo_data.py --fast             # ignore pacing (expect 429s)
"""

import argparse
import json
import random
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

# Colombo, roughly. Close enough to look real on an offline tile set of
# the region, and obviously not a real incident.
BASE_LAT = 6.9271
BASE_LON = 79.8612


def jitter(base, metres):
    """Offset a coordinate by up to `metres`, crudely. 1e-5 deg is about
    1.1 m of latitude, and near the equator longitude is close enough."""
    return base + random.uniform(-metres, metres) * 1e-5


MESSAGES = [
    "I am trapped and cannot get out. Someone here is injured",
    "Two adults and a child on the roof, water still rising",
    "I need medicine or a doctor. Diabetic, no insulin since yesterday",
    "Someone here is injured. Leg injury, cannot walk",
    "I need drinking water or food",
    "I am trapped and cannot get out. Ground floor, door blocked",
    "I need shelter or evacuation. Four people, one elderly",
    "I am safe, reporting my location",
    "I need medicine or a doctor",
    "Building partly collapsed, three of us in the stairwell",
    "I need drinking water or food. Six people at the school",
    "I am safe, reporting my location. No injuries here",
]

SOS_TEXTS = [
    "I am trapped and cannot get out; Someone here is injured. On the roof",
    "I need medicine or a doctor. Chest pain",
    "I need shelter or evacuation. Water at waist height",
]


def post(host, path, payload, timeout=8):
    req = urllib.request.Request(
        f"http://{host}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]
    except Exception as e:  # noqa: BLE001
        return 0, str(e)


def iso_ago(minutes):
    t = datetime.now(timezone.utc) - timedelta(minutes=minutes)
    return t.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="10.42.0.1",
                    help="node address on its user AP (default 10.42.0.1)")
    ap.add_argument("--messages", type=int, default=8)
    ap.add_argument("--checkins", type=int, default=4)
    ap.add_argument("--fast", action="store_true",
                    help="skip the rate-limit pacing (expect HTTP 429)")
    args = ap.parse_args()

    # 5 writes per 60 s, so 13 s apart leaves a little headroom.
    pace = 0 if args.fast else 13

    print(f"Seeding {args.host}. "
          f"{'No pacing, expect 429s.' if args.fast else f'{pace}s between writes to stay under the rate limit.'}")
    print("Demo content only. Nothing here is a real incident.\n")

    ok = fail = 0
    random.shuffle(MESSAGES)

    for i, content in enumerate(MESSAGES[:args.messages], 1):
        # Roughly two thirds carry a location, which is what the real mix
        # looks like: the browser prompt is opt-out but some people decline.
        loc = random.random() < 0.7
        payload = {
            "content": content,
            "victim_device_id": f"demo-{random.randint(0x10000000, 0xffffffff):08x}",
        }
        if loc:
            payload["user_lat"] = round(jitter(BASE_LAT, 400), 6)
            payload["user_lon"] = round(jitter(BASE_LON, 400), 6)
        status, body = post(args.host, "/message", payload)
        mark = "ok " if status == 200 else f"{status}"
        print(f"  message {i}/{args.messages}  [{mark}] {content[:52]}")
        if status == 200:
            ok += 1
        else:
            fail += 1
            if status == 429:
                print("    rate limited. That is the limiter working; "
                      "it is not a seeding failure.")
        if i < args.messages and pace:
            time.sleep(pace)

    print()
    for i in range(1, args.checkins + 1):
        device = f"demo-app-{random.randint(0x1000, 0xffff):04x}"
        # A short track, as the emergency app would have logged it.
        points = [
            {
                "lat": round(jitter(BASE_LAT, 500), 6),
                "lon": round(jitter(BASE_LON, 500), 6),
                "accuracy": round(random.uniform(8, 45), 1),
                "recorded_at": iso_ago(minutes=m),
            }
            for m in (720, 360, 90, 5)
        ]
        sos = i <= len(SOS_TEXTS)
        payload = {
            "device_id": device,
            "sos": sos,
            "sos_text": SOS_TEXTS[i - 1] if sos else "",
            "points": points,
        }
        status, body = post(args.host, "/checkin", payload)
        mark = "ok " if status == 200 else f"{status}"
        print(f"  checkin {i}/{args.checkins}  [{mark}] "
              f"{'SOS' if sos else 'location only'}, {len(points)} points")
        if status == 200:
            ok += 1
        else:
            fail += 1
        if i < args.checkins and pace:
            time.sleep(pace)

    print(f"\nDone. {ok} accepted, {fail} rejected.")
    if fail:
        print("Rejections are usually the rate limiter. Re-run to top up, "
              "or use --fast only if you are deliberately testing 429s.")
    print("\nNext: personnel, announcements and the mission plan are made "
          "in the GCC, not here. See the evidence guide, session 2.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
