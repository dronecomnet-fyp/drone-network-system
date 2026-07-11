import subprocess
import time
from sync_engine import sync_with_peer
import sys

# --- CONFIGURATION (Modify per Pi) ---
MY_SSID = "DRONE_A"
TARGET_PEERS = ["DRONE_B", "DRONE_C"]
AP_TIME = 90    # Seconds to stay as Hotspot for victims
SCAN_TIME = 40  # Seconds to look for other drones
# -------------------------------------

def run_cmd(cmd):
    """Executes a shell command and returns the result, logging errors."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[!] Command failed (code {result.returncode}): {cmd}")
        if result.stderr:
            print(f"    stderr: {result.stderr.strip()}")
    return result

def wait_for_route(timeout_sec=10):
    """Wait for wlan0 to have a valid default route and IP in 10.42.0.0/24.
    Returns True if ready, False if timeout."""
    start = time.time()
    while time.time() - start < timeout_sec:
        # Check if wlan0 has an IP
        ip_result = run_cmd("ip addr show wlan0 | grep 'inet 10.42'")
        route_result = run_cmd("ip route show default | grep wlan0")
        
        if ip_result.returncode == 0 and route_result.returncode == 0:
            print("[+] Network route is ready.")
            return True
        
        time.sleep(0.5)
    
    print(f"[-] Timeout waiting for network route on wlan0 after {timeout_sec}s")
    return False

def activate_ap():
    print(f"\n>>> STATE: ACCESS POINT ({MY_SSID})")
    disconnect_r = run_cmd("nmcli device disconnect wlan0")
    time.sleep(5)  # Give hardware time to release
    
    # Check if the profile already exists in NetworkManager
    check = run_cmd(f"nmcli con show {MY_SSID}")
    
    # If it does NOT exist, build it
    if check.returncode != 0:
        print("[*] Creating new OPEN hotspot profile...")
        add_r = run_cmd(f"nmcli con add type wifi ifname wlan0 con-name {MY_SSID} autoconnect no ssid {MY_SSID}")
        if add_r.returncode != 0:
            print("[-] Failed to create hotspot profile, skipping this cycle.")
            return
        mod_r = run_cmd(f"nmcli con modify {MY_SSID} 802-11-wireless.mode ap 802-11-wireless.band bg ipv4.method shared")
        if mod_r.returncode != 0:
            print("[-] Failed to configure hotspot, skipping this cycle.")
            return
    else:
        print("[*] Reusing existing hotspot profile...")
        
    # Turn it on
    up_r = run_cmd(f"nmcli con up {MY_SSID}")
    if up_r.returncode != 0:
        print(f"[-] Failed to bring up AP {MY_SSID}, will retry next cycle.")
        return
    print(f"[+] AP {MY_SSID} is now active.")

def activate_client():
    print("\n>>> STATE: SCANNING FOR PEERS")
    run_cmd("nmcli device disconnect wlan0")
    time.sleep(2)
    
    # Scan the airwaves for Wi-Fi networks
    scan_result = run_cmd("nmcli -t -f SSID dev wifi")
    found_peers = [ssid for ssid in TARGET_PEERS if ssid in scan_result.stdout]
    
    if not found_peers:
        print("[*] No peers nearby.")
        time.sleep(SCAN_TIME)
        return

    # If we found a peer, connect to it
    for peer in found_peers:
        print(f"[*] Found peer: {peer}. Attempting connection...")
        conn_r = run_cmd(f"nmcli dev wifi connect {peer}")
        if conn_r.returncode != 0:
            print(f"[-] Failed to connect to {peer}, trying next peer.")
            continue
        
        # Wait for DHCP and route to be ready before syncing
        if not wait_for_route(timeout_sec=10):
            print(f"[-] Peer {peer} did not provide a working route, disconnecting.")
            run_cmd(f"nmcli con down id {peer}")
            run_cmd(f"nmcli con delete id {peer}")
            continue
        
        # When connected to a 'shared' hotspot, the host is always 10.42.0.1
        print("[*] Connected and route is ready. Starting sync...")
        sync_with_peer("10.42.0.1")
        
        # Disconnect and clean up so we don't save broken profiles
        run_cmd(f"nmcli con down {peer}")
        run_cmd(f"nmcli con delete id {peer}")

def main():
    print("[*] Rescue Mesh Wi-Fi Switcher started.")
    try:
        while True:
            activate_ap()
            time.sleep(AP_TIME)
            activate_client()
    except KeyboardInterrupt:
        print("\n[*] Shutting down switcher...")
        # Graceful cleanup on exit
        run_cmd(f"nmcli con down {MY_SSID}")
    except Exception as e:
        print(f"[!] Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
