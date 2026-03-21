import subprocess
import time
import os

# Configuration from Environment
SSID = os.getenv("HOTSPOT_SSID", "SmartNetwork_AP")
PASSWORD = os.getenv("HOTSPOT_PASS", "galaksija2026")
INTERVAL = int(os.getenv("CHECK_INTERVAL", 120)) 

def run(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)

def setup_hotspot():
    """Ensure the Hotspot profile exists in NetworkManager."""
    exists = run("nmcli con show SmartHotspot")
    if exists.returncode != 0:
        print(f"Creating SmartHotspot profile: {SSID}")
        run(f"nmcli con add type wifi ifname wlan0 mode ap con-name SmartHotspot ssid {SSID}")
        run(f"nmcli con modify SmartHotspot wifi-sec.key-mgmt wpa-psk wifi-sec.psk {PASSWORD}")
        run(f"nmcli con modify SmartHotspot ipv4.method shared")
        run("nmcli con modify SmartHotspot connection.autoconnect no")

def is_connected_to_internet():
    """Checks if we are a client on a real network."""
    res = run("nmcli -t -f TYPE,STATE dev")
    # Check if wifi is 'connected' and it's NOT our own hotspot
    active_con = run("nmcli -t -f NAME,TYPE con show --active")
    return "wifi:connected" in res.stdout and "SmartHotspot" not in active_con.stdout

def main():
    print("--- Smart Network Manager Initialized ---")
    setup_hotspot()
    
    while True:
        if is_connected_to_internet():
            print("Status: Connected to saved network.")
        else:
            print("Status: Disconnected. Rescanning for saved networks...")
            run("nmcli device wifi rescan")
            time.sleep(15) # Wait for autoconnect attempt
            
            if not is_connected_to_internet():
                print("Action: No networks found. Activating Hotspot.")
                run("nmcli con up SmartHotspot")
        
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()