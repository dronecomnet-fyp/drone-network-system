"""
Test environment: everything runs against a throwaway workspace. Env vars
are set BEFORE any backend module import because config.py reads them at
import time. Rate limit counts are raised for the general API tests; the
exact 429 behavior is unit-tested against the limiter class directly and
integration-tested on /auth/login (which keeps its small limit).
"""

import os
import pathlib
import sys
import tempfile

BASE = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE))

_tmp = tempfile.mkdtemp(prefix="rescue_mesh_test_")

os.environ["NODE_ENV_FILE"] = "/nonexistent-skip-node-env"
os.environ.setdefault("NODE_ID", "DRONE_T")
os.environ["DB_FILE"] = os.path.join(_tmp, "test.db")
os.environ["AUDIT_LOG_FILE"] = os.path.join(_tmp, "audit.log")
os.environ["AUX_STATE_FILE"] = os.path.join(_tmp, "aux_state.json")
os.environ["NODE_MASTER_SECRET"] = "test_master_secret"
os.environ["API_TLS_ENABLED"] = "false"
os.environ["RESCUE_API_KEY"] = "test_rescue_key"
os.environ["HQ_API_KEY"] = "test_hq_key"
os.environ["RATE_LIMIT_COUNT"] = "30"
os.environ["GLOBAL_WRITE_LIMIT_COUNT"] = "100"
os.environ["LOGIN_RATE_LIMIT_COUNT"] = "5"
os.environ["LOGIN_RATE_LIMIT_WINDOW_SECONDS"] = "300"


import pytest  # noqa: E402


@pytest.fixture(autouse=True)
def _reset_rate_limiters():
    """Give every test a fresh rate-limit budget.

    The limiters are process-global and the suite shares one process, so
    without this the tests silently compete for one budget: a module that
    posts a lot leaves later modules getting 429s and failing for reasons
    that have nothing to do with what they are testing. That is exactly
    what happened when the area-map tests were added, and the failure
    surfaced in an unrelated file, which is the worst kind of test debt.

    The 429 behaviour itself is still tested deliberately, against the
    limiter class directly and on /auth/login which keeps a small limit.
    """
    import http_app
    import api
    for limiter in (http_app._ip_limiter, http_app._global_limiter,
                    api._login_ip_limiter, api._login_id_limiter,
                    api._location_limiter):
        limiter._events = {}
    yield
