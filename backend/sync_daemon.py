"""
sync_daemon.py: the always-on DTN sync daemon (file 02 task 2.3). Replaces
Phase 1's switcher.py entirely: wlan1 is a permanent IBSS interface with a
static IP (file 01 step 5), so there is no nmcli logic here at all.

Three concerns, one process (rescue-mesh-sync.service):

  Presence TX  every BEACON_INTERVAL (10 s): broadcast a signed UDP beacon
               {node_id, api_port, ts, counter, counts} to
               BEACON_ADDR:BEACON_PORT (10.99.0.255:48555). The counter is
               monotonic and persisted (models.next_beacon_counter), and
               the signature uses K_SYNC (file 09 F2/F6).

  Presence RX  listen on BEACON_BIND:BEACON_PORT; verify signature, drop
               our own beacons, reject non-increasing counters (replay,
               file 09 F6, audit-logged), track alive peers in peer_state.

  Sync loop    every SYNC_INTERVAL (30 s): pull deltas of all replicated
               tables from every alive peer (sync_engine.sync_with_peer).
               Runs fine with zero peers in range (the DTN normal case)
               and converges when they appear (file 07 T3).

BEACON_TARGETS (config) replaces broadcast with explicit unicast targets;
field nodes leave it empty, the loopback two-node test sets it because
127.0.0.1 has no broadcast semantics.
"""

import json
import socket
import threading
import time

import audit
import config
import crypto_keys
import models

audit_logger = audit.get_audit_logger()

_stop = threading.Event()


def _beacon_payload_canonical(node_id, api_port, ts, counter, counts_json) -> str:
    return f"{node_id}|{api_port}|{ts}|{counter}|{counts_json}"


def build_beacon() -> bytes:
    counts = models.table_counts()
    counts_json = json.dumps(counts, sort_keys=True, separators=(",", ":"))
    ts = models.iso_now()
    counter = models.next_beacon_counter()
    sig = crypto_keys.hmac_hex(
        crypto_keys.K_SYNC,
        _beacon_payload_canonical(config.NODE_ID, config.API_PORT, ts, counter, counts_json),
    )
    beacon = {
        "node_id": config.NODE_ID,
        "api_port": config.API_PORT,
        "ts": ts,
        "counter": counter,
        "counts": counts,
        "sig": sig,
    }
    return json.dumps(beacon, separators=(",", ":")).encode()


def parse_and_accept_beacon(data: bytes, src_ip: str) -> bool:
    """Verify, replay-check, and record a received beacon. Returns True when
    the peer table was updated."""
    try:
        beacon = json.loads(data.decode())
        node_id = beacon["node_id"]
        api_port = int(beacon["api_port"])
        ts = beacon["ts"]
        counter = int(beacon["counter"])
        counts = beacon.get("counts", {})
        sig = beacon["sig"]
    except (json.JSONDecodeError, UnicodeDecodeError, KeyError, TypeError, ValueError):
        return False
    if node_id == config.NODE_ID:
        return False
    counts_json = json.dumps(counts, sort_keys=True, separators=(",", ":"))
    payload = _beacon_payload_canonical(node_id, api_port, ts, counter, counts_json)
    if not crypto_keys.verify_hmac_hex(crypto_keys.K_SYNC, payload, sig):
        audit_logger.warning(f"BEACON_REJECT | src={src_ip} | reason=bad_signature")
        return False
    accepted = models.accept_beacon(node_id, src_ip, api_port, counter, counts_json)
    if not accepted:
        # Non-increasing counter: replayed or duplicated datagram (file 09 F6).
        audit_logger.warning(
            f"BEACON_REPLAY_REJECT | node={node_id} | src={src_ip} | counter={counter}"
        )
    return accepted


def beacon_tx_loop():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    if config.BEACON_TARGETS:
        targets = []
        for t in config.BEACON_TARGETS:
            host, _, port = t.partition(":")
            targets.append((host, int(port) if port else config.BEACON_PORT))
    else:
        targets = [(config.BEACON_ADDR, config.BEACON_PORT)]
    while not _stop.is_set():
        try:
            data = build_beacon()
            for target in targets:
                try:
                    sock.sendto(data, target)
                except OSError:
                    # Interface down (wlan1 settling after boot, or the DTN
                    # radio unplugged): keep beaconing attempts, do not crash.
                    pass
        except Exception as e:  # noqa: BLE001  daemon must survive anything
            audit_logger.warning(f"BEACON_TX_ERROR | reason={type(e).__name__}")
        _stop.wait(config.BEACON_INTERVAL)


def beacon_rx_loop():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((config.BEACON_BIND, config.BEACON_PORT))
    sock.settimeout(1.0)
    while not _stop.is_set():
        try:
            data, addr = sock.recvfrom(4096)
        except socket.timeout:
            continue
        except OSError:
            time.sleep(1)
            continue
        try:
            parse_and_accept_beacon(data, addr[0])
        except Exception as e:  # noqa: BLE001
            audit_logger.warning(f"BEACON_RX_ERROR | reason={type(e).__name__}")


def sync_loop():
    import sync_engine
    while not _stop.is_set():
        try:
            peers = models.alive_peers(config.PEER_EXPIRY)
            for peer in peers:
                sync_engine.sync_with_peer(peer)
        except Exception as e:  # noqa: BLE001
            audit_logger.warning(f"SYNC_LOOP_ERROR | reason={type(e).__name__}")
        _stop.wait(config.SYNC_INTERVAL)


def main():
    models.init_db()
    audit_logger.info(
        f"SYNC_DAEMON_START | node={config.NODE_ID} | beacon_port={config.BEACON_PORT} | "
        f"interval={config.SYNC_INTERVAL}"
    )
    threads = [
        threading.Thread(target=beacon_tx_loop, name="beacon-tx", daemon=True),
        threading.Thread(target=beacon_rx_loop, name="beacon-rx", daemon=True),
        threading.Thread(target=sync_loop, name="sync", daemon=True),
    ]
    for t in threads:
        t.start()
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        _stop.set()
        audit_logger.info("SYNC_DAEMON_STOP")


if __name__ == "__main__":
    main()
