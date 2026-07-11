"""
aux_state.py: the tiny local API between aux_bridge.py and the rest of the
backend (file 02 task 2.2 point 7). The bridge writes the latest aux module
state as JSON to AUX_STATE_FILE atomically (temp file + rename on the same
filesystem); api.py's /health and models.save_message read it.

When no aux module is fitted (DRONE_S flies without one, file 08), the state
reports aux_present false and clock_source "relative"; everything else on
the node works unchanged.
"""

import json
import os
import tempfile
from pathlib import Path

import config

DEFAULT_STATE = {
    "aux_present": False,
    "node_id": config.NODE_ID,
    "gps": {"lat": None, "lon": None, "fix": 0, "sats": 0, "hdop": None},
    "battery": {"a_v": None, "a_ma": None, "b_v": None, "b_ma": None},
    "gps_time_applied": False,
    "clock_source": "relative",
    "last_rx_ts": None,
}


def read_state() -> dict:
    try:
        with open(config.AUX_STATE_FILE) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return dict(DEFAULT_STATE)
    merged = dict(DEFAULT_STATE)
    merged.update(data)
    return merged


def write_state(state: dict) -> None:
    path = Path(config.AUX_STATE_FILE)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".aux_state_")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(state, f)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
