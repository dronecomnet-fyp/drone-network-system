"""
ratelimit.py: sliding-window rate limiting shared by the victim plane
(http_app.py) and the authenticated plane (api.py login route).

File 09 plane 1: per-IP limiting alone is weak on an open AP because a
nearby attacker (A1) can rotate MAC/DHCP for fresh IPs, so unauthenticated
writes are ALSO capped globally. The global cap throttles a flood while an
already-connected rescuer on the authenticated plane stays unaffected
(different endpoints, different limiter instances).
"""

import time
from threading import Lock

from fastapi import HTTPException


class SlidingWindowLimiter:
    """Per-key sliding window: at most `count` events per `window` seconds."""

    def __init__(self, count: int, window_seconds: int, scope: str):
        self.count = count
        self.window = window_seconds
        self.scope = scope
        self._events = {}
        self._lock = Lock()

    def check(self, key: str):
        now = time.time()
        start = now - self.window
        with self._lock:
            ts = [t for t in self._events.get(key, []) if t >= start]
            if len(ts) >= self.count:
                raise HTTPException(
                    status_code=429,
                    detail=f"Rate limit exceeded ({self.scope}). Please retry shortly.",
                )
            ts.append(now)
            self._events[key] = ts
            # Opportunistic cleanup so the map cannot grow unbounded.
            if len(self._events) > 10000:
                self._events = {
                    k: [t for t in v if t >= start]
                    for k, v in self._events.items()
                    if any(t >= start for t in v)
                }


class GlobalLimiter(SlidingWindowLimiter):
    """Single shared bucket regardless of source."""

    def check_global(self):
        self.check("__global__")
