# Archived Phase 1 components

Retired 2026-07-11 during the Phase 2 rebuild (master plan D1, D2, D3).
Kept for the inspectable history required by project rule 5; do not install
or run these on Phase 2 nodes.

- `switcher.py`: Phase 1 single-radio DTN. It cycled wlan0 between AP mode
  (90 s) and client scan/sync mode (40 s), which disconnected every user
  during every sync cycle. Superseded by the dual-radio design: wlan0 stays
  a 5 GHz user AP full time and wlan1 (AR9271) holds a 2.4 GHz IBSS cell
  full time, with sync_daemon.py doing presence and pull sync (files 01/02,
  master plan D2). The systemd unit rescue-mesh-switcher.service must NOT
  be installed on Phase 2 nodes.

- `ble_discovery.py`: Phase 1 BLE discovery attempt. It ran
  `bluetoothctl discoverable on`, which enables CLASSIC Bluetooth inquiry
  visibility, not BLE advertising, so phones scanning for BLE
  advertisements never saw the node: this is why it failed in testing.
  Superseded by real BLE advertising on the ESP32-C3 aux module (file 03,
  master plan D3). Pi Bluetooth is disabled entirely on Phase 2 nodes
  (dtoverlay=disable-bt) to remove the WiFi/BT coexistence variable.
