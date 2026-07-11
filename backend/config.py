"""
config.py: central configuration for all backend daemons (project rule 7:
configuration over constants; progress report item 4.3).

Load order:
  1. NODE_ENV_FILE env var, if set (used by tests and local dev).
  2. /etc/rescue-mesh/node.env, if present (field deployment, file 01 step 7).
  3. backend/.env, if present (developer convenience).
Process environment variables always win over file values (dotenv default).
"""

import os
from pathlib import Path

from dotenv import load_dotenv

_explicit = os.getenv("NODE_ENV_FILE", "")
if _explicit and Path(_explicit).exists():
    load_dotenv(_explicit)
elif Path("/etc/rescue-mesh/node.env").exists():
    load_dotenv("/etc/rescue-mesh/node.env")
else:
    load_dotenv(Path(__file__).parent / ".env")


def _bool(name: str, default: str = "false") -> bool:
    return os.getenv(name, default).strip().lower() in {"1", "true", "yes", "on"}


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


# --- Node identity (file 01 step 7) ---------------------------------------
NODE_ID = os.getenv("NODE_ID", "DRONE_DEV")
USER_AP_SSID = os.getenv("USER_AP_SSID", "RESCUE_DEV")
DTN_IP = os.getenv("DTN_IP", "10.99.0.1")
DTN_PEERS = [p.strip() for p in os.getenv("DTN_PEERS", "").split(",") if p.strip()]

# --- Network / ports --------------------------------------------------------
API_HOST = os.getenv("API_HOST", "0.0.0.0")
API_PORT = _int("API_PORT", 8443)
HTTP_HOST = os.getenv("HTTP_HOST", "0.0.0.0")
HTTP_PORT = _int("HTTP_PORT", 80)

# --- Storage ----------------------------------------------------------------
DB_FILE = os.getenv("DB_FILE", "drone_mesh.db")
AUDIT_LOG_FILE = os.getenv("AUDIT_LOG_FILE", "audit.log")

# --- Trust root (file 09 F2): ONE master secret, per-purpose keys derived
# with HKDF in crypto_keys.py. Never commit a real value (file 09 F4);
# deploy/setup_node.sh generates it per node fleet-wide.
NODE_MASTER_SECRET = os.getenv("NODE_MASTER_SECRET", "dev_master_secret_change_me")

# --- Break-glass API keys (file 09 plane 2: demoted, kept for bootstrap and
# recovery when the personnel table is empty; stored offline in the field).
RESCUE_API_KEY = os.getenv("RESCUE_API_KEY", "rk_team_a_alpha")
HQ_API_KEY = os.getenv("HQ_API_KEY", "rk_hq_dashboard")

# --- TLS for the authenticated plane (8443). Certs are issued by the fleet
# CA at deploy time (file 09 plane 2, deploy/make_fleet_ca.sh).
API_TLS_ENABLED = _bool("API_TLS_ENABLED", "false")
API_TLS_CERT = os.getenv("API_TLS_CERT", "keys/node_cert.pem")
API_TLS_KEY = os.getenv("API_TLS_KEY", "keys/node_key.pem")
# Inter-node mTLS: documented option, OFF by default (file 09 D1: per-record
# HMAC plus X-Node-Auth already authenticate sync; mTLS adds certificate
# lifecycle work for marginal gain in a 3-node fleet).
API_MTLS_ENABLED = _bool("API_MTLS_ENABLED", "false")
API_MTLS_CA_CERT = os.getenv("API_MTLS_CA_CERT", "keys/fleet_ca.crt")

# --- Sync daemon (file 02 task 2.3) ----------------------------------------
BEACON_PORT = _int("BEACON_PORT", 48555)
BEACON_ADDR = os.getenv("BEACON_ADDR", "10.99.0.255")
# BEACON_TARGETS overrides broadcast with explicit "ip:port" unicast targets.
# Field nodes leave it empty (broadcast); the loopback two-node test sets it.
BEACON_TARGETS = [t.strip() for t in os.getenv("BEACON_TARGETS", "").split(",") if t.strip()]
BEACON_BIND = os.getenv("BEACON_BIND", "0.0.0.0")
BEACON_INTERVAL = _int("BEACON_INTERVAL", 10)
PEER_EXPIRY = _int("PEER_EXPIRY", 35)
SYNC_INTERVAL = _int("SYNC_INTERVAL", 30)
SYNC_SCHEME = os.getenv("SYNC_SCHEME", "https")
SYNC_VERIFY_TLS = _bool("SYNC_VERIFY_TLS", "false")
SYNC_CA_CERT = os.getenv("SYNC_CA_CERT", "keys/fleet_ca.crt")
SYNC_PAGE_LIMIT = _int("SYNC_PAGE_LIMIT", 1000)

# --- Aux bridge (file 02 task 2.2) ------------------------------------------
AUX_SERIAL = os.getenv("AUX_SERIAL", "")
AUX_BAUD = _int("AUX_BAUD", 115200)
AUX_STATE_FILE = os.getenv("AUX_STATE_FILE", "/run/rescue-mesh/aux_state.json")
AUX_PING_INTERVAL = _int("AUX_PING_INTERVAL", 5)
HEALTH_SNAPSHOT_INTERVAL = _int("HEALTH_SNAPSHOT_INTERVAL", 30)
CLOCK_RESYNC_INTERVAL = _int("CLOCK_RESYNC_INTERVAL", 3600)
NEW_MSG_POLL_INTERVAL = _int("NEW_MSG_POLL_INTERVAL", 2)
LORA_SUMMARY_INTERVAL = _int("LORA_SUMMARY_INTERVAL", 300)
# Clock set command template; {utc} is replaced with the ISO timestamp.
# The deploy sudoers entry allows exactly this command for the service user
# (file 02 task 2.2 point 4). Tests override it with a mock.
DATE_SET_CMD = os.getenv("DATE_SET_CMD", "sudo -n /bin/date -u -s {utc}")

# --- Rate limits (file 09 plane 1: per-IP alone is weak because a nearby
# attacker can rotate MAC/DHCP, so unauthenticated writes also get a global
# cap; both caps apply to /message and /checkin).
RATE_LIMIT_COUNT = _int("RATE_LIMIT_COUNT", 5)
RATE_LIMIT_WINDOW_SECONDS = _int("RATE_LIMIT_WINDOW_SECONDS", 60)
GLOBAL_WRITE_LIMIT_COUNT = _int("GLOBAL_WRITE_LIMIT_COUNT", 60)
GLOBAL_WRITE_LIMIT_WINDOW_SECONDS = _int("GLOBAL_WRITE_LIMIT_WINDOW_SECONDS", 60)
MAX_PENDING_MESSAGES = _int("MAX_PENDING_MESSAGES", 10000)
LOGIN_RATE_LIMIT_COUNT = _int("LOGIN_RATE_LIMIT_COUNT", 5)
LOGIN_RATE_LIMIT_WINDOW_SECONDS = _int("LOGIN_RATE_LIMIT_WINDOW_SECONDS", 300)

# --- Personnel auth (file 02 task 2.4) ---------------------------------------
TOKEN_TTL_HOURS = _int("TOKEN_TTL_HOURS", 24)
PBKDF2_ITERATIONS = _int("PBKDF2_ITERATIONS", 210000)
PIN_LENGTH = _int("PIN_LENGTH", 6)

# --- Victim E2E encryption: capability kept, OFF by default (file 09 D2:
# a fleet keypair whose private key sits on every rescuer phone is a shared
# secret in asymmetric clothing; enabling it is a deliberate op decision).
E2E_ENABLED = _bool("E2E_ENABLED", "false")
VICTIM_E2E_PUBLIC_KEY_PATH = os.getenv("VICTIM_E2E_PUBLIC_KEY_PATH", "")
VICTIM_E2E_KEY_ID = os.getenv("VICTIM_E2E_KEY_ID", "rescue-team-key-1")
E2E_ENCRYPTION_REQUIRED = _bool("E2E_ENCRYPTION_REQUIRED", "false")
