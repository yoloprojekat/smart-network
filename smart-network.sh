#!/usr/bin/env bash
# ==============================================================================
# Smart Network - Ultra-Lightweight Failover Hotspot (DietPi & Debian)
# Pure Bash & wpasupplicant (Zero Docker, Zero Python, Zero NetworkManager)
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
WIFI_COUNTRY="${WIFI_COUNTRY:-RS}"
WPA_CONF="${WPA_CONF:-/etc/wpa_supplicant/wpa_supplicant.conf}"
DNSMASQ_PID_FILE="/run/smart-network-dnsmasq.pid"
HOTSPOT_ACTIVE=0

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
    stop_dhcp
    if command -v dnsmasq >/dev/null 2>&1; then
        touch /tmp/dnsmasq.leases
        chmod 644 /tmp/dnsmasq.leases

        # --port=0 disables DNS server to prevent conflicts with systemd-resolved, pi-hole, unbound
        # --bind-dynamic binds only to wlan0 without locking global sockets
        # --dhcp-authoritative guarantees fast IP lease assignment to connecting clients
        dnsmasq \
            --interface="$WLAN_IFACE" \
            --bind-dynamic \
            --port=0 \
            --dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,12h \
            --dhcp-option=option:router,"$HOTSPOT_IP" \
            --dhcp-option=option:dns-server,"$HOTSPOT_IP" \
            --dhcp-leasefile=/tmp/dnsmasq.leases \
            --dhcp-authoritative \
            --conf-file=/dev/null \
            --pid-file="$DNSMASQ_PID_FILE"

        sleep 1
        if [ -f "$DNSMASQ_PID_FILE" ] && kill -0 "$(cat "$DNSMASQ_PID_FILE")" 2>/dev/null; then
            echo "DHCP server (dnsmasq) active on $WLAN_IFACE [PID $(cat "$DNSMASQ_PID_FILE")]."
        fi
    else
        echo "Warning: dnsmasq not found. Clients may need static IP configuration."
    fi
}

ensure_ssh_running() {
    if systemctl is-active --quiet dropbear 2>/dev/null || \
       systemctl is-active --quiet ssh 2>/dev/null || \
       systemctl is-active --quiet sshd 2>/dev/null; then
        echo "SSH service is active and listening."
        return 0
    fi

    echo "Ensuring SSH service is active on DietPi..."
    if systemctl list-unit-files | grep -q -E '^dropbear\.service'; then
        systemctl unmask dropbear 2>/dev/null || true
        systemctl restart dropbear 2>/dev/null || systemctl start dropbear 2>/dev/null || true
    elif systemctl list-unit-files | grep -q -E '^ssh\.service'; then
        systemctl unmask ssh 2>/dev/null || true
        systemctl restart ssh 2>/dev/null || systemctl start ssh 2>/dev/null || true
    elif systemctl list-unit-files | grep -q -E '^sshd\.service'; then
        systemctl unmask sshd 2>/dev/null || true
        systemctl restart sshd 2>/dev/null || systemctl start sshd 2>/dev/null || true
    fi

    # Fallback to direct dropbear if daemon failed under systemd
    if ! pgrep -x dropbear >/dev/null 2>&1 && ! pgrep -x sshd >/dev/null 2>&1; then
        if command -v dropbear >/dev/null 2>&1; then
            echo "Spawning direct dropbear listener on port 22..."
            dropbear -p 22 2>/dev/null || true
        fi
    fi
}

ensure_wpa_config() {
    mkdir -p "$(dirname "$WPA_CONF")"
    if [ ! -f "$WPA_CONF" ]; then
        echo "Creating initial $WPA_CONF..."
        cat << EOF > "$WPA_CONF"
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=${WIFI_COUNTRY}
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
            sed -i "3i country=${WIFI_COUNTRY}" "$WPA_CONF"
        fi
    fi
}

ensure_wpa_supplicant() {
    rfkill unblock wifi 2>/dev/null || true
    command -v iw >/dev/null 2>&1 && iw reg set "$WIFI_COUNTRY" 2>/dev/null || true
    ip link set dev "$WLAN_IFACE" up 2>/dev/null || true
    ensure_wpa_config

    if wpa_cli -i "$WLAN_IFACE" ping 2>/dev/null | grep -q "PONG"; then
        return 0
    fi

    if ! pgrep -f "wpa_supplicant.*$WLAN_IFACE" >/dev/null 2>&1; then
        echo "Starting wpasupplicant on $WLAN_IFACE..."
        mkdir -p /var/run/wpa_supplicant
        wpa_supplicant -B -i "$WLAN_IFACE" -c "$WPA_CONF" 2>/dev/null || true
    fi

    local retries=5
    while [ $retries -gt 0 ]; do
        if wpa_cli -i "$WLAN_IFACE" ping 2>/dev/null | grep -q "PONG"; then
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done
}

get_hotspot_id() {
    wpa_cli -i "$WLAN_IFACE" list_networks 2>/dev/null | tail -n +2 | while IFS=$'\t' read -r id ssid flags rest; do
        if [ "$ssid" = "$HOTSPOT_SSID" ]; then
            echo "$id"
            return 0
        fi
    done
}

setup_hotspot() {
    local hs_id
    hs_id=$(get_hotspot_id)
    if [ -z "$hs_id" ]; then
        echo "Configuring SmartHotspot profile in wpa_supplicant: $HOTSPOT_SSID"
        hs_id=$(wpa_cli -i "$WLAN_IFACE" add_network 2>/dev/null | tail -n 1 | tr -d '\r\n')
        if [ -n "$hs_id" ] && [ "$hs_id" -eq "$hs_id" ] 2>/dev/null; then
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" ssid "\"$HOTSPOT_SSID\"" >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" mode 2 >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" proto RSN >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" key_mgmt WPA-PSK >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" pairwise CCMP >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" group CCMP >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" psk "\"$HOTSPOT_PASS\"" >/dev/null
            wpa_cli -i "$WLAN_IFACE" set_network "$hs_id" frequency "$HOTSPOT_FREQ" >/dev/null
            wpa_cli -i "$WLAN_IFACE" disable_network "$hs_id" >/dev/null
            wpa_cli -i "$WLAN_IFACE" save_config >/dev/null 2>&1 || true
            echo "SmartHotspot profile created (network ID $hs_id)."
        else
            echo "Warning: Failed to create hotspot profile via wpa_cli."
        fi
    else
        echo "SmartHotspot profile exists (network ID $hs_id)."
    fi
}

has_connected_clients() {
    # 1. Check via iw station dump
    if command -v iw >/dev/null 2>&1; then
        if iw dev "$WLAN_IFACE" station dump 2>/dev/null | grep -q "Station "; then
            return 0
        fi
    fi

    # 2. Check via wpa_cli all_sta
    if wpa_cli -i "$WLAN_IFACE" all_sta 2>/dev/null | grep -q -E "^[0-9a-fA-F:]{17}"; then
        return 0
    fi

    # 3. Check active DHCP leases in /tmp/dnsmasq.leases
    if [ -s /tmp/dnsmasq.leases ]; then
        return 0
    fi

    return 1
}

is_connected_to_client() {
    local status wpa_state mode ssid
    status=$(wpa_cli -i "$WLAN_IFACE" status 2>/dev/null) || return 1
    wpa_state=$(echo "$status" | awk -F= '$1=="wpa_state" {print $2}')
    mode=$(echo "$status" | awk -F= '$1=="mode" {print $2}')
    ssid=$(echo "$status" | awk -F= '$1=="ssid" {print $2}')

    [ "$wpa_state" = "COMPLETED" ] && [ "$mode" != "AP" ] && [ "$ssid" != "$HOTSPOT_SSID" ]
}

start_hotspot() {
    echo "Action: Activating SmartHotspot ($HOTSPOT_SSID)..."
    rfkill unblock wifi 2>/dev/null || true
    command -v iw >/dev/null 2>&1 && iw reg set "$WIFI_COUNTRY" 2>/dev/null || true
    ip link set dev "$WLAN_IFACE" up 2>/dev/null || true

    local hs_id
    hs_id=$(get_hotspot_id)
    if [ -z "$hs_id" ]; then
        setup_hotspot
        hs_id=$(get_hotspot_id)
    fi

    if [ -n "$hs_id" ]; then
        wpa_cli -i "$WLAN_IFACE" select_network "$hs_id" >/dev/null 2>&1 || true
    fi

    # Configure static IP and link subnet routing
    ip addr replace "${HOTSPOT_IP}/${HOTSPOT_SUBNET}" dev "$WLAN_IFACE"
    ip route replace "${HOTSPOT_IP%.*}.0/${HOTSPOT_SUBNET}" dev "$WLAN_IFACE" scope link src "$HOTSPOT_IP" 2>/dev/null || true

    start_dhcp
    ensure_ssh_running

    HOTSPOT_ACTIVE=1
    echo "✅ Hotspot active! IP: $HOTSPOT_IP, SSID: '$HOTSPOT_SSID'"
    echo "👉 SSH ready: ssh root@$HOTSPOT_IP or ssh dietpi@$HOTSPOT_IP"
}

stop_hotspot() {
    echo "Action: Deactivating Hotspot, returning to client mode..."
    stop_dhcp
    ip addr del "${HOTSPOT_IP}/${HOTSPOT_SUBNET}" dev "$WLAN_IFACE" 2>/dev/null || true
    rm -f /tmp/dnsmasq.leases

    wpa_cli -i "$WLAN_IFACE" enable_network all >/dev/null 2>&1 || true
    local hs_id
    hs_id=$(get_hotspot_id)
    if [ -n "$hs_id" ]; then
        wpa_cli -i "$WLAN_IFACE" disable_network "$hs_id" >/dev/null 2>&1 || true
    fi

    if command -v dhclient >/dev/null 2>&1; then
        dhclient -r "$WLAN_IFACE" 2>/dev/null || true
        dhclient "$WLAN_IFACE" 2>/dev/null &
    elif command -v dhcpcd >/dev/null 2>&1; then
        dhcpcd -n "$WLAN_IFACE" 2>/dev/null || true
    elif command -v ifup >/dev/null 2>&1; then
        ifup "$WLAN_IFACE" 2>/dev/null || true
    fi

    HOTSPOT_ACTIVE=0
}

main() {
    echo "--- Smart Network Initialized (DietPi / wpasupplicant) ---"
    ensure_wpa_supplicant
    setup_hotspot

    # Initial boot probe (fast check, max 5s)
    echo "Checking initial Wi-Fi connection..."
    local probe=5
    while [ $probe -gt 0 ]; do
        if is_connected_to_client; then
            echo "Status: Connected to saved Wi-Fi network at boot."
            break
        fi
        sleep 1
        probe=$((probe - 1))
    done

    # If no saved Wi-Fi connected within 5s, start Hotspot immediately
    if ! is_connected_to_client; then
        echo "No saved network detected. Fast-booting Hotspot..."
        start_hotspot
    fi

    while true; do
        sleep "$CHECK_INTERVAL"

        if [ "$HOTSPOT_ACTIVE" -eq 1 ]; then
            # CRITICAL: If a client is connected (active SSH session), NEVER interrupt!
            if has_connected_clients; then
                echo "Status: Hotspot in use by connected client(s). Maintaining stable connection."
                continue
            fi

            # Hotspot is idle (no clients). Check if saved networks are nearby before dropping AP
            echo "Status: Hotspot idle. Scanning for saved networks..."
            wpa_cli -i "$WLAN_IFACE" scan >/dev/null 2>&1 || true
            sleep 3

            local found_saved=0
            local saved_ssids
            saved_ssids=$(wpa_cli -i "$WLAN_IFACE" list_networks 2>/dev/null | tail -n +2 | awk -F'\t' '{print $2}')
            local scan_res
            scan_res=$(wpa_cli -i "$WLAN_IFACE" scan_results 2>/dev/null | tail -n +2 | awk -F'\t' '{print $5}')

            for s in $saved_ssids; do
                if [ -n "$s" ] && [ "$s" != "$HOTSPOT_SSID" ]; then
                    if echo "$scan_res" | grep -Fqx "$s"; then
                        echo "Detected saved network nearby: $s"
                        found_saved=1
                        break
                    fi
                fi
            done

            if [ "$found_saved" -eq 1 ]; then
                echo "Switching from Hotspot to saved network: $s..."
                stop_hotspot
                sleep 5
                if is_connected_to_client; then
                    echo "Successfully reconnected to saved network."
                else
                    echo "Failed to connect to saved network, re-activating Hotspot..."
                    start_hotspot
                fi
            else
                echo "No saved networks in vicinity. Hotspot remains active."
            fi

        else
            # Client mode: monitor connection health
            if is_connected_to_client; then
                echo "Status: Connected to saved Wi-Fi network."
            else
                echo "Status: Disconnected from saved network. Rescanning..."
                wpa_cli -i "$WLAN_IFACE" scan >/dev/null 2>&1 || true
                sleep 5
                if is_connected_to_client; then
                    echo "Status: Reconnected to saved network."
                else
                    echo "Action: Saved network lost. Activating Hotspot..."
                    start_hotspot
                fi
            fi
        fi
    done
}

main
