"""
mission_config.py: per-mission, versioned settings that a node serves to
victims (CHANGES.md item 34).

Why this exists. Testers said the captive portal was wrong for an
emergency: it demanded that a frightened person type prose before they
could ask for help. The fix is to offer tappable options instead, but the
right options depend on the disaster, and the wording for a flood is not
the wording for a landslide. The GCC knows the disaster type; the nodes did
not know anything about the mission at all.

So the GCC pushes a config to each node before deployment, and the node
serves the portal from it.

Three properties this has to have, all of them learned the hard way in
distributed systems:

  1. A node that was never pushed to MUST still work. It falls back to
     STOCK_CONFIG below, which is deliberately need-based ("I am trapped",
     "I need water") rather than disaster-specific, so it is never wrong,
     only less tailored.

  2. Every node reports WHICH version it holds, so the GCC can show
     "config v3" or "stock" per node and the operator can see who is
     actually updated before deploying. Silent partial rollout is the
     failure mode that bites.

  3. Versions only ever move forward. A push carrying an older or equal
     version is rejected, so a stale GCC replaying an old config cannot
     downgrade a node that another operator already updated. Messages
     record the version that produced them, so changing the options
     mid-mission never makes older messages unreadable.
"""

import json
import os
import threading

import config

# Bumped by hand when the SHAPE of the config changes, not its contents.
CONFIG_SCHEMA = "mission-config-v1"

# What a node serves when nobody has pushed anything. Phrased around NEEDS
# rather than around a disaster, so it is usable in any event: the whole
# point is that an un-pushed node is still helpful, not broken.
STOCK_CONFIG = {
    "schema": CONFIG_SCHEMA,
    "version": 0,
    "mission_name": "",
    "disaster_type": "",
    "source": "stock",
    "updated_at": "",
    # Each option becomes one big tappable button in the portal. `urgent`
    # ones are rendered first and flagged to the rescue team.
    "situations": [
        {"id": "trapped", "label": "I am trapped and cannot get out",
         "urgent": True},
        {"id": "injured", "label": "Someone here is injured",
         "urgent": True},
        {"id": "medical", "label": "I need medicine or a doctor",
         "urgent": True},
        {"id": "water_food", "label": "I need drinking water or food",
         "urgent": False},
        {"id": "shelter", "label": "I need shelter or evacuation",
         "urgent": False},
        {"id": "safe", "label": "I am safe, reporting my location",
         "urgent": False},
    ],
    # Shown above the buttons. Kept short: people skim in an emergency.
    "headline": "Tap what you need. You can tap more than one.",
}


_lock = threading.Lock()


def _path() -> str:
    return getattr(config, "MISSION_CONFIG_FILE", "") or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "mission_config.json"
    )


def load() -> dict:
    """The active config, or the stock one if nothing was ever pushed.

    Never raises: a corrupt or half-written file falls back to stock rather
    than taking the victim portal down, because a portal serving slightly
    generic options is infinitely better than a portal serving a traceback
    to someone who needs help.
    """
    try:
        with open(_path(), "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict) or not data.get("situations"):
            return dict(STOCK_CONFIG)
        merged = dict(STOCK_CONFIG)
        merged.update(data)
        merged["source"] = "pushed"
        return merged
    except (OSError, json.JSONDecodeError, ValueError):
        return dict(STOCK_CONFIG)


def save(new_config: dict) -> dict:
    """Accept a pushed config if it is strictly newer. Returns the config
    now in force, so the caller can report what actually happened.

    Raises ValueError when the push is malformed or not an upgrade; the API
    turns that into a 400 rather than silently doing nothing, because an
    operator who thinks they pushed and did not is exactly the situation
    property 2 above exists to prevent.
    """
    if not isinstance(new_config, dict):
        raise ValueError("config must be an object")

    situations = new_config.get("situations")
    if not isinstance(situations, list) or not situations:
        raise ValueError("config needs a non-empty situations list")
    for s in situations:
        if not isinstance(s, dict) or not s.get("id") or not s.get("label"):
            raise ValueError("each situation needs an id and a label")

    try:
        version = int(new_config.get("version", 0))
    except (TypeError, ValueError):
        raise ValueError("version must be a whole number")

    with _lock:
        current = load()
        if version <= int(current.get("version", 0)):
            raise ValueError(
                f"version {version} is not newer than the {current.get('version')} "
                "already on this node"
            )

        stored = dict(STOCK_CONFIG)
        stored.update(new_config)
        stored["schema"] = CONFIG_SCHEMA
        stored["version"] = version
        stored["source"] = "pushed"

        # Write then rename: a power cut mid-write must not leave a
        # half-parsed file, since these nodes lose power for a living.
        tmp = _path() + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(stored, f, separators=(",", ":"), sort_keys=True)
        os.replace(tmp, _path())
        return stored


def summary() -> dict:
    """The small bit /health publishes, so the GCC can show a per-node
    'config v3' or 'stock' column without shipping the whole thing."""
    c = load()
    return {
        "version": c.get("version", 0),
        "source": c.get("source", "stock"),
        "mission_name": c.get("mission_name", ""),
        "disaster_type": c.get("disaster_type", ""),
        "updated_at": c.get("updated_at", ""),
        "situation_count": len(c.get("situations", [])),
    }
