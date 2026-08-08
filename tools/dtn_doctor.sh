#!/bin/bash
# dtn_doctor.sh: work out why this node has no mesh, in one command.
#
# Run on a node:  sudo bash tools/dtn_doctor.sh
#
# Why this exists. An absent or misconfigured wlan1 has now presented as a
# "sync problem" three separate times (CHANGES items 40, 49, 50), and each
# time it cost hours. The reason it is so confusing is that the symptom is
# SILENCE: a node with no peers logs SYNC_OK with imported=0, which reads
# exactly like a healthy node with nothing to do.
#
# This checks every link in the chain from "is the adapter plugged in" to
# "are we actually syncing", stops at the first broken one, and prints the
# command that fixes it. It changes nothing by itself.

CHECK=0
FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { printf '  [ OK ]  %s\n' "$*"; }
bad()  { printf '  [FAIL]  %s\n' "$*"; FAIL=1; }
warn() { printf '  [ ?? ]  %s\n' "$*"; }
step() { CHECK=$((CHECK+1)); printf '\n%d. %s\n' "$CHECK" "$*"; }

fix() {
    printf '\n----------------------------------------------------------\n'
    printf 'DIAGNOSIS\n\n  %s\n\nFIX\n\n' "$1"
    shift
    for line in "$@"; do printf '  %s\n' "$line"; done
    printf '\n----------------------------------------------------------\n'
    exit 1
}

say "=========================================================="
say " DTN mesh doctor        node: $(hostname)        $(date +%T)"
say "=========================================================="

# --- 1. is the adapter physically there ---------------------------------
step "USB WiFi adapter present?"
if lsusb 2>/dev/null | grep -qi "atheros\|ath9k\|0cf3:9271"; then
    ok "AR9271 seen on the USB bus"
else
    warn "no Atheros device in lsusb (some clones report a different name)"
fi

if ! ip link show wlan1 >/dev/null 2>&1; then
    bad "there is no interface called wlan1"
    say ""
    say "  Interfaces that DO exist:"
    ip -brief link show | sed 's/^/    /'
    say ""
    OTHER=$(ip -brief link show | awk '$1 ~ /^wl/ && $1 != "wlan0" && $1 != "wlan1" {print $1}' | head -1)
    if [ -n "$OTHER" ]; then
        MAC=$(cat "/sys/class/net/$OTHER/address" 2>/dev/null)
        fix "The adapter is plugged in but came up as '$OTHER', not wlan1. Each node pins its adapter to the name wlan1 BY MAC ADDRESS, and this adapter's MAC ($MAC) is not in this node's config. This happens after swapping adapters between nodes." \
            "Edit this node's conf and add the MAC as the second accepted adapter:" \
            "" \
            "    nano ~/rescue-mesh/deploy/nodes/drone_X.conf" \
            "      DTN_MAC_ALT=$MAC" \
            "" \
            "    cd ~/rescue-mesh/deploy && sudo ./setup_node.sh X" \
            "    sudo reboot"
    fi
    fix "No USB WiFi adapter is visible to the kernel at all." \
        "Reseat the adapter, then:  dmesg | tail -20" \
        "If dmesg shows ath9k_htc firmware errors, install the firmware:" \
        "    sudo apt install firmware-ath9k-htc" \
        "" \
        "If it worked a moment ago and has now vanished, this is the USB" \
        "brownout from CHANGES item 40. Power the node from a 3 A supply," \
        "not the battery pack."
fi
ok "wlan1 exists (MAC $(cat /sys/class/net/wlan1/address 2>/dev/null))"

# --- 2. is the bring-up script installed --------------------------------
step "Bring-up script installed?"
if [ -x /usr/local/sbin/dtn-net-up.sh ]; then
    ok "/usr/local/sbin/dtn-net-up.sh present and executable"
else
    fix "The IBSS bring-up script is not installed, so nothing has ever configured wlan1." \
        "    cd ~/rescue-mesh/deploy && sudo ./setup_node.sh X    # a, b or s"
fi

if [ -f /etc/rescue-mesh/dtn_ip ]; then
    ok "DTN address configured: $(cat /etc/rescue-mesh/dtn_ip)"
else
    fix "/etc/rescue-mesh/dtn_ip is missing, so the script cannot assign an address." \
        "    cd ~/rescue-mesh/deploy && sudo ./setup_node.sh X"
fi

# --- 3. is NetworkManager staying out of the way ------------------------
step "Is NetworkManager leaving wlan1 alone?"
if command -v nmcli >/dev/null 2>&1; then
    STATE=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep '^wlan1:' | cut -d: -f2)
    case "$STATE" in
        unmanaged) ok "NetworkManager reports wlan1 as unmanaged, correct" ;;
        "")        warn "NetworkManager does not list wlan1" ;;
        *)         bad "NetworkManager is managing wlan1 (state: $STATE)"
                   fix "NetworkManager has control of wlan1 and will keep forcing it back to managed mode, undoing the IBSS setup." \
                       "The config that prevents this exists but has not been applied:" \
                       "    sudo cp ~/rescue-mesh/deploy/files/unmanaged-dtn.conf \\" \
                       "            /etc/NetworkManager/conf.d/unmanaged-dtn.conf" \
                       "    sudo systemctl reload NetworkManager" \
                       "    sudo systemctl restart dtn-net" ;;
    esac
else
    ok "NetworkManager not installed, nothing to fight over the interface"
fi

# --- 4. the dtn-net unit ------------------------------------------------
step "dtn-net service state?"
ACTIVE=$(systemctl is-active dtn-net 2>/dev/null)
ENABLED=$(systemctl is-enabled dtn-net 2>/dev/null)
say "     active: $ACTIVE     enabled: $ENABLED"
if [ "$ACTIVE" = "failed" ]; then
    bad "dtn-net is in the failed state"
    say ""
    systemctl status dtn-net --no-pager -n 8 2>/dev/null | sed 's/^/    /'
    fix "dtn-net tried to configure wlan1 and failed. The log above says why." \
        "Most often the adapter was not present when it ran. Now that it is:" \
        "    sudo systemctl restart dtn-net" \
        "" \
        "If it fails again immediately, run the script by hand to see the" \
        "actual error:" \
        "    sudo /usr/local/sbin/dtn-net-up.sh"
fi

# --- 5. the interface mode: the one that catches people -----------------
step "Is wlan1 actually in IBSS mode?"
TYPE=$(iw dev wlan1 info 2>/dev/null | awk '/^\ttype/ {print $2}')
say "     type: ${TYPE:-unknown}"
if [ "$TYPE" = "IBSS" ]; then
    ok "wlan1 is in IBSS (ad-hoc) mode"
else
    bad "wlan1 is in '$TYPE' mode, not IBSS"
    fix "The adapter exists with the right name, but nothing has switched it into ad-hoc mode. dtn-net has not run successfully since this adapter appeared. This is the usual state after plugging an adapter into a node that was already running: the old dtn-net was a boot-time oneshot and never re-ran." \
        "Right now:" \
        "    sudo systemctl restart dtn-net" \
        "    iw dev wlan1 info        # expect: type IBSS" \
        "" \
        "So it never happens again, apply the hotplug fix (CHANGES item 50):" \
        "    cd ~/rescue-mesh && git pull" \
        "    cd deploy && sudo ./setup_node.sh X" \
        "    sudo reboot"
fi

# --- 6. joined the right cell -------------------------------------------
step "Joined the RESCUE_DTN cell?"
LINKINFO=$(iw dev wlan1 link 2>/dev/null)
if echo "$LINKINFO" | grep -qi "not connected"; then
    warn "wlan1 is in IBSS mode but reports 'not connected'"
    say "     With IBSS this can be normal when no other node is in range."
else
    ok "$(echo "$LINKINFO" | head -2 | tr '\n' ' ')"
fi

IPADDR=$(ip -4 addr show wlan1 2>/dev/null | awk '/inet /{print $2}')
if [ -n "$IPADDR" ]; then
    ok "address assigned: $IPADDR"
else
    bad "wlan1 has no IPv4 address"
    fix "The interface is up but has no address, so nothing can reach it." \
        "    sudo systemctl restart dtn-net"
fi

# --- 7. can we see anybody ----------------------------------------------
step "Any peers visible?"
HEALTH=$(curl -sk --max-time 5 https://127.0.0.1:8443/health 2>/dev/null)
if [ -z "$HEALTH" ]; then
    bad "the API did not answer on 127.0.0.1:8443"
    fix "The node's own API is not responding, so peer state cannot be read." \
        "    sudo systemctl status rescue-mesh-api" \
        "    sudo systemctl restart rescue-mesh-api"
fi

PEERS=$(printf '%s' "$HEALTH" | grep -o '"node_id":"[^"]*"' | sed 's/.*:"//;s/"//' | tail -n +2 | tr '\n' ' ')
if [ -n "$PEERS" ]; then
    ok "peers seen: $PEERS"
else
    warn "no peers visible right now"
    say ""
    say "     This is NOT necessarily wrong. The network is delay tolerant,"
    say "     so nodes are often out of contact. But everything above passed,"
    say "     so if another node SHOULD be in range, check on that node:"
    say ""
    say "       sudo bash tools/dtn_doctor.sh"
    say ""
    say "     Both ends must be in IBSS mode on the same cell to see each"
    say "     other. One node alone can never show a peer."
fi

# --- 8. is the sync loop running ----------------------------------------
step "Sync daemon running and logging?"
if [ "$(systemctl is-active rescue-mesh-sync)" = "active" ]; then
    ok "rescue-mesh-sync is active"
else
    bad "rescue-mesh-sync is not running"
    fix "The sync daemon is not running, so nothing will replicate even with a healthy mesh." \
        "    sudo systemctl status rescue-mesh-sync" \
        "    sudo systemctl restart rescue-mesh-sync"
fi

SYNCLINES=$(journalctl -u rescue-mesh-sync -n 60 --no-pager 2>/dev/null | grep -c "SYNC_OK\|SYNC_START")
say "     SYNC lines in the last 60 log entries: $SYNCLINES"
if [ "$SYNCLINES" -eq 0 ]; then
    say ""
    say "     No sync lines. If there are also no peers above, that is the"
    say "     explanation and it is consistent: the loop has nobody to sync"
    say "     with, so it logs nothing. It is NOT a missing table."
else
    TABLES=$(journalctl -u rescue-mesh-sync -n 200 --no-pager 2>/dev/null \
             | grep -o "table=[a-z_]*" | sort -u | sed 's/table=//' | tr '\n' ' ')
    ok "tables seen syncing: $TABLES"
    if ! printf '%s' "$TABLES" | grep -q lora_events; then
        say ""
        warn "lora_events is NOT among them"
        fix "The sync loop is running but does not know about the lora_events table, which means this node is running code from before that update." \
            "    cd ~/rescue-mesh && git pull" \
            "    sudo systemctl restart rescue-mesh-api rescue-mesh-sync rescue-mesh-auxbridge"
    fi
fi

printf '\n----------------------------------------------------------\n'
if [ "$FAIL" -eq 0 ]; then
    say "No faults found in the mesh chain on this node."
    if [ -z "$PEERS" ]; then
        say "No peers, but everything on THIS node is configured correctly."
        say "Run the same check on the other node."
    fi
else
    say "Something above failed. Fix the first failure and re-run."
fi
printf -- '----------------------------------------------------------\n'
