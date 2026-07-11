#!/bin/bash
# dtn-net-up.sh: bring wlan1 (AR9271) into the always-on IBSS DTN cell
# (file 01 step 5, master plan D2). Installed to /usr/local/sbin/ by
# setup_node.sh; invoked by dtn-net.service after boot.
#
# Values are fixed FLEET-WIDE by design:
#   SSID  RESCUE_DTN
#   FREQ  2437 MHz (2.4 GHz channel 6; channel plan in master plan R2)
#   BSSID 02:12:34:56:78:9A (fixed cell id prevents IBSS split-cells;
#         locally administered address, not a vendor MAC)
# The per-node IP comes from /etc/rescue-mesh/dtn_ip (10.99.0.1/2/3).

set -e

IFACE=wlan1
SSID=RESCUE_DTN
FREQ=2437
BSSID=02:12:34:56:78:9A
IP=$(cat /etc/rescue-mesh/dtn_ip)

ip link set "$IFACE" down
iw dev "$IFACE" set type ibss
ip link set "$IFACE" up
iw dev "$IFACE" ibss join "$SSID" "$FREQ" fixed-freq "$BSSID"
ip addr flush dev "$IFACE"
ip addr add "$IP/24" brd 10.99.0.255 dev "$IFACE"

echo "dtn-net: $IFACE joined $SSID @${FREQ}MHz as $IP"
