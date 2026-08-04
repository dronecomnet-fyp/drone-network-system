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

  2. Every node reports WHICH config it holds, so the GCC can show per
     node whether it matches what the operator has loaded, or is still on
     stock. Silent partial rollout is the failure mode that bites.

  3. There is NO version counter. A counter has to be stored somewhere and
     kept correct, and whoever holds it can be wrong: a fresh GCC install,
     a second operator's laptop, or cleared settings all rewind it, and the
     operator then gets pushes rejected with no visible cause. Instead a
     config identifies itself by a HASH OF ITS OWN CONTENT, and ordering
     comes from the timestamp it was created at.

     That gives the two things a counter was only approximating. Comparing
     nodes becomes exact rather than numeric: same config_id means the same
     options, whoever pushed them and in whatever order. And a stale push
     is refused because its timestamp is older, not because a number
     somewhere was out of step.

     Changing the options mid-mission never makes older messages
     unreadable, because the option LABEL text is stored in the message
     content, not a reference to the config.
"""

import hashlib
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
    "config_id": "stock",
    # Credentials are scoped to a mission (field backlog, 2026-08-05). Empty
    # here means "this node has no active mission", which accepts any
    # credential: that is the state before the operator has pushed anything,
    # and locking people out of an unconfigured node would be worse than
    # useless.
    "mission_id": "",
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


def content_id(cfg: dict) -> str:
    """Short stable fingerprint of what a victim actually sees.

    Deliberately covers ONLY the visible content, not the timestamp or the
    mission name, so pushing the identical options twice produces the same
    id and the GCC can say "this node already matches" instead of inventing
    a difference that does not exist.
    """
    payload = json.dumps(
        {
            "situations": [
                {"id": s.get("id"), "label": s.get("label"),
                 "urgent": bool(s.get("urgent"))}
                for s in cfg.get("situations", [])
            ],
            "headline": cfg.get("headline", ""),
            "show_rescuer_positions": bool(cfg.get("show_rescuer_positions", True)),
        },
        sort_keys=True, separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode()).hexdigest()[:12]


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


def save(new_config: dict, force: bool = False) -> dict:
    """Store a pushed config. Returns what is now in force, so the caller
    reports the node's own answer rather than its own optimism.

    Ordering is by `updated_at`: a push older than what the node already
    holds is refused, which stops a second laptop carrying a stale mission
    file from silently undoing someone else's newer push. `force` overrides
    that for the case where an operator knows their clock was wrong and
    means it anyway.

    Raises ValueError when the push is malformed or older; the API turns
    that into a 400, because an operator who believes they pushed and did
    not is the exact failure this design exists to prevent.
    """
    if not isinstance(new_config, dict):
        raise ValueError("config must be an object")

    situations = new_config.get("situations")
    if not isinstance(situations, list) or not situations:
        raise ValueError("config needs a non-empty situations list")
    for s in situations:
        if not isinstance(s, dict) or not s.get("id") or not s.get("label"):
            raise ValueError("each situation needs an id and a label")

    incoming_at = str(new_config.get("updated_at", "") or "")

    with _lock:
        current = load()
        current_at = str(current.get("updated_at", "") or "")
        # ISO 8601 UTC sorts correctly as plain text, so no parsing needed.
        if not force and current_at and incoming_at and incoming_at < current_at:
            raise ValueError(
                f"this push was created at {incoming_at}, which is older than "
                f"the config already on this node ({current_at}). Push again "
                "with force if you mean to replace it."
            )

        stored = dict(STOCK_CONFIG)
        stored.update(new_config)
        stored["schema"] = CONFIG_SCHEMA
        stored["config_id"] = content_id(stored)
        stored["source"] = "pushed"

        # Write then rename: a power cut mid-write must not leave a
        # half-parsed file, since these nodes lose power for a living.
        tmp = _path() + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(stored, f, separators=(",", ":"), sort_keys=True)
        os.replace(tmp, _path())
        return stored


def summary() -> dict:
    """The small bit /health publishes, so the GCC can tell per node
    whether it matches, without shipping the whole config."""
    c = load()
    return {
        "config_id": c.get("config_id", "stock"),
        "mission_id": c.get("mission_id", ""),
        "source": c.get("source", "stock"),
        "mission_name": c.get("mission_name", ""),
        "disaster_type": c.get("disaster_type", ""),
        "updated_at": c.get("updated_at", ""),
        "situation_count": len(c.get("situations", [])),
    }


def active_mission_id() -> str:
    """Which mission this node is currently running, or empty.

    Empty accepts every credential. That is deliberate: a node nobody has
    pushed a mission to must still let rescuers work, and refusing them
    would turn a missed push into a lockout.
    """
    return str(load().get("mission_id", "") or "")
