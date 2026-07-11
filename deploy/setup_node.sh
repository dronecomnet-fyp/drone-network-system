#!/bin/bash
# setup_node.sh: turn a fresh Raspberry Pi OS Lite (64-bit, Bookworm) into
# a rescue mesh node (file 01; file 09 tasks folded in). Run ON the Pi:
#
#   sudo ./setup_node.sh a|b|s
#
# Prerequisites (file 01 steps 0-1, manual):
#   - old card imaged/preserved, ONE original kept as rollback
#   - Imager settings: hostname drone-a/b/s, SSH key auth, user "drone",
#     no WiFi preconfigured, locale/timezone Asia/Colombo
#   - repo cloned to /home/drone/rescue-mesh
#   - deploy/secrets/ copied from the operator laptop (make_fleet_ca.sh)
#
# The script is re-runnable: existing .link files, node.env, and certs are
# regenerated from the same inputs. A reboot is required after the first
# run for interface pinning and the Bluetooth overlay to take effect.

set -euo pipefail

# --- Arguments and paths ------------------------------------------------------

NODE_LETTER="${1:-}"
if [[ ! "$NODE_LETTER" =~ ^[abs]$ ]]; then
    echo "Usage: sudo $0 a|b|s"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$REPO_DIR/backend"
CONF_FILE="$SCRIPT_DIR/nodes/drone_${NODE_LETTER}.conf"
SECRETS_DIR="$SCRIPT_DIR/secrets"
SERVICE_USER=drone

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run with sudo."
    exit 1
fi
if [[ ! -f "$CONF_FILE" ]]; then
    echo "ERROR: node config not found: $CONF_FILE"
    exit 1
fi
if [[ ! -f "$SECRETS_DIR/fleet_secrets.env" || ! -f "$SECRETS_DIR/fleet_ca.key" ]]; then
    echo "ERROR: $SECRETS_DIR is missing fleet trust material."
    echo "Run deploy/make_fleet_ca.sh ONCE on the operator laptop and copy"
    echo "deploy/secrets/ to this Pi (file 09 plane 2)."
    exit 1
fi

# shellcheck source=/dev/null
source "$CONF_FILE"
# shellcheck source=/dev/null
source "$SECRETS_DIR/fleet_secrets.env"

echo "=== Rescue mesh node setup: $NODE_ID ==="

# --- Step 2 (file 01): verify the network stack, do not assume ----------------

echo "[Step 2] Verifying network stack assumptions"
if [[ "$(systemctl is-active NetworkManager)" != "active" ]]; then
    echo "ERROR: NetworkManager is not active. Bookworm is expected to use"
    echo "NetworkManager; install/enable it first (old rpi_setup_plan Step 0)."
    exit 1
fi
if [[ "$(systemctl is-active dhcpcd 2>/dev/null || true)" == "active" ]]; then
    echo "ERROR: dhcpcd is active; it conflicts with NetworkManager."
    echo "Disable it (systemctl disable --now dhcpcd) and re-run."
    exit 1
fi

echo "[Step 2] Checking AR9271 (ath9k_htc) presence"
if ! lsusb | grep -qi "atheros\|0cf3:"; then
    echo "WARNING: no Atheros USB device visible in lsusb. Plug in the"
    echo "AR9271 adapter. Continuing (the .link file still gets written"
    echo "if DTN_MAC is set in the conf)."
fi
if ! dmesg | grep -qi "ath9k_htc.*firmware\|htc_9271" ; then
    echo "NOTE: ath9k_htc firmware not seen in dmesg yet. If wlan1 never"
    echo "appears, install the firmware package (Debian: firmware-ath9k-htc;"
    echo "confidence Moderate, record the exact package in VERIFY.md)."
fi

echo "[Step 2] Setting WiFi regulatory domain LK (master plan R3)"
raspi-config nonint do_wifi_country LK || iw reg set LK

# --- Step 3 (file 01): pin interface names by MAC -----------------------------

echo "[Step 3] Pinning interface names (wlan0=onboard, wlan1=AR9271)"
detect_mac() {
    # $1 = sysfs match: "onboard" (mmc/soc) or "usb"
    local kind="$1" iface mac
    for iface in /sys/class/net/wl*; do
        [[ -e "$iface" ]] || continue
        local devpath
        devpath="$(readlink -f "$iface/device" 2>/dev/null || true)"
        mac="$(cat "$iface/address")"
        if [[ "$kind" == "usb" && "$devpath" == *usb* ]]; then
            echo "$mac"; return 0
        elif [[ "$kind" == "onboard" && "$devpath" != *usb* ]]; then
            echo "$mac"; return 0
        fi
    done
    return 1
}

if [[ -z "${ONBOARD_MAC:-}" ]]; then
    ONBOARD_MAC="$(detect_mac onboard || true)"
    [[ -n "$ONBOARD_MAC" ]] && echo "  detected onboard MAC: $ONBOARD_MAC"
fi
if [[ -z "${DTN_MAC:-}" ]]; then
    DTN_MAC="$(detect_mac usb || true)"
    [[ -n "$DTN_MAC" ]] && echo "  detected AR9271 MAC:  $DTN_MAC"
fi
if [[ -z "$ONBOARD_MAC" || -z "$DTN_MAC" ]]; then
    echo "ERROR: could not determine both MACs. Fill ONBOARD_MAC and"
    echo "DTN_MAC in $CONF_FILE and re-run (file 01 step 3)."
    exit 1
fi

mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-onboard-wifi.link <<EOF
[Match]
MACAddress=$ONBOARD_MAC
[Link]
Name=wlan0
EOF
cat > /etc/systemd/network/11-dtn-wifi.link <<EOF
[Match]
MACAddress=$DTN_MAC
[Link]
Name=wlan1
EOF
echo "  .link files written (take effect at reboot; verify with ip link)"

# --- Step 6 (file 01): base software (done early so later steps have tools) ---

echo "[Step 6] Installing base packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    git python3 python3-venv python3-pip sqlite3 openssl iw nftables

echo "[Step 6] Python venv + pinned requirements"
sudo -u "$SERVICE_USER" python3 -m venv "$BACKEND_DIR/.venv"
sudo -u "$SERVICE_USER" "$BACKEND_DIR/.venv/bin/pip" install -q --upgrade pip
sudo -u "$SERVICE_USER" "$BACKEND_DIR/.venv/bin/pip" install -q \
    -r "$BACKEND_DIR/requirements.txt"

# --- Step 7 (file 01) + file 09: per-node configuration and trust material ----

echo "[Step 7] Writing /etc/rescue-mesh/node.env"
mkdir -p /etc/rescue-mesh
echo "$DTN_IP" > /etc/rescue-mesh/dtn_ip

KEYS_DIR="$BACKEND_DIR/keys"
mkdir -p "$KEYS_DIR"

echo "[Step 7] Issuing node TLS certificate from the fleet CA (file 09 plane 2)"
openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
    -keyout "$KEYS_DIR/node_key.pem" -out "$KEYS_DIR/node.csr" \
    -subj "/CN=$NODE_ID" 2>/dev/null
cat > "$KEYS_DIR/node_ext.cnf" <<EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:10.42.0.1,IP:$DTN_IP
EOF
openssl x509 -req -in "$KEYS_DIR/node.csr" \
    -CA "$SECRETS_DIR/fleet_ca.crt" -CAkey "$SECRETS_DIR/fleet_ca.key" \
    -CAcreateserial -days 730 \
    -extfile "$KEYS_DIR/node_ext.cnf" \
    -out "$KEYS_DIR/node_cert.pem" 2>/dev/null
cp "$SECRETS_DIR/fleet_ca.crt" "$KEYS_DIR/fleet_ca.crt"
rm -f "$KEYS_DIR/node.csr" "$KEYS_DIR/node_ext.cnf"
chown -R "$SERVICE_USER:$SERVICE_USER" "$KEYS_DIR"
chmod 600 "$KEYS_DIR/node_key.pem"

cat > /etc/rescue-mesh/node.env <<EOF
# Generated by setup_node.sh $(date -u +%Y-%m-%dT%H:%M:%SZ). chmod 600.
# Fleet secrets come from deploy/secrets/fleet_secrets.env (identical
# fleet-wide); rotation runbook: backend docs SECRETS_ROTATION.md.
NODE_ID=$NODE_ID
USER_AP_SSID=$USER_AP_SSID
DTN_IP=$DTN_IP
DTN_PEERS=$DTN_PEERS

API_HOST=0.0.0.0
API_PORT=8443
HTTP_HOST=0.0.0.0
HTTP_PORT=80

DB_FILE=/home/drone/rescue-mesh/backend/drone_mesh.db
AUDIT_LOG_FILE=/home/drone/rescue-mesh/backend/audit.log

NODE_MASTER_SECRET=$NODE_MASTER_SECRET
RESCUE_API_KEY=$RESCUE_API_KEY
HQ_API_KEY=$HQ_API_KEY

API_TLS_ENABLED=true
API_TLS_CERT=/home/drone/rescue-mesh/backend/keys/node_cert.pem
API_TLS_KEY=/home/drone/rescue-mesh/backend/keys/node_key.pem
API_MTLS_ENABLED=false
API_MTLS_CA_CERT=/home/drone/rescue-mesh/backend/keys/fleet_ca.crt

BEACON_ADDR=10.99.0.255
BEACON_PORT=48555
BEACON_INTERVAL=10
PEER_EXPIRY=35
SYNC_INTERVAL=30
SYNC_SCHEME=https
SYNC_VERIFY_TLS=true
SYNC_CA_CERT=/home/drone/rescue-mesh/backend/keys/fleet_ca.crt

AUX_SERIAL=$AUX_SERIAL
AUX_STATE_FILE=/run/rescue-mesh/aux_state.json

DRONE_CONTROL=$DRONE_CONTROL
FC_SERIAL=$FC_SERIAL

E2E_ENABLED=false
E2E_ENCRYPTION_REQUIRED=false
EOF
chmod 600 /etc/rescue-mesh/node.env

# --- Step 4 (file 01): wlan0 user AP via NetworkManager shared mode -----------

echo "[Step 4] Configuring 5 GHz user AP ($USER_AP_SSID, channel $USER_AP_CHANNEL)"
nmcli con delete USER_AP >/dev/null 2>&1 || true
nmcli con add type wifi ifname wlan0 con-name USER_AP autoconnect yes \
    ssid "$USER_AP_SSID"
nmcli con modify USER_AP 802-11-wireless.mode ap 802-11-wireless.band a \
    802-11-wireless.channel "$USER_AP_CHANNEL" \
    ipv4.method shared ipv4.addresses 10.42.0.1/24 \
    802-11-wireless.powersave 2
# Open network is intentional for victims (file 01 step 4): documented
# design property; app-layer controls compensate (file 09 plane 1).

echo "[Step 4] Captive portal DNS wildcard"
mkdir -p /etc/NetworkManager/dnsmasq-shared.d
cp "$SCRIPT_DIR/files/portal.conf" /etc/NetworkManager/dnsmasq-shared.d/portal.conf

# --- Step 5 (file 01): wlan1 IBSS DTN backbone --------------------------------

echo "[Step 5] Configuring IBSS DTN backbone on wlan1"
mkdir -p /etc/NetworkManager/conf.d
cp "$SCRIPT_DIR/files/unmanaged-dtn.conf" /etc/NetworkManager/conf.d/unmanaged-dtn.conf
install -m 755 "$SCRIPT_DIR/files/dtn-net-up.sh" /usr/local/sbin/dtn-net-up.sh

# --- Step 8 (file 01): services, sudoers, firewall, Bluetooth off --------------

echo "[Step 8] Installing systemd units"
for unit in rescue-mesh-runtime dtn-net rescue-mesh-api rescue-portal \
            rescue-mesh-sync rescue-mesh-auxbridge rescue-mesh-firewall; do
    cp "$SCRIPT_DIR/systemd/$unit.service" "/etc/systemd/system/$unit.service"
done

echo "[Step 8] Narrow sudoers entry for GPS clock set (file 02 task 2.2)"
install -m 440 "$SCRIPT_DIR/files/rescue-mesh-sudoers" /etc/sudoers.d/rescue-mesh
visudo -c >/dev/null

echo "[Step 8] Firewall rules for this node role (file 09 plane 4 layer 1)"
if [[ "$DRONE_CONTROL" == "true" ]]; then
    cp "$SCRIPT_DIR/files/nftables-drone-s.nft" /etc/rescue-mesh/nftables.nft
else
    cp "$SCRIPT_DIR/files/nftables-volunteer.nft" /etc/rescue-mesh/nftables.nft
fi
echo 1 > /proc/sys/net/ipv4/ip_forward || true
sed -i 's/^#\?net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

echo "[Step 8] Disabling Pi Bluetooth (master plan D3: BLE lives on the aux module)"
BOOT_CONFIG=/boot/firmware/config.txt
[[ -f "$BOOT_CONFIG" ]] || BOOT_CONFIG=/boot/config.txt   # older layouts
grep -q '^dtoverlay=disable-bt' "$BOOT_CONFIG" || echo 'dtoverlay=disable-bt' >> "$BOOT_CONFIG"
systemctl disable --now hciuart >/dev/null 2>&1 || true

echo "[Step 8] Enabling services"
systemctl daemon-reload
systemctl enable rescue-mesh-runtime dtn-net rescue-mesh-api rescue-portal \
    rescue-mesh-sync rescue-mesh-auxbridge rescue-mesh-firewall >/dev/null

# RETIRED Phase 1 units must not exist (file 01 step 8, rule 5 disclosure):
for old in rescue-mesh-switcher rescue-mesh-ble; do
    systemctl disable --now "$old" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/$old.service"
done

echo ""
echo "=== Setup complete for $NODE_ID ==="
echo "REBOOT NOW (interface pinning + Bluetooth overlay), then run the"
echo "checks in deploy/VERIFY.md. Consider moving deploy/secrets/ off this"
echo "Pi once all three nodes are built (fleet_ca.key belongs offline)."
