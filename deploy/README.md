# deploy/: blank card to working node

Everything a teammate needs to rebuild a node with no prior context
(file 01 acceptance). One image + one script serves all three nodes; only
`nodes/drone_X.conf` differs per node.

## One-time, per fleet (operator laptop)

1. `cd deploy && ./make_fleet_ca.sh`
   Creates `deploy/secrets/`: the fleet CA (node certs are issued from it
   during setup; the apps embed `fleet_ca.crt` for real pinning) and
   `fleet_secrets.env` (one master secret; per-purpose keys are derived on
   the nodes, file 09 F2). NEVER commit this directory; keep `fleet_ca.key`
   offline once all nodes are built.

## Per Pi

1. Flash Raspberry Pi OS Lite (64-bit, Bookworm) with Raspberry Pi Imager.
   Imager settings: hostname `drone-a` / `drone-b` / `drone-s`, enable SSH
   with key auth, username `drone`, do NOT preconfigure WiFi, locale and
   timezone Asia/Colombo.
2. First boot with Ethernet (or keyboard+monitor). SSH in as `drone`.
3. `git clone <repo-url> /home/drone/rescue-mesh`
4. Copy `deploy/secrets/` from the operator laptop into
   `/home/drone/rescue-mesh/deploy/secrets/` (scp or USB).
5. Plug in the AR9271 USB adapter and the aux module (A/B only).
6. `cd /home/drone/rescue-mesh/deploy && sudo ./setup_node.sh a` (or b/s).
7. Reboot when told to.
8. Work through `deploy/VERIFY.md`; log results in `docs/test_log.md`.

## What the script does (mapping to file 01)

| Step | Action |
|------|--------|
| 2 | Verifies NetworkManager active, dhcpcd inactive; checks ath9k; sets country LK |
| 3 | Pins wlan0=onboard, wlan1=AR9271 via systemd .link files (MACs auto-detected or from the conf) |
| 4 | USER_AP profile: 5 GHz, channel from conf, `ipv4.method shared`, 10.42.0.1/24; dnsmasq wildcard for the captive portal |
| 5 | wlan1 unmanaged by NM; dtn-net-up.sh + dtn-net.service join the fixed IBSS cell (RESCUE_DTN, ch 6, fixed BSSID) |
| 6 | apt base packages; venv with pinned backend/requirements.txt |
| 7 | /etc/rescue-mesh/node.env from conf + fleet secrets (chmod 600); node TLS cert issued from the fleet CA (SAN 10.42.0.1 + DTN IP) |
| 8 | systemd units (api 8443, portal 80, sync, auxbridge, firewall, runtime dir); narrow sudoers for GPS clock set; per-role nftables; Bluetooth disabled (dtoverlay=disable-bt); retired Phase 1 units removed |

## Service map

| Service | What | Port |
|---------|------|------|
| rescue-portal | victim plane: form, /message, /checkin, captive probes | 80 (HTTP) |
| rescue-mesh-api | authenticated plane: rescue/HQ/sync API | 8443 (HTTPS, fleet-CA cert) |
| rescue-mesh-sync | UDP presence beacons + pull sync | 48555/udp |
| rescue-mesh-auxbridge | serial JSON to the ESP32-C3 aux module | ttyACM0 |
| dtn-net | one-shot IBSS bring-up for wlan1 | - |
| rescue-mesh-firewall | per-role nftables (MAVLink lockdown / relay path) | - |
| (drone_s later, file 08) rescue-mesh-mavgw | MAVLink gateway, lands with package 08 after Stage 0 | 14550/udp |

## Fallback (do not build preemptively)

If IBSS proves unstable on the shipped kernel during file 07 T2/T3, the
documented fallback is wlan1 AP<->station cycling (a port of the archived
switcher.py bound to wlan1, users untouched on wlan0). See file 01 step 5
and file 07 backout criteria; nothing in this folder implements it yet on
purpose.
