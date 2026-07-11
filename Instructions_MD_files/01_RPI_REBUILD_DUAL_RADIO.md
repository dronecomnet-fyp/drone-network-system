# 01 PI REBUILD AND DUAL-RADIO BRING-UP

Goal: three identical, scripted Raspberry Pi nodes where wlan0 (onboard) runs
the 5 GHz user AP continuously and wlan1 (AR9271 USB) runs the 2.4 GHz DTN
backbone continuously. The Phase 1 single-radio switcher is retired.

Deliverable for Claude Code: a `deploy/` folder in the repo containing
`setup_node.sh`, config templates, systemd unit files, and a `VERIFY.md`
checklist, such that a fresh Pi becomes a working node by running one script
with a node letter argument. Everything below must end up encoded in those
files, not just done by hand once.

## Step 0. Preserve the old state (once per Pi, manual)

1. Power the old node, SSH in, copy off: `backend/.env`, `backend/keys/`,
   `drone_mesh.db`, `audit.log` (keep for the report's Phase 1 evidence).
2. Optionally image the whole card from a laptop:
   `sudo dd if=/dev/sdX of=drone_A_phase1.img bs=4M status=progress`.
3. Keep ONE original card untouched as rollback until file 07 passes.

## Step 1. Flash and first boot (per Pi)

1. Raspberry Pi Imager -> Raspberry Pi OS Lite (64-bit, Bookworm).
2. In Imager's settings: hostname `drone-a` (b/c per node), enable SSH with
   key auth, username `drone`, do NOT preconfigure WiFi (we script it),
   set locale/timezone Asia/Colombo.
3. Boot with Ethernet or keyboard for the first session.
4. Set WiFi regulatory domain: `sudo raspi-config nonint do_wifi_country LK`.
   Verify with `iw reg get`. Without this, 5 GHz AP channels may be blocked.

## Step 2. Verify the network stack assumptions before scripting

Bookworm is expected to use NetworkManager by default. VERIFY, do not assume:
```
systemctl is-active NetworkManager    # expect: active
systemctl is-active dhcpcd            # expect: inactive
```
If NetworkManager is not active, install and enable it exactly as the old
rpi_setup_plan_from_claude.md Step 0 described. The setup script must perform
this check and abort with a clear message if the stack is wrong.

Verify the AR9271 driver and firmware load:
```
lsusb                     # expect an Atheros AR9271 entry
dmesg | grep -i ath9k     # expect ath9k_htc firmware loaded, no errors
iw list                   # confirm one PHY supports IBSS ("ad-hoc"/"IBSS")
```
If firmware is missing, `sudo apt install firmware-ath9k-htc` (package name
may differ on Raspberry Pi OS; resolve at implementation time and record the
exact package in VERIFY.md).

## Step 3. Pin interface names (critical, prevents wlan0/wlan1 swapping)

The onboard radio and the USB radio can enumerate in either order. Pin them
by MAC address with systemd .link files so wlan0 is ALWAYS onboard and wlan1
is ALWAYS the AR9271:

`/etc/systemd/network/10-onboard-wifi.link`
```
[Match]
MACAddress=<onboard MAC>
[Link]
Name=wlan0
```
`/etc/systemd/network/11-dtn-wifi.link`
```
[Match]
MACAddress=<AR9271 MAC>
[Link]
Name=wlan1
```
The setup script should read both MACs interactively (or from a per-node
config file `deploy/nodes/drone_a.conf`) and write these files, then require
a reboot. Verify after reboot with `ip link`.

## Step 4. wlan0: 5 GHz user AP (NetworkManager, shared mode)

One profile per node, created by the script from the node config:
```
nmcli con add type wifi ifname wlan0 con-name USER_AP autoconnect yes \
  ssid RESCUE_A
nmcli con modify USER_AP 802-11-wireless.mode ap 802-11-wireless.band a \
  802-11-wireless.channel 36 ipv4.method shared ipv4.addresses 10.42.0.1/24 \
  802-11-wireless.powersave 2
nmcli con up USER_AP
```
Notes:
- SSID comes from config (RESCUE_A/B/C), not hardcoded in code. This closes
  progress report item 4.1.
- Open network (no password) is intentional for victims; document as a known
  design property, compensated by role keys and HTTPS at the app layer.
- `ipv4.method shared` gives DHCP + the fixed gateway 10.42.0.1 that the
  captive portal, apps, and cert CN already assume.
- Channel 36 is the initial choice; confirm against TRCSL outdoor 5 GHz
  guidance (master plan R3) and make the channel a config value.

Captive portal DNS + port 80:
- Add `/etc/NetworkManager/dnsmasq-shared.d/portal.conf` containing
  `address=/#/10.42.0.1` so every DNS name resolves to the node while a
  client is on the AP (restart NetworkManager after adding).
- Run http_app.py directly on port 80 via its systemd unit using
  `AmbientCapabilities=CAP_NET_BIND_SERVICE` (no root, no iptables DNAT).
  Set env `HTTP_PORT=80`. HTTPS app stays on 8443.

## Step 5. wlan1: 2.4 GHz IBSS DTN backbone (NetworkManager NOT used here)

Rationale in master plan D2. Keep wlan1 out of NetworkManager and configure
it deterministically with iw + a oneshot systemd service.

1. Tell NetworkManager to ignore wlan1:
   `/etc/NetworkManager/conf.d/unmanaged-dtn.conf`
   ```
   [keyfile]
   unmanaged-devices=interface-name:wlan1
   ```
2. `/usr/local/sbin/dtn-net-up.sh` (installed by the script):
   ```
   #!/bin/bash
   set -e
   IFACE=wlan1
   SSID=RESCUE_DTN
   FREQ=2437                 # channel 6, keep fixed fleet-wide
   BSSID=02:12:34:56:78:9A   # fixed cell id, prevents IBSS split-cells
   IP=$(cat /etc/rescue-mesh/dtn_ip)   # 10.99.0.1 / .2 / .3 per node
   ip link set $IFACE down
   iw dev $IFACE set type ibss
   ip link set $IFACE up
   iw dev $IFACE ibss join $SSID $FREQ fixed-freq $BSSID
   ip addr flush dev $IFACE
   ip addr add $IP/24 brd 10.99.0.255 dev $IFACE
   ```
3. `dtn-net.service` (oneshot, After=network.target, RemainAfterExit=yes,
   ExecStart the script above, Restart=on-failure via a small retry wrapper
   or `ExecStartPre=/bin/sleep 5` to let the USB adapter settle).
4. Open IBSS (no encryption): app-layer protection remains the HMAC message
   signatures plus the existing optional TLS/mTLS from
   rpi_SECURITY_DEPLOYMENT.md. Record as a documented tradeoff; IBSS-RSN is
   the upgrade path if the supervisor requires link encryption.

FALLBACK (only if IBSS proves unstable on the shipped kernel during file 07
testing): revert wlan1 to the design v3 AP<->station cycling, implemented as
a port of the old switcher.py but bound to wlan1 with users untouched on
wlan0. Do not build the fallback preemptively.

## Step 6. Base software install (scripted)

```
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git python3 python3-venv python3-pip sqlite3 openssl iw
```
Clone repo to /home/drone/rescue-mesh, create venv, install:
fastapi "uvicorn[standard]" pydantic requests cryptography python-dotenv
pyserial. Pin exact versions in `backend/requirements.txt` (create it; the
old docs installed unpinned, which is not reproducible).

## Step 7. Per-node configuration

Replace scattered constants (progress report item 4.3) with
`/etc/rescue-mesh/node.env`, generated by the script from
`deploy/nodes/drone_X.conf`:
```
NODE_ID=DRONE_A
USER_AP_SSID=RESCUE_A
DTN_IP=10.99.0.1
DTN_PEERS=10.99.0.2,10.99.0.3
API_PORT=8443
HTTP_PORT=80
... existing secrets (RESCUE_API_KEY, HQ_API_KEY, INTER_NODE_SECRET,
    NODE_SHARED_SECRET) generated fresh per rpi_SECRETS_ROTATION.md ...
AUX_SERIAL=/dev/ttyACM0
```
chmod 600. Secrets identical fleet-wide, per the existing rotation runbook.

Fleet note: three Pis are built from this ONE image and script. drone_a and
drone_b are the volunteer-drone comm modules; drone_s is the system drone
node (file 08). drone_s.conf differs only by: NODE_ID=DRONE_S,
USER_AP_SSID=RESCUE_S, DTN_IP=10.99.0.3, DRONE_CONTROL=true,
FC_SERIAL=<from file 04 Stage 0>, and AUX_SERIAL left empty (no third aux
module exists; aux_bridge then stays disabled and /health reports aux
absent).

## Step 8. systemd services (installed by script)

- rescue-mesh-api.service: uvicorn api:app on 8443 with TLS (reuse cert
  generation from rpi_SECURITY_DEPLOYMENT.md, CN=10.42.0.1).
- rescue-portal.service: uvicorn http_app:app on 80 with
  AmbientCapabilities=CAP_NET_BIND_SERVICE, User=drone.
- dtn-net.service: Step 5.
- rescue-mesh-sync.service: NEW always-on sync daemon from file 02.
- rescue-mesh-auxbridge.service: NEW serial daemon from file 02.
- RETIRED (rule 9 disclosure): rescue-mesh-switcher.service and
  rescue-mesh-ble.service must NOT be installed. switcher.py is superseded by
  the dual-radio design; ble_discovery.py is superseded by ESP32-C3
  advertising (design v3). Move both files to `backend/archived/` with a
  README line explaining when and why, so the history is inspectable.
- Disable Pi Bluetooth entirely to remove the coexistence variable:
  add `dtoverlay=disable-bt` to /boot/firmware/config.txt (verify exact path
  on Bookworm) and disable the hciuart service.

## Step 9. Verification checklist (goes into deploy/VERIFY.md)

Per node:
1. `ip link` shows wlan0=onboard, wlan1=AR9271 after reboot.
2. Phone connects to RESCUE_X, captive popup appears (Android and iPhone),
   portal link opens the HTTPS form, message submits.
3. `iw dev wlan1 info` shows type IBSS, ssid RESCUE_DTN, the fixed BSSID.
4. With two nodes powered: `ping 10.99.0.2` from .1 succeeds; user devices on
   wlan0 stay connected the whole time (the Phase 1 problem is gone).
5. All services `active (running)` after a cold boot with no keyboard.
6. Repeat the Phase 1 API curl checks from rpi_PI_SETUP.md section 12.

Acceptance: all six checks pass on all three nodes, and a fourth teammate can
rebuild a node from a blank card using only deploy/README.md.
