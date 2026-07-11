"""
crypto_keys.py: per-purpose key derivation and token primitives.

File 09 F2: Phase 1 signed everything (records, sync auth, planned tokens)
with the single NODE_SHARED_SECRET, so one captured node owned the whole
trust root for every purpose at once. Phase 2 derives purpose-separated
keys from ONE master secret with HKDF-SHA256:

  K_MSG    signs replicated records (messages, personnel, announcements,
           gs_messages, checkins)
  K_SYNC   authenticates inter-node traffic (X-Node-Auth header, presence
           beacon signatures)
  K_TOKEN  signs personnel session tokens

A leak of one purpose key forges nothing under the other purposes. Physical
capture of a node (adversary A2) still yields the master secret; that stays
the documented residual risk, answered by the fleet-wide rotation runbook
(SECRETS_ROTATION.md). Per-node Ed25519 identities are future work.

Session token format (file 02 task 2.4):
  base64url(payload_json) + "." + hex(HMAC_SHA256(K_TOKEN, payload_json))
  payload = {"personnel_id": ..., "role": ..., "exp": epoch_seconds}
Stateless: ANY node holding the same master secret verifies it offline.
"""

import base64
import hashlib
import hmac
import json
import time

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

import config

_HKDF_SALT = b"rescue-mesh-phase2-v1"


def _derive(purpose: str) -> bytes:
    return HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=_HKDF_SALT,
        info=purpose.encode(),
    ).derive(config.NODE_MASTER_SECRET.encode())


K_MSG = _derive("record-signing")
K_SYNC = _derive("inter-node-auth")
K_TOKEN = _derive("session-tokens")

# Static header value for X-Node-Auth. Same trust shape as Phase 1 (a shared
# fleet value compared with compare_digest) but bound to the sync purpose key
# only, so leaking it does not let anyone forge records or tokens.
NODE_AUTH_VALUE = hmac.new(K_SYNC, b"x-node-auth-v2", hashlib.sha256).hexdigest()


def hmac_hex(key: bytes, payload: str) -> str:
    return hmac.new(key, payload.encode(), hashlib.sha256).hexdigest()


def verify_hmac_hex(key: bytes, payload: str, signature: str) -> bool:
    if not signature:
        return False
    return hmac.compare_digest(hmac_hex(key, payload), signature)


def mint_token(personnel_id: str, role: str, ttl_hours: int = None) -> dict:
    ttl = ttl_hours if ttl_hours is not None else config.TOKEN_TTL_HOURS
    exp = int(time.time()) + ttl * 3600
    payload = json.dumps(
        {"personnel_id": personnel_id, "role": role, "exp": exp},
        separators=(",", ":"),
        sort_keys=True,
    )
    body = base64.urlsafe_b64encode(payload.encode()).decode().rstrip("=")
    sig = hmac_hex(K_TOKEN, payload)
    return {"token": f"{body}.{sig}", "expires_at": exp}


def verify_token(token: str):
    """Return the payload dict for a valid, unexpired token, else None."""
    try:
        body, sig = token.strip().split(".", 1)
        pad = "=" * (-len(body) % 4)
        payload = base64.urlsafe_b64decode(body + pad).decode()
    except (ValueError, UnicodeDecodeError):
        return None
    if not verify_hmac_hex(K_TOKEN, payload, sig):
        return None
    try:
        data = json.loads(payload)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    if int(data.get("exp", 0)) < time.time():
        return None
    if not data.get("personnel_id") or not data.get("role"):
        return None
    return data
