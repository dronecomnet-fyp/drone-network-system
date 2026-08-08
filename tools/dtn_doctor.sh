#!/bin/bash
# dtn_doctor.sh: work out why this node has no mesh, in one command.
#
# Run on a node:  sudo dtn-doctor
#   (setup_node.sh installs it to /usr/local/sbin/dtn-doctor, so it works
#    from any directory. Before that has been run, from the repo root:
#    sudo bash tools/dtn_doctor.sh)
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
ON_BUS=0
if lsusb 2>/dev/null | grep -qi "atheros\|ath9k\|0cf3:9271"; then
    ok "AR9271 seen on the USB bus"
    ON_BUS=1
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
    # On the bus but no network interface at all: the USB device
    # enumerated and the driver never produced a netdev. That is a driver
    # or firmware problem, not a missing adapter, and saying "no adapter"
    # here would contradict the line above.
    if [ "$ON_BUS" = "1" ] && [ -z "$(ip -brief link show | awk '$1 ~ /^wl/ && $1 != "wlan0" {print $1}')" ]; then
        say ""
        say "  ath9k_htc firmware lines in dmesg:"
        dmesg 2>/dev/null | grep -i "ath9k\|htc_9271\|firmware" | tail -8 | sed 's/^/    /'
        say ""
        if [ -f /lib/firmware/htc_9271.fw ]; then
            ok "/lib/firmware/htc_9271.fw is installed"
            fix "The adapter is on the USB bus and the firmware file exists, but no network interface was created. The driver failed to bind or the firmware failed to load." \
                "Look at the dmesg lines above for the actual error, then:" \
                "    sudo modprobe -r ath9k_htc && sudo modprobe ath9k_htc" \
                "    ip link show" \
                "" \
                "If dmesg mentions a USB transfer or power error, this is the" \
                "brownout from CHANGES item 40: power the node from a 3 A" \
                "supply rather than the battery pack, then reseat the adapter."
        else
            fix "The adapter IS on the USB bus, but the ath9k_htc firmware is not installed, so the kernel cannot bring it up and no network interface is created. This is why there is no wlan1 despite the hardware being plugged in." \
                "    sudo apt update" \
                "    sudo apt install -y firmware-ath9k-htc" \
                "    sudo modprobe -r ath9k_htc && sudo modprobe ath9k_htc" \
                "" \
                "Then check it appeared:" \
                "    ip link show          # expect wlan1" \
                "    iw dev wlan1 info     # expect type IBSS once dtn-net runs"
        fi
    fi

    if [ -n "$OTHER" ]; then
        MAC=$(cat "/sys/class/net/$OTHER/address" 2>/dev/null)
        DRV=$(basename "$(readlink -f "/sys/class/net/$OTHER/device/driver" 2>/dev/null)" 2>/dev/null)
        fix "The adapter is plugged in and working, but came up as '$OTHER' instead of wlan1 (MAC $MAC, driver ${DRV:-unknown}). The naming rule has not been applied on this node." \
            "Newer setups match wlan1 by DRIVER, so any AR9271 in any port" \
            "becomes wlan1 with nothing to configure. Apply it:" \
            "" \
            "    cd ~/rescue-mesh && git pull" \
            "    cd deploy && sudo ./setup_node.sh X       # a, b or s" \
            "    sudo reboot" \
            "" \
            "If the driver above is NOT ath9k_htc, tell the team: the match" \
            "rule in setup_node.sh assumes that driver name."
    fi
    # Nothing on the bus. The useful question is whether it was EVER on
    # the bus this boot: "never plugged in" and "was working and vanished"
    # look identical right now but have completely different fixes, and
    # the second one is the brownout that already cost this project an
    # evening.
    say ""
    say "  Everything currently on the USB bus:"
    lsusb 2>/dev/null | sed 's/^/    /'
    say ""

    SEEN=$(dmesg 2>/dev/null | grep -ci "ath9k_htc\|htc_9271")
    DROPPED=$(dmesg 2>/dev/null | grep -i "usb.*disconnect\|device descriptor read\|unable to enumerate\|device not accepting address" | tail -5)

    if [ "$SEEN" -gt 0 ]; then
        say "  ath9k_htc WAS active earlier this boot. Last USB events:"
        dmesg 2>/dev/null | grep -i "ath9k\|usb.*disconnect\|htc_9271" | tail -8 | sed 's/^/    /'
        fix "The adapter was working during this boot and has since disappeared from the USB bus. It did not fall out of the driver, it fell off the BUS, which is a power or connection fault rather than a software one. This is the exact failure from CHANGES item 40." \
            "In order of likelihood:" \
            "" \
            "  1. POWER. The Pi plus this adapter plus the aux module needs" \
            "     a 3 A class supply. A battery pack or a weak charger cannot" \
            "     sustain it and the adapter browns out and drops off." \
            "     Move to a known-good 3 A supply and reseat." \
            "" \
            "  2. A loose or damaged USB connection. Try a different port." \
            "" \
            "  3. A failing adapter. Try the other one to tell the two apart:" \
            "     if a second adapter survives in the same port and supply," \
            "     the first adapter is the fault."
    fi

    if [ -n "$DROPPED" ]; then
        say "  Recent USB errors in dmesg:"
        printf '%s\n' "$DROPPED" | sed 's/^/    /'
        say ""
    fi

    fix "No USB WiFi adapter has been seen on this node at all this boot. The kernel has never enumerated one, so this is almost certainly physical: nothing is plugged in, or what is plugged in is not powering up." \
        "  1. Confirm it is actually in THIS node. With fewer adapters than" \
        "     nodes, the usual answer is that it is in another one." \
        "" \
        "  2. Reseat it, then watch the kernel see it live:" \
        "         dmesg -w        # then unplug and replug the adapter" \
        "     Nothing appearing means no electrical connection at all." \
        "" \
        "  3. Try a different USB port and a 3 A supply." \
        "" \
        "  4. Try the other adapter in the same port. If that one enumerates," \
        "     the first adapter is dead."
fi
ok "wlan1 exists (MAC $(cat /sys/class/net/wlan1/address 2>/dev/null))"

# --- 1b. is the link STABLE, or is it flapping? -------------------------
#
# The interface existing right now says nothing about whether it stays.
# An adapter that drops off the bus every half minute passes every other
# check in this script between drops, and the first version of this tool
# printed "No faults found" for a node whose adapter had disconnected
# twice in the previous forty seconds. Silence about a flapping link is
# worse than no check at all.
step "Is the adapter link stable, or dropping off?"
DISC=$(dmesg 2>/dev/null | grep -c "usb 1-1.*: USB disconnect")
PORTERR=$(dmesg 2>/dev/null | grep -ci "Cannot enable. Maybe the USB cable is bad\|unable to enumerate USB device\|attempt power cycle")

say "     USB disconnect events this boot: $DISC"
say "     port enable failures this boot:  $PORTERR"

# Which physical port is the adapter in, and are the failures specific to
# ONE port or spread across several? That distinction is the whole
# diagnosis. Errors on one port mean that port is faulty and the fix is to
# move the adapter. Errors across several ports mean the supply cannot
# hold the load, which is a completely different problem with a completely
# different fix.
USBPATH=$(basename "$(dirname "$(readlink -f /sys/class/net/wlan1/device 2>/dev/null)")" 2>/dev/null)
case "$USBPATH" in
    *-*.*)  HUB="${USBPATH%.*}"; PORTNUM="${USBPATH##*.}"
            CURPORT="${HUB}-port${PORTNUM}" ;;
    *)      CURPORT="" ;;
esac
case "$USBPATH" in
    ""|"."|"/") ;;  # sysfs unreadable, say nothing rather than print junk
    *) say "     adapter is on USB path: $USBPATH${CURPORT:+  (that is $CURPORT)}" ;;
esac

BADPORTS=$(dmesg 2>/dev/null | grep -io "usb [0-9-]*-port[0-9]*: Cannot enable\|usb [0-9-]*-port[0-9]*: unable to enumerate" \
           | grep -o "[0-9-]*-port[0-9]*" | sort -u | tr '\n' ' ')
[ -n "$BADPORTS" ] && say "     ports reporting enable failures: $BADPORTS"
NBADPORTS=$(printf '%s' "$BADPORTS" | wc -w | tr -d ' ')

if [ "$PORTERR" -gt 0 ] && [ "$NBADPORTS" = "1" ]; then
    bad "one specific USB port is failing to enable devices"
    fix "The failures are all on a SINGLE port ($BADPORTS), not spread across the board. That is a faulty port, not a power problem. A port in this state typically works when the device is present at boot, because the hub powers every port once during startup, and then fails on replug, because a hot insert needs the port to do its own powered reset and this one cannot." \
        "  1. MOVE THE ADAPTER to a different port and leave it there." \
        "     Confirm with an unplug and replug: a good port re-enumerates" \
        "     within a couple of seconds." \
        "" \
        "  2. LABEL THE BAD PORT physically, with tape or a marker. This" \
        "     will otherwise be rediscovered by whoever picks the node up" \
        "     next, and it costs hours each time." \
        "" \
        "  3. Optionally, once: update the Pi USB controller firmware." \
        "     It occasionally fixes port-enable faults and is cheap to try." \
        "         sudo rpi-eeprom-update -a  &&  sudo reboot" \
        "" \
        "You do NOT need a powered hub or a bigger supply for this fault." \
        "The other ports on this board work, which rules out the supply."
fi

if [ "$PORTERR" -gt 0 ]; then
    bad "the USB port has failed to enable the device $PORTERR time(s)"
    say ""
    dmesg 2>/dev/null | grep -i "Cannot enable\|unable to enumerate\|attempt power cycle" | tail -4 | sed 's/^/    /'
    fix "This is an ELECTRICAL fault, not a software one. 'Cannot enable. Maybe the USB cable is bad' and 'attempt power cycle' are the USB host controller telling you it cannot keep the device powered and enumerated. The adapter may be working at this instant and will drop again." \
        "In order of likelihood, and the first one is usually it:" \
        "" \
        "  1. POWER. The AR9271 pulls 400 to 500 mA on its own, on top of" \
        "     the Pi and the aux module. A weak supply or a battery pack" \
        "     cannot hold that up. Use a 3 A class supply." \
        "" \
        "  2. A POWERED USB HUB between the Pi and the adapter. This is the" \
        "     definitive fix and worth doing for the field build, because it" \
        "     takes the adapter off the Pi's own power budget entirely." \
        "" \
        "  3. A different USB port, and no extension cable. If you are using" \
        "     an extension, remove it and test the adapter directly." \
        "" \
        "  4. A failing adapter. Swap in the other one, same port and supply." \
        "     If that one is stable, the first adapter is the fault." \
        "" \
        "Until this is fixed, treat ALL range and sync measurements from" \
        "this node as void: the mesh will disappear mid-test and the result" \
        "will look like a software problem."
elif [ "$DISC" -gt 1 ]; then
    bad "the adapter has disconnected $DISC times this boot"
    fix "The adapter keeps leaving the USB bus. It is up now, but it will not stay up, and anything measured through it is unreliable." \
        "Most likely power. Move to a 3 A supply, or put a powered USB hub" \
        "between the Pi and the adapter, then re-run this check." \
        "" \
        "See CHANGES item 40: this exact failure already cost the project an" \
        "evening once, because sync keeps logging SYNC_OK while it happens."
elif [ "$DISC" -eq 1 ]; then
    warn "one disconnect seen this boot, which is normal if you replugged it"
else
    ok "no disconnects this boot"
fi

# The driver tries a versioned firmware filename first and falls back.
# The failure line looks alarming and is not a problem, so say so before
# somebody spends an hour on it.
if dmesg 2>/dev/null | grep -q "htc_9271-1.4.0.fw failed"; then
    if dmesg 2>/dev/null | grep -q "Transferred FW: htc_9271.fw"; then
        ok "firmware loaded (ignore the 'htc_9271-1.4.0.fw failed' line, the"
        say "          driver tries a versioned name first and then falls back)"
    else
        fix "The ath9k_htc firmware did not load. The driver tried htc_9271-1.4.0.fw, fell back to htc_9271.fw, and that did not transfer either." \
            "    sudo apt install -y firmware-ath9k-htc" \
            "    sudo modprobe -r ath9k_htc && sudo modprobe ath9k_htc"
    fi
fi

# --- 1c. which naming scheme is this node using? ------------------------
step "How is wlan1 given its name?"
LINKFILE=/etc/systemd/network/11-dtn-wifi.link
if [ ! -f "$LINKFILE" ]; then
    bad "$LINKFILE does not exist"
    fix "Nothing is pinning the adapter to the name wlan1. It works right now only by luck of enumeration order, and a reboot or a replug can rename it." \
        "    cd ~/rescue-mesh/deploy && sudo ./setup_node.sh X    # a, b or s" \
        "    sudo reboot"
fi
MATCH=$(grep -E '^(Driver|MACAddress)=' "$LINKFILE" 2>/dev/null | head -1)
say "     $LINKFILE matches on: ${MATCH:-nothing}"
case "$MATCH" in
    Driver=*)
        ok "matched by DRIVER: any AR9271 in any port becomes wlan1"
        ACTUAL=$(basename "$(readlink -f /sys/class/net/wlan1/device/driver 2>/dev/null)" 2>/dev/null)
        if [ -n "$ACTUAL" ] && [ "$ACTUAL" != "${MATCH#Driver=}" ]; then
            bad "but the adapter actually uses driver '$ACTUAL'"
            fix "The rule matches ${MATCH#Driver=} and this adapter uses $ACTUAL, so the name is not coming from the rule. A different adapter, or a different port, may come up unnamed." \
                "Tell the team the driver is '$ACTUAL' so the match rule in" \
                "deploy/setup_node.sh can be widened."
        fi
        ;;
    MACAddress=*)
        warn "matched by MAC ADDRESS: this is the OLD scheme"
        say ""
        say "     It works while this exact adapter is fitted. It does NOT"
        say "     survive swapping adapters, and cheap AR9271 dongles do not"
        say "     all keep a stable MAC across power cycles, which is what"
        say "     made interface names swap after a reboot."
        say ""
        say "     Fix (safe to do while everything is working):"
        say "       cd ~/rescue-mesh && git pull"
        say "       cd deploy && sudo ./setup_node.sh X      # a, b or s"
        say "       sudo reboot"
        ;;
    *)
        warn "could not read a Match rule from $LINKFILE"
        ;;
esac

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
