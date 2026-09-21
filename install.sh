#!/usr/bin/env bash
set -e

# ==============================================================================
# Smart Network Installer (Bash + wpa_supplicant + systemd)
# Lightweight failover hotspot without Docker, Python, or NetworkManager
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
    rm -f "$SYSTEMD_DIR/$SERVICE_NAME"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    echo "✅ Smart Network has been completely uninstalled."
    exit 0
fi

echo "🚀 Installing Smart Network (Pure Bash + wpa_supplicant)..."

# Ensure essential dependencies are installed
echo "📦 Checking and installing dependencies..."
DEPS_TO_INSTALL=()
for pkg in wpasupplicant dnsmasq iproute2 wireless-tools; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        DEPS_TO_INSTALL+=("$pkg")
    fi
done

if [ ${#DEPS_TO_INSTALL[@]} -gt 0 ]; then
    echo "Installing missing packages: ${DEPS_TO_INSTALL[*]}"
    apt-get update
    apt-get install -y "${DEPS_TO_INSTALL[@]}"
fi

# Ensure standalone dnsmasq service does not run globally at boot
# (Smart Network spawns a scoped dnsmasq instance only when the hotspot is active)
if systemctl is-enabled --quiet dnsmasq 2>/dev/null; then
    systemctl disable --now dnsmasq >/dev/null 2>&1 || true
fi

# Create target directory
echo "📁 Setting up installation directory at $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Clean up any legacy Python files if upgrading
rm -f "$INSTALL_DIR/main.py"

# Copy bash failover daemon script
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
EOF
    chmod 644 "$CONFIG_FILE"
fi

# Install systemd unit
echo "📦 Installing systemd service unit to $SYSTEMD_DIR/$SERVICE_NAME..."
cp "$SCRIPT_DIR/smart-network.service" "$SYSTEMD_DIR/$SERVICE_NAME"
chmod 644 "$SYSTEMD_DIR/$SERVICE_NAME"

# Reload systemd and enable + start immediately
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
echo "Uninstall:    sudo bash install.sh --uninstall"
echo "---------------------------------------------------------"
