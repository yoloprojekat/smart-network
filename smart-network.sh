#!/usr/bin/env bash
# ==============================================================================
# Smart Network - Lightweight Failover Hotspot
# Pure Bash & wpa_supplicant implementation (Zero Docker, Zero Python)
# ==============================================================================

set -u

# Configuration (can be overridden via /etc/default/smart-network)
HOTSPOT_SSID="${HOTSPOT_SSID:-Pametno-Vozilo_AP}"
HOTSPOT_PASS="${HOTSPOT_PASS:-galaksija2026}"
CHECK_INTERVAL="${CHECK_INTERVAL:-120}"
WLAN_IFACE="${WLAN_INTERFACE:-wlan0}"
HOTSPOT_IP="${HOTSPOT_IP:-192.168.4.1}"
HOTSPOT_SUBNET="${HOTSPOT_SUBNET:-24}"
HOTSPOT_FREQ="${HOTSPOT_FREQ:-2412}"
WPA_CONF="${WPA_CONF:-/etc/wpa_supplicant/wpa_supplicant.conf}"
DNSMASQ_PID_FILE="/run/smart-network-dnsmasq.pid"

cleanup() {
    echo "Shutting down Smart Network service..."
    stop_dhcp
    ip addr del "${HOTSPOT_IP}/${HOTSPOT_SUBNET}" dev "$WLAN_IFACE" 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM SIGHUP

stop_dhcp() {
    if [ -f "$DNSMASQ_PID_FILE" ]; then
        local pid
        pid=$(cat "$DNSMASQ_PID_FILE" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$DNSMASQ_PID_FILE"
    fi
}

start_dhcp() {
    if command -v dnsmasq >/dev/null 2>&1; then
        stop_dhcp
        dnsmasq \
            --interface="$WLAN_IFACE" \
            --bind-interfaces \
            --dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,12h \
            --conf-file=/dev/null \
            --dhcp-option=3,"$HOTSPOT_IP" \
            --dhcp-option=6,"$HOTSPOT_IP" \
            --pid-file="$DNSMASQ_PID_FILE"
    fi
}

get_hotspot_id() {
    wpa_cli -i "$WLAN_IFACE" list_networks 2>/dev/null | tail -n +2 | while IFS=$'\t' read -r id ssid flags rest; do
        if [ "$ssid" = "$HOTSPOT_SSID" ]; then
            echo "$id"
            return 0
        fi
    done
}

ensure_wpa_supplicant() {
    local retries=20
    while [ $retries -gt 0 ]; do
        if wpa_cli -i "$WLAN_IFACE" ping 2>/dev/null | grep -q "PONG"; then
            return 0
        fi
        echo "Waiting for wpa_supplicant on $WLAN_IFACE..."
        sleep 1
        retries=$((retries - 1))
    done

    # If not running, start wpa_supplicant in background
    if ! pgrep -f "wpa_supplicant.*$WLAN_IFACE" >/dev/null 2>&1; then
        echo "Starting wpa_supplicant for interface $WLAN_IFACE..."
        wpa_supplicant -B -i "$WLAN_IFACE" -c "$WPA_CONF" 2>/dev/null || true
        sleep 2
    fi
}

setup_hotspot() {
    local hs_id
    hs_id=$(get_hotspot_id)
    if [ -z "$hs_id" ]; then
        echo "Creating SmartHotspot profile in wpa_supplicant: $HOTSPOT_SSID"
        hs_id=$(wpa_cli -i "$WLAN_IFACE" add_network 2>/dev/null | tail -n 1 | tr -d '\r\n')
        if [ -n "$hs_id" ] && [ "$hs_id" -eq "$hs_id" ] 2>/dev/null; then
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" ssid "\"$HOTSPOT_SSID\"" >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" mode 2 >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" key_mgmt WPA-PSK >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" psk "\"$HOTSPOT_PASS\"" >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" frequency "$HOTSPOT_FREQ" >/dev/null
            wpa_cli -i "$WLAN_IFACE" disable_network "$hs_id" >/dev/null
            echo "SmartHotspot profile created with network ID $hs_id (disabled by default)."
        else
            echo "Warning: Could not create hotspot profile via wpa_cli."
        fi
    else
        echo "SmartHotspot profile exists with network ID $hs_id."
    fi
}

is_connected_to_client_network() {
    local status wpa_state mode ssid
    status=$(wpa_cli -i "$WLAN_IFACE" status 2>/dev/null) || return 1
    wpa_state=$(echo "$status" | awk -F= '$1=="wpa_state" {print $2}')
    mode=$(echo "$status" | awk -F= '$1=="mode" {print $2}')
    ssid=$(echo "$status" | awk -F= '$1=="ssid" {print $2}')

    [ "$wpa_state" = "COMPLETED" ] && [ "$mode" != "AP" ] && [ "$ssid" != "$HOTSPOT_SSID" ]
}

start_hotspot() {
    echo "Action: No known networks found. Activating Hotspot ($HOTSPOT_SSID)..."
    local hs_id
    hs_id=$(get_hotspot_id)
    if [ -n "$hs_id" ]; then
        wpa_cli -i "$WLAN_IFACE" select_network "$hs_id" >/dev/null
    fi
    ip addr replace "${HOTSPOT_IP}/${HOTSPOT_SUBNET}" dev "$WLAN_IFACE"
    start_dhcp
    echo "Hotspot active on $HOTSPOT_IP (SSID: $HOTSPOT_SSID)"
}

stop_hotspot() {
    echo "Action: Known network detected. Deactivating Hotspot, returning to client mode..."
    stop_dhcp
    ip addr del "${HOTSPOT_IP}/${HOTSPOT_SUBNET}" dev "$WLAN_IFACE" 2>/dev/null || true
    if command -v dhclient >/dev/null 2>&1; then
        dhclient -r "$WLAN_IFACE" 2>/dev/null || true
        dhclient "$WLAN_IFACE" 2>/dev/null &
    elif command -v dhcpcd >/dev/null 2>&1; then
        dhcpcd -n "$WLAN_IFACE" 2>/dev/null || true
    fi
}

main() {
    echo "--- Smart Network Initialized (Bash & wpa_supplicant) ---"
    ensure_wpa_supplicant
    setup_hotspot

    local hotspot_active=0

    while true; do
        if is_connected_to_client_network; then
            if [ "$hotspot_active" -eq 1 ]; then
                stop_hotspot
                hotspot_active=0
            fi
            echo "Status: Connected to saved Wi-Fi network."
        else
            echo "Status: Disconnected. Rescanning for saved networks..."
            # Enable all saved networks and disable hotspot during scan attempt
            wpa_cli -i "$WLAN_IFACE" enable_network all >/dev/null 2>&1 || true
            local hs_id
            hs_id=$(get_hotspot_id)
            if [ -n "$hs_id" ]; then
                wpa_cli -i "$WLAN_IFACE" disable_network "$hs_id" >/dev/null 2>&1 || true
            fi

            wpa_cli -i "$WLAN_IFACE" scan >/dev/null 2>&1 || true
            sleep 15  # Wait for auto-connect attempt

            if is_connected_to_client_network; then
                if [ "$hotspot_active" -eq 1 ]; then
                    stop_hotspot
                    hotspot_active=0
                fi
                echo "Status: Connected to saved Wi-Fi network after rescan."
            else
                if [ "$hotspot_active" -eq 0 ]; then
                    start_hotspot
                    hotspot_active=1
                else
                    echo "Status: Still disconnected. Hotspot remains active."
                fi
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main
