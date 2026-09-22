#!/usr/bin/env bash
set -e

# ==============================================================================
# Smart Network Installer (Raspberry Pi OS Lite / Debian)
# Failover hotspot powered by NetworkManager (nmcli) & systemd
# ==============================================================================

SERVICE_NAME="smart-network.service"
INSTALL_DIR="/opt/smart-network"
SYSTEMD_DIR="/etc/systemd/system"
CONFIG_FILE="/etc/default/smart-network"
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

    # Remove NetworkManager hotspot connection profile if present
    if command -v nmcli >/dev/null 2>&1; then
        echo "Removing SmartHotspot profile from NetworkManager..."
        nmcli connection delete smart-hotspot >/dev/null 2>&1 || true
    fi

    rm -f "$SYSTEMD_DIR/$SERVICE_NAME"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    echo "✅ Smart Network has been completely uninstalled."
    exit 0
fi

echo "🚀 Installing Smart Network (Raspberry Pi OS Lite edition)..."

# 1. Optimize Raspberry Pi OS boot speed
echo "⚡ Optimizing boot speed (disabling blocking network wait services)..."
# Mask wait-online services that cause 90-120s boot freeze when offline
if systemctl list-unit-files | grep -q -E '^NetworkManager-wait-online\.service'; then
    systemctl disable --now NetworkManager-wait-online.service >/dev/null 2>&1 || true
    systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1 || true
fi

if systemctl list-unit-files | grep -q -E '^systemd-networkd-wait-online\.service'; then
    systemctl disable --now systemd-networkd-wait-online.service >/dev/null 2>&1 || true
    systemctl mask systemd-networkd-wait-online.service >/dev/null 2>&1 || true
fi

# Remove raspi-config wait-for-network override if present
rm -f /etc/systemd/system/dhcpcd.service.d/wait.conf 2>/dev/null || true

# 2. Check and install dependencies
echo "📦 Checking and installing dependencies..."
DEPS_TO_INSTALL=()
for pkg in network-manager dnsmasq-base iproute2 wireless-tools iw rfkill; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        DEPS_TO_INSTALL+=("$pkg")
    fi
done

if [ ${#DEPS_TO_INSTALL[@]} -gt 0 ]; then
    echo "Installing missing packages: ${DEPS_TO_INSTALL[*]}"
    apt-get update
    apt-get install -y "${DEPS_TO_INSTALL[@]}"
fi

# Ensure standalone dnsmasq service does not run globally
# (NetworkManager uses dnsmasq-base internally on demand for AP DHCP)
if systemctl is-enabled --quiet dnsmasq 2>/dev/null; then
    systemctl disable --now dnsmasq >/dev/null 2>&1 || true
fi

# 3. Ensure Wi-Fi radio is unblocked and operational
echo "📡 Unblocking Wi-Fi radio..."
rfkill unblock wifi 2>/dev/null || true

# Set default wireless regulatory domain
if command -v iw >/dev/null 2>&1; then
    iw reg set RS 2>/dev/null || true
fi
if command -v raspi-config >/dev/null 2>&1; then
    raspi-config nonint do_wifi_country RS 2>/dev/null || true
fi

# 4. Ensure OpenSSH server is active and persistent
echo "🔑 Verifying OpenSSH server..."
# Enable SSH flag on Raspberry Pi boot partition
touch /boot/firmware/ssh 2>/dev/null || touch /boot/ssh 2>/dev/null || true

if systemctl list-unit-files | grep -q -E '^ssh\.service'; then
    systemctl unmask ssh >/dev/null 2>&1 || true
    systemctl enable --now ssh >/dev/null 2>&1 || true
elif systemctl list-unit-files | grep -q -E '^sshd\.service'; then
    systemctl unmask sshd >/dev/null 2>&1 || true
    systemctl enable --now sshd >/dev/null 2>&1 || true
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
# HOTSPOT_CON_NAME="smart-hotspot"
# HOTSPOT_SSID="Pametno-Vozilo_AP"
# HOTSPOT_PASS="galaksija2026"
# CHECK_INTERVAL=120
# WLAN_INTERFACE="wlan0"
# HOTSPOT_IP="192.168.4.1"
# HOTSPOT_SUBNET="24"
# WIFI_COUNTRY="RS"
EOF
    chmod 644 "$CONFIG_FILE"
fi

# 6. Install systemd unit
echo "📦 Installing systemd service unit to $SYSTEMD_DIR/$SERVICE_NAME..."
cp "$SCRIPT_DIR/smart-network.service" "$SYSTEMD_DIR/$SERVICE_NAME"
chmod 644 "$SYSTEMD_DIR/$SERVICE_NAME"

# 7. Reload systemd and enable + start immediately
echo "🔄 Reloading systemd daemon..."
systemctl daemon-reload

echo "⚡ Enabling and starting $SERVICE_NAME now..."
systemctl enable --now "$SERVICE_NAME"

echo ""
echo "🎉 Installation complete! Smart Network is running as an ultra-lightweight systemd service."
echo "---------------------------------------------------------"
echo "Status check: sudo systemctl status smart-network"
echo "Live logs:    sudo journalctl -u smart-network -f"
echo "Config file:  $CONFIG_FILE"
echo "SSH login:    ssh <user>@192.168.4.1 (e.g. ssh pi@192.168.4.1)"
echo "Uninstall:    sudo bash install.sh --uninstall"
echo "---------------------------------------------------------"
