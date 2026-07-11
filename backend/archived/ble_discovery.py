import subprocess
import time
import os

# --- CONFIGURATION (Modify per Pi) ---
NODE_LETTER = "A" # Change to B or C for other boards
MY_SSID = f"DRONE_{NODE_LETTER}"
BROADCAST_NAME = f"EMERGENCY: {MY_SSID}" 
# -------------------------------------

def run_cmd(cmd):
    """Executes a shell command and returns the result."""
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)

def setup_ble():
    print(f"[*] Initializing BLE Discovery for {MY_SSID}...")
    
    # 1. Power on the Bluetooth controller
    run_cmd("sudo bluetoothctl power on")
    
    # 2. Set the 'Alias' (the name phones will see)
    run_cmd(f"sudo bluetoothctl system-alias '{BROADCAST_NAME}'")
    
    # 3. Set discoverable mode so it shows up in scans
    run_cmd("sudo bluetoothctl discoverable on")
    
    # 4. Set the discoverable timeout to 0 (never timeout)
    run_cmd("sudo bluetoothctl discoverable-timeout 0")
    
    # 5. Disable pairable mode (we only want them to see us, not connect)
    run_cmd("sudo bluetoothctl pairable off")
    
    print(f"[+] BLE is now broadcasting as: {BROADCAST_NAME}")

def main():
    if os.geteuid() != 0:
        print("[!] This script must be run with sudo.")
        return

    setup_ble()
    
    try:
        while True:
            # Re-verify discoverable status every 60 seconds
            run_cmd("sudo bluetoothctl discoverable on")
            time.sleep(60)
    except KeyboardInterrupt:
        print("\n[*] Shutting down BLE broadcast...")
        run_cmd("sudo bluetoothctl discoverable off")

if __name__ == "__main__":
    main()