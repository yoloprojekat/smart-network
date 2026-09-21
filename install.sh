#!/usr/bin/env bash
set -e

# ==============================================================================
# Smart Network Installer (DietPi OS / Debian)
# Ultra-lightweight failover hotspot (Pure Bash + wpasupplicant + systemd)
# ==============================================================================

SERVICE_NAME="smart-network.service"
INSTALL_DIR="/opt/smart-network"
SYSTEMD_DIR="/etc/systemd/system"
CONFIG_FILE="/etc/default/smart-network"
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify root privileges
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: Please run this script with root privileges (e.g. sudo bash install.sh)"
    exit 1
fi

# Handle uninstall flag
if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "-u" ]; then
    echo "🗑️  Uninstalling Smart Network service..."
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
    fi
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME"
    fi
    rm -f "$SYSTEMD_DIR/$SERVICE_NAME"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    echo "✅ Smart Network has been completely uninstalled."
    exit 0
fi

echo "🚀 Installing Smart Network (DietPi / wpasupplicant edition)..."

# 1. Optimize DietPi boot wait times
echo "⚡ Checking DietPi boot optimizations..."
for dietpi_cfg in /boot/dietpi.txt /boot/firmware/dietpi.txt /boot/dietpi/dietpi.txt; do
    if [ -f "$dietpi_cfg" ]; then
        if grep -q "^AUTO_SETUP_BOOT_WAIT_FOR_NETWORK=1" "$dietpi_cfg"; then
            echo "🔧 Disabling DietPi network boot delay (AUTO_SETUP_BOOT_WAIT_FOR_NETWORK=0) in $dietpi_cfg..."
            sed -i 's/^AUTO_SETUP_BOOT_WAIT_FOR_NETWORK=1/AUTO_SETUP_BOOT_WAIT_FOR_NETWORK=0/' "$dietpi_cfg"
        fi
    fi
done

# Disable dietpi-wait-for-network if enabled in systemd to prevent 60-120s boot freeze
if systemctl is-enabled --quiet dietpi-wait-for-network 2>/dev/null; then
    echo "Disabling dietpi-wait-for-network service to prevent boot blocking..."
    systemctl disable --now dietpi-wait-for-network >/dev/null 2>&1 || true
fi

# 2. Ensure essential dependencies are installed
echo "📦 Checking and installing dependencies..."
DEPS_TO_INSTALL=()
for pkg in wpasupplicant dnsmasq iproute2 wireless-tools iw rfkill; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        DEPS_TO_INSTALL+=("$pkg")
    fi
done

# Ensure a DHCP client is available (dhclient, udhcpc, or dhcpcd)
if ! command -v dhclient >/dev/null 2>&1 && \
   ! command -v udhcpc >/dev/null 2>&1 && \
   ! command -v dhcpcd >/dev/null 2>&1; then
    if ! dpkg -s "isc-dhcp-client" >/dev/null 2>&1; then
        DEPS_TO_INSTALL+=("isc-dhcp-client")
    fi
fi

if [ ${#DEPS_TO_INSTALL[@]} -gt 0 ]; then
    echo "Installing missing packages: ${DEPS_TO_INSTALL[*]}"
    apt-get update
    apt-get install -y "${DEPS_TO_INSTALL[@]}"
fi

# Unblock Wi-Fi radio
rfkill unblock wifi 2>/dev/null || true

# 3. Ensure SSH daemon (Dropbear on DietPi or OpenSSH) is active and unmasked
echo "🔑 Verifying SSH service availability..."
if systemctl list-unit-files | grep -q -E '^dropbear\.service'; then
    systemctl unmask dropbear >/dev/null 2>&1 || true
    systemctl enable --now dropbear >/dev/null 2>&1 || true
elif systemctl list-unit-files | grep -q -E '^ssh\.service'; then
    systemctl unmask ssh >/dev/null 2>&1 || true
    systemctl enable --now ssh >/dev/null 2>&1 || true
elif systemctl list-unit-files | grep -q -E '^sshd\.service'; then
    systemctl unmask sshd >/dev/null 2>&1 || true
    systemctl enable --now sshd >/dev/null 2>&1 || true
fi

# Ensure standalone dnsmasq service does not run globally at boot
# (Smart Network runs its own scoped DHCP instance on demand)
if systemctl is-enabled --quiet dnsmasq 2>/dev/null; then
    systemctl disable --now dnsmasq >/dev/null 2>&1 || true
fi

# 4. Ensure wpa_supplicant control interface configuration exists
echo "📡 Verifying wpa_supplicant configuration at $WPA_CONF..."
mkdir -p "$(dirname "$WPA_CONF")"
if [ ! -s "$WPA_CONF" ]; then
    cat << 'EOF' > "$WPA_CONF"
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=RS
EOF
    chmod 600 "$WPA_CONF"
else
    if ! grep -q "ctrl_interface=" "$WPA_CONF"; then
        sed -i '1i ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev' "$WPA_CONF"
    fi
    if ! grep -q "update_config=" "$WPA_CONF"; then
        sed -i '2i update_config=1' "$WPA_CONF"
    fi
    if ! grep -q "country=" "$WPA_CONF"; then
        sed -i '3i country=RS' "$WPA_CONF"
    fi
fi

# 5. Create target directory & copy script
echo "📁 Setting up installation directory at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -f "$INSTALL_DIR/main.py"

cp "$SCRIPT_DIR/smart-network.sh" "$INSTALL_DIR/smart-network.sh"
chmod 755 "$INSTALL_DIR/smart-network.sh"

# Create default configuration if absent
if [ ! -f "$CONFIG_FILE" ]; then
    echo "⚙️  Creating default configuration at $CONFIG_FILE..."
    cat << 'EOF' > "$CONFIG_FILE"
# ==========================================
# Smart Network Configuration
# ==========================================
# HOTSPOT_SSID="Pametno-Vozilo_AP"
# HOTSPOT_PASS="galaksija2026"
# CHECK_INTERVAL=120
# WLAN_INTERFACE="wlan0"
# HOTSPOT_IP="192.168.4.1"
# HOTSPOT_SUBNET="24"
# HOTSPOT_FREQ="2412"
# WIFI_COUNTRY="RS"
EOF
    chmod 644 "$CONFIG_FILE"
fi

# 6. Install systemd unit
echo "📦 Installing systemd service unit to $SYSTEMD_DIR/$SERVICE_NAME..."
cp "$SCRIPT_DIR/smart-network.service" "$SYSTEMD_DIR/$SERVICE_NAME"
chmod 644 "$SYSTEMD_DIR/$SERVICE_NAME"

# 7. Reload systemd and enable + restart immediately
echo "🔄 Reloading systemd daemon..."
systemctl daemon-reload

echo "⚡ Enabling and starting $SERVICE_NAME now..."
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo ""
echo "🎉 Installation complete! Smart Network is running as an ultra-lightweight systemd service."
echo "---------------------------------------------------------"
echo "Status check: sudo systemctl status smart-network"
echo "Live logs:    sudo journalctl -u smart-network -f"
echo "Config file:  $CONFIG_FILE"
echo "SSH login:    ssh root@192.168.4.1 (or ssh dietpi@192.168.4.1)"
echo "              (Default DietPi password is 'pi')"
echo "Uninstall:    sudo bash install.sh --uninstall"
echo "---------------------------------------------------------"
