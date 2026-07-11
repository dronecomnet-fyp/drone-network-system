#!/bin/bash
# make_fleet_ca.sh: generate the fleet trust material ONCE per fleet
# (file 09 plane 2 + F2). Run on the operator laptop, not on a node.
#
# Produces in deploy/secrets/ (gitignored, file 09 F4):
#   fleet_ca.key          CA private key (keep OFFLINE after node setup)
#   fleet_ca.crt          CA certificate: embedded by the rescue app and
#                         GCC for real pinning (evil twins fail closed)
#   fleet_secrets.env     NODE_MASTER_SECRET + break-glass API keys,
#                         identical fleet-wide (K_msg/K_sync/K_token are
#                         HKDF-derived from the master on each node)
#
# Re-running with the files present is refused: rotating the fleet trust
# is a deliberate act (SECRETS_ROTATION.md), pass --rotate to force.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$SCRIPT_DIR/secrets"
CA_DAYS=1095   # 3 years; prototype fleet, rotation runbook covers renewal

if [[ -f "$SECRETS_DIR/fleet_ca.key" && "${1:-}" != "--rotate" ]]; then
    echo "ERROR: $SECRETS_DIR already holds fleet trust material."
    echo "Rotating invalidates every node cert and secret (see"
    echo "SECRETS_ROTATION.md). Run again with --rotate if you mean it."
    exit 1
fi

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

echo "[1/3] Generating fleet CA key + certificate"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$SECRETS_DIR/fleet_ca.key" -out "$SECRETS_DIR/fleet_ca.crt" \
    -days "$CA_DAYS" -nodes \
    -subj "/CN=rescue-mesh-fleet-ca" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"

echo "[2/3] Generating fleet secrets"
{
    echo "# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by make_fleet_ca.sh"
    echo "# Identical fleet-wide; never commit (file 09 F4)."
    echo "NODE_MASTER_SECRET=$(openssl rand -hex 32)"
    echo "RESCUE_API_KEY=rk_$(openssl rand -hex 16)"
    echo "HQ_API_KEY=hk_$(openssl rand -hex 16)"
} > "$SECRETS_DIR/fleet_secrets.env"
chmod 600 "$SECRETS_DIR/fleet_secrets.env" "$SECRETS_DIR/fleet_ca.key"

echo "[3/3] Done. Copy deploy/secrets/ to each Pi for setup_node.sh, then"
echo "      store fleet_ca.key OFFLINE. fleet_ca.crt (public) is what the"
echo "      apps embed in packages 04/05."
