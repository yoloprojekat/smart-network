# 🌐 Smart Network (Failover Hotspot)

**Smart Network** is an ultra-lightweight, intelligent network module engineered for the **Smart Vehicle** platform (optimized for **DietPi OS** and **Debian / Raspberry Pi OS**). This project was developed as part of the solution for the national competition **Galaksija Kup 2026**.

The primary objective of this solution is to guarantee 100% network accessibility for the Raspberry Pi 5: whenever the vehicle is not connected to a known Wi-Fi network, a local **WPA2 Access Point (Hotspot)** is automatically and instantly created with **SSH access** enabled. As soon as a known network becomes available in the area (and the Hotspot is not in active use), the system seamlessly returns to client station mode.

---

## ⚡ Why We Removed Docker, Python, and NetworkManager

Earlier iterations of the project relied on a Docker container, a Python script, and NetworkManager. Real-world testing on the Raspberry Pi 5 revealed critical issues:

* ⏱️ **Eliminated Boot Delay (~1 Minute Saved):** Initializing the Docker daemon and launching containers on Raspberry Pi OS / DietPi prolonged system boot by **more than 1 minute**.
* 🪶 **Minimal Resource Footprint:** The Docker container and Python runtime consumed over 150 MB of RAM and generated continuous disk I/O. Switching to a pure **Bash script** directly managing **`wpasupplicant`** reduced memory usage to just **~2 MB**.
* 🚀 **Non-Blocking, Instant Startup (`systemd`):** The service is configured as `Type=simple` under `systemd`. It runs asynchronously in the background upon boot, never blocks system startup targets, and activates the Hotspot in under **5 seconds** if no known networks are present.

---

## 🚀 Key Features & Rock-Solid Stability

* **Fast Failover (~5 Seconds):** On boot, the system performs a quick 5-second check. If the vehicle is not connected to a saved network, the Hotspot activates immediately.
* **Active Session Protection (Never Drops):** The Hotspot is **never interrupted** while a client is actively connected (e.g., during an active SSH session or web connection). Network rescans only take place when the Hotspot is completely idle.
* **Guaranteed SSH Access:**
  * Assigns a static IP address (`192.168.4.1/24`) to the wireless interface.
  * Spawns a dedicated, conflict-free DHCP server (`dnsmasq` with `--port=0` and `--bind-dynamic`) to lease IP addresses to connecting devices.
  * Automatically verifies, unmasks, and starts the SSH daemon (**Dropbear** on DietPi or **OpenSSH**).
* **DietPi OS Compatibility:** Tailored for DietPi's `wpasupplicant` package, `ifupdown`, and Dropbear SSH, automatically disabling `AUTO_SETUP_BOOT_WAIT_FOR_NETWORK` multi-minute boot freezes.
* **WPA2 CCMP/AES Standard:** Explicitly configured with `proto RSN`, `pairwise CCMP`, and `group CCMP` to ensure modern smartphones (iOS, Android) and laptops connect reliably without handshake rejections.
* **Self-Healing Reconnection:** While the Hotspot is idle (no clients connected), the system checks in the background for known Wi-Fi networks and automatically reconnects once in range.

---

## 🛠️ How It Works

```
               ┌────────────────────────┐
               │      System Boot       │
               │ (non-blocking systemd) │
               └───────────┬────────────┘
                           ▼
               ┌────────────────────────┐
               │ Check Wi-Fi Connection │◄─────────────────────────┐
               │   (up to 5 seconds)    │                          │
               └───────────┬────────────┘                          │
              Connected?   │ Disconnected                          │
          ┌────────────────┴──────────────┐                        │
          ▼                               ▼                        │
   [Client Mode]               [Instant Hotspot Boot]              │
Connected to saved Wi-Fi         SSID: Pametno-Vozilo_AP           │
  (Vehicle on LAN/Web)           IP: 192.168.4.1 (SSH active)      │
          │                               │                        │
          │                               ▼                        │
          │                     ┌────────────────────┐             │
          │                     │ Client Connected?  │             │
          │                     │ (SSH session / mob)│             │
          │                     └─────────┬──────────┘             │
          │                       Yes │   │ No (idle)              │
          │           Maintain stable │   ▼                        │
          │              Hotspot link │ Scan for saved networks    │
          │                           │   │                        │
          │                           │   │ Found?                 │
          │                           │   ├── Yes ─► [Stop AP &    │
          │                           │   │          Connect WiFi] │
          │                           │   └── No ──► [Stay in AP]  │
          └───────────────────┬───────┴────────────────────────────┘
                              │
                              ▼
                  Wait CHECK_INTERVAL (120s)
                              │
                              └────────────────────────────────────┘
```

---

## 📦 Installation

Clone the repository and run the installation script with root privileges:

```bash
git clone https://github.com/yoloprojekat/smart-network.git
cd smart-network
sudo bash install.sh
```

The installer will automatically:
1. Optimize DietPi boot parameters by setting `AUTO_SETUP_BOOT_WAIT_FOR_NETWORK=0` and disabling blocking wait services.
2. Install required dependencies (`wpasupplicant`, `dnsmasq`, `wireless-tools`, `iw`, `rfkill`).
3. Ensure the `ctrl_interface` socket configuration is present in `/etc/wpa_supplicant/wpa_supplicant.conf`.
4. Ensure the SSH service (`dropbear` or `ssh`) is enabled, unmasked, and running.
5. Install the daemon script to `/opt/smart-network/smart-network.sh`.
6. Create the configuration file at `/etc/default/smart-network`.
7. Install `smart-network.service` to `/etc/systemd/system/`.
8. Reload systemd and immediately enable & start the service (`systemctl enable --now smart-network.service`).

---

## 🔑 Connecting & SSH Access

1. When the vehicle is not in range of a known Wi-Fi network, look for the following Wi-Fi access point:
   * **SSID:** `Pametno-Vozilo_AP`
   * **Password:** `galaksija2026`
2. Your device (laptop, smartphone, tablet) will automatically receive an IP address in the `192.168.4.x` range.
3. Connect via SSH:
   ```bash
   ssh root@192.168.4.1
   # or:
   ssh dietpi@192.168.4.1
   ```
   *(Default password for `root` and `dietpi` on DietPi OS is `pi`)*

---

## ⚙️ Configuration

Settings can be customized in `/etc/default/smart-network` without modifying the core script:

```bash
sudo nano /etc/default/smart-network
```

Example configuration:
```bash
# Hotspot SSID broadcasted by the vehicle
HOTSPOT_SSID="Pametno-Vozilo_AP"

# Hotspot WPA2 Password (minimum 8 characters)
HOTSPOT_PASS="galaksija2026"

# Interval to check for saved networks when idle (in seconds)
CHECK_INTERVAL=120

# Wireless interface (default: wlan0)
WLAN_INTERFACE="wlan0"

# Static IP of the vehicle in Hotspot mode
HOTSPOT_IP="192.168.4.1"
HOTSPOT_SUBNET="24"

# Wireless Regulatory Domain
WIFI_COUNTRY="RS"
```

After modifying the configuration, apply changes by restarting the service:
```bash
sudo systemctl restart smart-network
```

---

## 📊 Monitoring & Status

* **Check service status:**
  ```bash
  sudo systemctl status smart-network
  ```
* **Follow live logs in real time:**
  ```bash
  sudo journalctl -u smart-network -f
  ```
* **View connected clients (stations):**
  ```bash
  sudo iw dev wlan0 station dump
  ```

---

## 🗑️ Uninstallation

To cleanly remove the service and all installed files:

```bash
sudo bash install.sh --uninstall
```

---

<div align="center">

Author: **Danilo Stoletović**  
**Technical School „Nikola Tesla“ Niš • 2026**

</div>
