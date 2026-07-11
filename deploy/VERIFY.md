# deploy/VERIFY.md: per-node acceptance checklist (file 01 step 9)

Run after `sudo ./setup_node.sh <a|b|s>` and the required reboot. Log each
run in docs/test_log.md. Acceptance for file 01: all checks pass on all
three nodes AND a teammate can rebuild a node from a blank card using only
deploy/README.md.

## Step 0. Environment notes to record once

- [ ] Python version on the Pi (`python3 --version`). The pinned
      requirements were resolved on Python 3.14 (dev Mac); confirm
      `pip install -r backend/requirements.txt` succeeds on the Pi's
      Python 3.11 and record any version changes here and in
      docs/CHANGES.md.
- [ ] Exact ath9k firmware package if one had to be installed
      (expected: `firmware-ath9k-htc`; confidence Moderate until
      confirmed on the Bookworm image).

## Checks (file 01 step 9, extended by file 09)

1. [ ] Interface pinning survives reboot: `ip link` shows wlan0 with the
       onboard MAC and wlan1 with the AR9271 MAC (compare against the
       .conf values).

2. [ ] Phone joins RESCUE_X, the captive popup appears (test one Android
       AND one iPhone), the popup lands directly on the message form
       (plain HTTP, NO certificate warning: file 09 F3), and a message
       submits successfully.

3. [ ] `iw dev wlan1 info` shows type IBSS, ssid RESCUE_DTN, and the
       fixed BSSID 02:12:34:56:78:9A.

4. [ ] With two nodes powered: `ping 10.99.0.2` (from .1) succeeds, AND a
       phone streaming pings to 10.42.0.1 over the user AP stays
       connected the whole time (the Phase 1 disconnection problem is
       gone; full test is file 07 T2).

5. [ ] All services `active (running)` after a cold boot with no
       keyboard/monitor:
       `systemctl status rescue-mesh-api rescue-portal dtn-net \
        rescue-mesh-sync rescue-mesh-auxbridge rescue-mesh-firewall`
       (on DRONE_S, rescue-mesh-auxbridge exits 0 by design: check it
       shows inactive (dead) with status=0/SUCCESS, and /health reports
       aux "absent").

6. [ ] API checks (Phase 1 rpi_PI_SETUP.md section 12 equivalents, v2
       endpoints):
       - `curl -sk https://10.42.0.1:8443/health | python3 -m json.tool`
         shows node_id, gps, battery, clock_source, peers.
       - `curl -s http://10.42.0.1/ | head -5` returns the victim form.
       - Victim POST works over HTTP:
         `curl -s -X POST http://10.42.0.1/message -H 'Content-Type: application/json' -d '{"content":"verify test"}'`
       - With the HQ break-glass key: `curl -sk -H "X-API-Key: $HQ_API_KEY" https://10.42.0.1:8443/messages` lists it.

7. [ ] TLS chain (file 09 plane 2): from a laptop with the fleet CA cert,
       `curl --cacert fleet_ca.crt https://10.42.0.1:8443/health`
       verifies WITHOUT -k. With a wrong CA it must fail.

8. [ ] Relay path plumbing (volunteer nodes, file 08): from a laptop on
       the user AP, `ping 10.99.0.3` reaches DRONE_S when it is in IBSS
       range; `nft list table inet rescue_mesh` shows the forward rules.
       On DRONE_S: `nft list table inet rescue_mesh` shows the 14550
       source restriction.

9. [ ] Clock behavior (nodes with aux module): after GPS fix,
       journalctl -u rescue-mesh-auxbridge shows a CLOCK_SYNC entry and
       /health clock_source flips to "gps". Pull the aux USB cable:
       /health flips aux to "absent" without service restart; replug:
       recovery (file 02 acceptance 3).

10. [ ] Beacon replay defence spot check (file 09 T9.3): capture one
        beacon (`tcpdump -i wlan1 -c 1 -w /tmp/b.pcap udp port 48555`),
        replay it (`tcppreplay` or a 5-line python resend), then check
        the peer's audit.log contains BEACON_REPLAY_REJECT.
