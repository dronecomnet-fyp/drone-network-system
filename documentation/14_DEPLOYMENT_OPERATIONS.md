# 14 Deployment and Operations

This chapter is the practical one: how a node is built from a blank SD card, how
secrets and the fleet certificate authority work, what runs as a service, and
where the step-by-step field runbooks are. The authoritative procedures are the
browsable runbooks and `deploy/VERIFY.md`; this chapter gives you the map.

## The principle: one script, config per node

A fresh Pi becomes a node by running one script with a node letter. Everything a
node needs is in files, nothing is hand-done. This is the reproducibility the
clean-rebuild decision (chapter 03) was made for.

- `deploy/setup_node.sh <a|b|s>` reads `deploy/nodes/drone_<x>.conf` and does
  everything: pins the interface MAC addresses, creates the `RESCUE_x` access
  point, installs the IBSS bring-up, the captive portal, the Python venv and
  pinned requirements, generates `/etc/rescue-mesh/node.env` with fresh secrets,
  installs the sudoers rule and the systemd units, disables onboard Bluetooth,
  and applies the firewall.
- `deploy/nodes/drone_a.conf` / `drone_b.conf` / `drone_s.conf`: the only
  per-node differences (node id, SSID, DTN IP, and for DRONE_S the flight
  controller serial and `DRONE_CONTROL=true`).

## Secrets and the fleet CA (the most important operational rule)

- `deploy/make_fleet_ca.sh` generates the one fleet certificate authority into
  `deploy/secrets/` (git-ignored, carried by the operator on a USB stick). **Run
  it exactly once, on DRONE_A.**
- **DRONE_B and DRONE_S must copy DRONE_A's `deploy/secrets/` and must NEVER run
  `make_fleet_ca.sh`.** A different key set (or a different master secret) means
  the nodes silently reject each other's records and beacons and never sync. This
  is the single most common and most confusing setup mistake; it is called out
  in every node runbook.
- No secret is ever committed to git (`.gitignore` covers `deploy/secrets/`,
  `*.pem`, `*.key`, databases, and the audit log). Secrets are generated at
  deploy time. Anything that ever touched the old Phase 1 repositories is treated
  as burned and rotated. Rotation means regenerating the fleet secrets and
  re-issuing node certificates from DRONE_A, then redeploying to every node; a
  dedicated rotation runbook is future work.

## The systemd services

`deploy/systemd/` installs these units (chapter 06 describes what they do):

| Unit | What it runs |
|------|--------------|
| `rescue-portal.service` | the victim plane (`http_app.py`, port 80) |
| `rescue-mesh-api.service` | the authenticated plane (`api.py`, HTTPS 8443) |
| `rescue-mesh-sync.service` | the DTN sync daemon (beacons + pull) |
| `rescue-mesh-auxbridge.service` | the serial link to the ESP32 aux module |
| `rescue-mesh-mavgw.service` | the MAVLink gateway (DRONE_S only, `DRONE_CONTROL=true`) |
| `rescue-mesh-firewall.service` | applies the nftables rules |
| `dtn-net.service` | oneshot: brings up the IBSS mesh interface at boot |
| `rescue-mesh-runtime.service` | prepares the `/run/rescue-mesh` state dir |

The Phase 1 `switcher.py` and `ble_discovery.py` are retired to
`backend/archived/` and their units are not installed.

A node config detail worth knowing: `node.env` is owned by the service user and
mode 600. A Phase 2 bug where the setup script left it root-owned crash-looped
the services with a PermissionError; the fix chowns it to the service user, and
`config.py` was also made resilient to an unreadable env file since systemd
populates the environment anyway.

## The clock and the narrow sudoers rule

A node may boot before it has a GPS fix, so its clock starts on relative time
(this is why records carry `time_source` and the apps show a "~" hint). When the
aux module (or the MAVLink gateway on DRONE_S) provides GPS time, the aux bridge
sets the system clock. It is allowed to do exactly one privileged thing, through
a narrow sudoers rule (`deploy/files/rescue-mesh-sudoers`): run `date -u -s`.
Nothing else. Clock changes are audit-logged with the old and new time.

## The firewall

`deploy/files/nftables-drone-s.nft` and `nftables-volunteer.nft`, applied per
node role:

- On a volunteer node: forward the relayed MAVLink to DRONE_S's gateway and
  masquerade the user subnet out the mesh interface (the relay path, chapter 11).
- On DRONE_S: restrict the MAVLink UDP port 14550 to the local user subnet and
  the volunteer mesh addresses (file 09 plane 4 layer 1).

## The runbooks

The step-by-step field procedures are browsable HTML runbooks with verification
gates (the same design system throughout). Start here for any hands-on task:

| Runbook | Purpose |
|---------|---------|
| `deploy/windows_pi_bringup.html` | build a single node from a blank card |
| `deploy/windows_mesh_bringup.html` | bring up the two-node DTN mesh |
| `deploy/windows_drone_s_bringup.html` | bring up DRONE_S as a full node + gateway |
| `deploy/node_update_locations.html` | roll the rescuer-location update to each node |
| `deploy/mission_layer_check.html` | verify the whole mission layer end to end |
| `firmware/aux1/windows_bringup.html` | flash and test the aux module |
| `gcc_app/windows_gcc_bringup.html` | build and run the GCC |
| `gcc_app/windows_drone_control.html` | GCC drone control bring-up |
| `docs/phone_apps_bringup.html` | build and install the phone apps |

And `deploy/VERIFY.md` is the acceptance checklist for a rebuilt node,
`deploy/README.md` the blank-card walkthrough.

## The order to bring up a fleet

1. Build DRONE_A (`setup_node.sh a`), run `make_fleet_ca.sh` on it once.
2. Build DRONE_B (`setup_node.sh b`), copying A's `deploy/secrets/` first.
3. Bring up the mesh and confirm A and B sync (`windows_mesh_bringup.html`).
4. Build DRONE_S (`setup_node.sh s`), copying A's secrets, wire the flight
   controller, confirm it joins the mesh and the gateway works
   (`windows_drone_s_bringup.html`).
5. Flash each aux module (`firmware/aux1/windows_bringup.html`).
6. Build and configure the apps; load the fleet CA into each.
7. If updating an existing fleet for rescuer locations, follow
   `node_update_locations.html`.
8. Verify the operation layer (`mission_layer_check.html`).
