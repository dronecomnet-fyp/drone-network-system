#!/bin/bash
# local_two_node_test.sh: run TWO complete backend nodes on loopback and
# prove the file 02 acceptance behaviors without hardware:
#
#   1. message / personnel / announcement / gs_message / checkin created on
#      one node converge to the other (all five replicated tables)
#   2. PIN issued on A logs in on B; claim on B carries the identity back
#      to A; revoke on A blocks login on B after sync
#   3. kill -9 one API mid-operation: the peer logs SYNC_FAIL and keeps
#      going; after restart there are no duplicates (distinct PK == rows)
#
# Loopback specifics: beacons are UNICAST via BEACON_TARGETS (127.0.0.1
# has no broadcast), each node gets its own beacon port, and TLS is off
# (SYNC_SCHEME=http). On real nodes deploy/ enables broadcast + TLS.
#
# Usage: tools/local_two_node_test.sh   (from the repo root; needs the
# backend venv at backend/.venv)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$REPO_DIR/backend"
PY="$BACKEND/.venv/bin/python"
WORK="$(mktemp -d /tmp/two_node_test.XXXXXX)"
MASTER="two_node_test_master_$(date +%s)"

A_API=18443; A_HTTP=18081; A_BEACON=48601
B_API=18444; B_HTTP=18082; B_BEACON=48602
RESCUE_KEY=tk_rescue; HQ_KEY=tk_hq

PIDS=()
cleanup() {
    for pid in "${PIDS[@]}"; do kill -9 "$pid" 2>/dev/null || true; done
    wait 2>/dev/null || true
}
trap cleanup EXIT

make_env() {  # $1 node letter, $2 api port, $3 http port, $4 beacon port, $5 peer beacon port
    local dir="$WORK/node_$1"
    mkdir -p "$dir"
    cat > "$dir/node.env" <<EOF
NODE_ID=DRONE_$1
USER_AP_SSID=RESCUE_$1
DTN_IP=127.0.0.1
API_HOST=127.0.0.1
API_PORT=$2
HTTP_HOST=127.0.0.1
HTTP_PORT=$3
DB_FILE=$dir/mesh.db
AUDIT_LOG_FILE=$dir/audit.log
AUX_STATE_FILE=$dir/aux_state.json
NODE_MASTER_SECRET=$MASTER
RESCUE_API_KEY=$RESCUE_KEY
HQ_API_KEY=$HQ_KEY
API_TLS_ENABLED=false
SYNC_SCHEME=http
SYNC_VERIFY_TLS=false
BEACON_BIND=127.0.0.1
BEACON_PORT=$4
BEACON_TARGETS=127.0.0.1:$5
BEACON_INTERVAL=2
PEER_EXPIRY=10
SYNC_INTERVAL=3
AUX_SERIAL=
EOF
    echo "$dir"
}

start_node() {  # $1 dir, $2 which (api|sync|http)
    local dir="$1" what="$2"
    ( cd "$dir" && NODE_ENV_FILE="$dir/node.env" exec "$PY" "$BACKEND/${what}.py" \
        > "$dir/${what}.log" 2>&1 ) &
    PIDS+=($!)
    echo $!
}

wait_http() {  # $1 url, $2 label
    for _ in $(seq 1 50); do
        if curl -sf "$1" >/dev/null 2>&1; then return 0; fi
        sleep 0.3
    done
    echo "FATAL: $2 never came up ($1)"; exit 1
}

jqget() { "$PY" -c "import json,sys; print(json.load(sys.stdin)$1)"; }

wait_for() {  # $1 seconds, $2 description, $3 command that must exit 0
    local deadline=$((SECONDS + $1))
    while (( SECONDS < deadline )); do
        if eval "$3" >/dev/null 2>&1; then echo "  ok: $2"; return 0; fi
        sleep 1
    done
    echo "FAIL: timed out waiting for: $2"
    return 1
}

echo "=== two-node local sync test (workdir $WORK) ==="
A_DIR=$(make_env A "$A_API" "$A_HTTP" "$A_BEACON" "$B_BEACON")
B_DIR=$(make_env B "$B_API" "$B_HTTP" "$B_BEACON" "$A_BEACON")

echo "[1] starting node A (api/http/sync) and node B (api/http/sync)"
A_API_PID=$(start_node "$A_DIR" api)
start_node "$A_DIR" http_app >/dev/null
start_node "$A_DIR" sync_daemon >/dev/null
start_node "$B_DIR" api >/dev/null
start_node "$B_DIR" http_app >/dev/null
start_node "$B_DIR" sync_daemon >/dev/null

wait_http "http://127.0.0.1:$A_API/health" "node A api"
wait_http "http://127.0.0.1:$B_API/health" "node B api"
wait_http "http://127.0.0.1:$A_HTTP/" "node A portal"
wait_http "http://127.0.0.1:$B_HTTP/" "node B portal"

echo "[2] creating artifacts: victim msg on A, personnel on A, announcement on A, gs report on B, checkin on B"
MSG_ID=$(curl -sf -X POST "http://127.0.0.1:$A_HTTP/message" \
    -H 'Content-Type: application/json' \
    -d '{"content":"trapped near river bend","user_lat":6.91,"user_lon":79.86,"victim_device_id":"vt-1"}' | jqget "['msg_id']")
PERS=$(curl -sf -X POST "http://127.0.0.1:$A_API/personnel" \
    -H "X-API-Key: $HQ_KEY" -H 'Content-Type: application/json' \
    -d '{"name":"Test Rescuer","role":"RESCUE_TEAM"}')
PID_=$(echo "$PERS" | jqget "['personnel_id']")
PIN_=$(echo "$PERS" | jqget "['pin']")
curl -sf -X POST "http://127.0.0.1:$A_API/announcements" \
    -H "X-API-Key: $HQ_KEY" -H 'Content-Type: application/json' \
    -d '{"title":"Muster point","body":"School grounds at 0800","priority":"HIGH"}' >/dev/null
curl -sf -X POST "http://127.0.0.1:$B_API/gs-uplink" \
    -H "X-API-Key: $RESCUE_KEY" -H 'Content-Type: application/json' \
    -d '{"content":"road blocked at km 3","location_lat":6.95,"location_lon":79.9}' >/dev/null
curl -sf -X POST "http://127.0.0.1:$B_HTTP/checkin" \
    -H 'Content-Type: application/json' \
    -d '{"device_id":"emg-9","sos":false,"points":[{"lat":6.9,"lon":79.8,"accuracy":9.0,"recorded_at":"2026-07-11T05:00:00Z"}]}' >/dev/null

echo "[3] waiting for convergence (beacons 2 s, sync every 3 s)"
FAILED=0
wait_for 30 "A's message visible on B" \
    "curl -sf -H 'X-API-Key: $RESCUE_KEY' http://127.0.0.1:$B_API/messages | grep -q '$MSG_ID'" || FAILED=1
wait_for 30 "A's announcement visible on B" \
    "curl -sf -H 'X-API-Key: $RESCUE_KEY' http://127.0.0.1:$B_API/announcements | grep -q 'Muster point'" || FAILED=1
wait_for 30 "B's gs report visible on A" \
    "curl -sf -H 'X-API-Key: $HQ_KEY' http://127.0.0.1:$A_API/gs-messages | grep -q 'road blocked'" || FAILED=1
wait_for 30 "B's checkin visible on A (sqlite)" \
    "sqlite3 '$A_DIR/mesh.db' \"SELECT COUNT(*) FROM checkins WHERE device_id='emg-9'\" | grep -q '^1$'" || FAILED=1

echo "[4] PIN issued on A logs in on B (personnel synced with hashes)"
TOKEN=""
if wait_for 30 "personnel record on B" \
    "sqlite3 '$B_DIR/mesh.db' \"SELECT COUNT(*) FROM personnel WHERE personnel_id='$PID_'\" | grep -q '^1$'"; then
    TOKEN=$(curl -sf -X POST "http://127.0.0.1:$B_API/auth/login" \
        -H 'Content-Type: application/json' \
        -d "{\"personnel_id\":\"$PID_\",\"pin\":\"$PIN_\"}" | jqget "['token']") || true
fi
if [[ -n "$TOKEN" ]]; then echo "  ok: login on B with PIN from A"; else echo "FAIL: login on B"; FAILED=1; fi

echo "[5] claim on B with the token; claimed_by must reach A"
curl -sf -X POST "http://127.0.0.1:$B_API/messages/$MSG_ID/claim" \
    -H "X-Session-Token: $TOKEN" -H 'Content-Type: application/json' -d '{}' >/dev/null || FAILED=1
wait_for 30 "claim with identity visible on A" \
    "sqlite3 '$A_DIR/mesh.db' \"SELECT claimed_by FROM messages WHERE msg_id='$MSG_ID'\" | grep -q '$PID_'" || FAILED=1

echo "[6] kill -9 node A's API mid-operation; B must log SYNC_FAIL and survive"
kill -9 "$A_API_PID" 2>/dev/null || true
sleep 8
if grep -q "SYNC_FAIL" "$B_DIR/audit.log"; then
    echo "  ok: B logged SYNC_FAIL and kept running"
else
    echo "FAIL: no SYNC_FAIL logged on B"; FAILED=1
fi
A_API_PID=$(start_node "$A_DIR" api)
wait_http "http://127.0.0.1:$A_API/health" "node A api (restarted)"

echo "[7] revoke on A blocks login on B after sync"
curl -sf -X POST "http://127.0.0.1:$A_API/personnel/$PID_/revoke" -H "X-API-Key: $HQ_KEY" >/dev/null || FAILED=1
wait_for 30 "revocation visible on B" \
    "sqlite3 '$B_DIR/mesh.db' \"SELECT status FROM personnel WHERE personnel_id='$PID_'\" | grep -q REVOKED" || FAILED=1
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$B_API/auth/login" \
    -H 'Content-Type: application/json' -d "{\"personnel_id\":\"$PID_\",\"pin\":\"$PIN_\"}")
if [[ "$HTTP_CODE" == "401" ]]; then echo "  ok: revoked login rejected on B"; else echo "FAIL: revoked login returned $HTTP_CODE"; FAILED=1; fi

echo "[8] duplicate check after crash/recovery (distinct PK == row count)"
for tbl_pk in "messages msg_id" "personnel personnel_id" "announcements id" "gs_messages id" "checkins id"; do
    set -- $tbl_pk
    for db in "$A_DIR/mesh.db" "$B_DIR/mesh.db"; do
        rows=$(sqlite3 "$db" "SELECT COUNT(*) FROM $1")
        distinct=$(sqlite3 "$db" "SELECT COUNT(DISTINCT $2) FROM $1")
        if [[ "$rows" != "$distinct" ]]; then
            echo "FAIL: duplicates in $1 of $db ($rows rows, $distinct distinct)"; FAILED=1
        fi
    done
done
echo "  ok: no duplicate primary keys anywhere"

echo ""
if [[ "$FAILED" == "0" ]]; then
    echo "=== TWO-NODE TEST: PASS (logs kept in $WORK) ==="
else
    echo "=== TWO-NODE TEST: FAIL (inspect $WORK) ==="
    exit 1
fi
