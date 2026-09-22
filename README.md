# 🌐 Smart Network (Failover Hotspot)

**Smart Network** is an ultra-lightweight, intelligent failover network module engineered for **Raspberry Pi OS Lite** (Raspberry Pi 5 / 4 / 3 / Zero) powered natively by **NetworkManager (`nmcli`)** and **`systemd`**. This project was developed as part of the autonomous platform for the national competition **Galaksija Kup 2026**.

The primary objective of this solution is to guarantee 100% network accessibility for the Raspberry Pi: whenever the vehicle is not connected to a known Wi-Fi network, a local **WPA2 Access Point (Hotspot)** is automatically and instantly created with **SSH access** enabled. As soon as a known network becomes available in the area (and the Hotspot is not in active use), the system seamlessly returns to client station mode.

---

## ⚡ Why Native NetworkManager & systemd?

Raspberry Pi OS (Bookworm and newer) uses **NetworkManager** as its official, standard networking stack. Smart Network leverages this native infrastructure directly:

* ⏱️ **Zero Boot Delay (~5-Second Startup):** Traditional setups often freeze for 1–2 minutes at boot if offline due to systemd wait-online targets. Smart Network runs asynchronously as a `Type=simple` systemd service and masks blocking wait services, bringing the Hotspot online in seconds.
* 🪶 **Ultra-Minimal Resource Footprint:** By replacing heavy containers and Python runtimes with a streamlined Bash daemon interacting directly with `nmcli`, memory usage is kept under **~3 MB** with negligible CPU consumption.
* 🛡️ **Native DHCP & AP Management:** Employs NetworkManager's native `ipv4.method shared` mode (powered by `dnsmasq-base`), eliminating manual socket and PID management while providing rock-solid DHCP leasing to connecting clients.
* 🔌 **Seamless OS Integration:** Works out of the box with standard Raspberry Pi OS tools like `nmtui`, `nmcli`, and `raspi-config`.

---

## 🚀 Key Features & Rock-Solid Stability

* **Fast Failover (~5–8 Seconds):** On system boot, the daemon performs a quick probe. If the device does not associate with a saved Wi-Fi network, the Hotspot activates immediately.
* **Active Session Protection (Never Drops):** The Hotspot is **never interrupted** while a client is actively connected (e.g., during an active SSH session or configuration). Rescans for saved networks only occur when the Hotspot is completely idle.
* **Guaranteed SSH Access:**
  * Assigns a static gateway IP (`192.168.4.1/24`) to the wireless interface.
  * Manages DHCP leasing automatically for connected phones, laptops, and tablets.
  * Automatically verifies, unmasks, and maintains the OpenSSH daemon (`ssh.service`).
* **WPA2 CCMP/AES Security:** Configured with `proto RSN`, `pairwise CCMP`, and `group CCMP` to ensure immediate and reliable connection from modern iOS, Android, macOS, Linux, and Windows devices.
* **Self-Healing Reconnection:** While the Hotspot is idle (no clients connected), the daemon scans for saved Wi-Fi networks in the background and automatically switches back to client mode once back in range.

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
               │   (probe max 8s)       │                          │
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
          │                     │ (SSH / Mobile / PC)│             │
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

Clone the repository to your Raspberry Pi and run the installation script with root privileges:

```bash
git clone https://github.com/yoloprojekat/smart-network.git
cd smart-network
sudo bash install.sh
```

The installer will automatically:
1. Optimize boot speed by masking blocking wait-online services (`NetworkManager-wait-online.service`, `systemd-networkd-wait-online.service`).
2. Install necessary packages (`network-manager`, `dnsmasq-base`, `wireless-tools`, `iw`, `rfkill`).
3. Ensure Wi-Fi radio is unblocked and configure regulatory domain (`RS`).
4. Ensure OpenSSH server is enabled, unmasked, and running.
5. Install the daemon script to `/opt/smart-network/smart-network.sh`.
6. Create the configuration file at `/etc/default/smart-network`.
7. Install and enable `smart-network.service` under `systemd`.
8. Start the service immediately.

---

## 🔑 Connecting & SSH Access

1. When the vehicle is not in range of a known Wi-Fi network, look for the following Wi-Fi access point:
   * **SSID:** `Pametno-Vozilo_AP`
   * **Password:** `galaksija2026`
2. Your device (laptop, smartphone, tablet) will automatically receive an IP address in the `192.168.4.x` range.
3. Connect via SSH:
   ```bash
   ssh pi@192.168.4.1
   # (or use the username configured during your Raspberry Pi OS setup)
   ```

---

## 📶 Adding a New Wi-Fi Network

> **Note:** You need to be connected to the Hotspot to be able to add a new Wi-Fi network when the Raspberry Pi is offline or in the field.

1. Connect to the Hotspot (`Pametno-Vozilo_AP`) and access the Raspberry Pi via SSH:
   ```bash
   ssh pi@192.168.4.1
   ```
2. Add and connect to the new Wi-Fi network using NetworkManager:
   ```bash
   sudo nmcli dev wifi connect "SSID_NAME" password "WIFI_PASSWORD"
   ```
   *(Or launch the interactive terminal menu with `sudo nmtui`)*.
3. Once the network profile is saved, disconnect from the Hotspot. Smart Network will detect the new Wi-Fi network during its idle scan and connect to it automatically.

---

## ⚙️ Configuration

Settings can be customized in `/etc/default/smart-network` without modifying the core script:

```bash
sudo nano /etc/default/smart-network
```

Example configuration:
```bash
# NetworkManager connection profile name
HOTSPOT_CON_NAME="smart-hotspot"

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
* **Check NetworkManager device state:**
  ```bash
  nmcli dev status
  ```
* **View connected clients (stations):**
  ```bash
  sudo iw dev wlan0 station dump
  ```

---

## 🗑️ Uninstallation

To cleanly remove the service, the NetworkManager hotspot profile, and all installed files:

```bash
sudo bash install.sh --uninstall
```

---

<div align="center">

Author: **Danilo Stoletović**  
**Technical School „Nikola Tesla“ Niš • 2026**

</div>
