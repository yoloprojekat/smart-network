#!/usr/bin/env bash
# ==============================================================================
# Smart Network - Failover Hotspot (Raspberry Pi OS Lite)
# Pure Bash + NetworkManager (nmcli) + systemd
# ==============================================================================

set -u

# Configuration (can be overridden via /etc/default/smart-network)
HOTSPOT_CON_NAME="${HOTSPOT_CON_NAME:-smart-hotspot}"
HOTSPOT_SSID="${HOTSPOT_SSID:-Pametno-Vozilo_AP}"
HOTSPOT_PASS="${HOTSPOT_PASS:-galaksija2026}"
CHECK_INTERVAL="${CHECK_INTERVAL:-120}"
WLAN_IFACE="${WLAN_INTERFACE:-wlan0}"
HOTSPOT_IP="${HOTSPOT_IP:-192.168.4.1}"
HOTSPOT_SUBNET="${HOTSPOT_SUBNET:-24}"
WIFI_COUNTRY="${WIFI_COUNTRY:-RS}"

HOTSPOT_ACTIVE=0

cleanup() {
    echo "Shutting down Smart Network service..."
    if [ "$HOTSPOT_ACTIVE" -eq 1 ]; then
        nmcli connection down "$HOTSPOT_CON_NAME" >/dev/null 2>&1 || true
        nmcli device connect "$WLAN_IFACE" >/dev/null 2>&1 || true
    fi
    exit 0
}

trap cleanup SIGINT SIGTERM SIGHUP

ensure_ssh_running() {
    if systemctl is-active --quiet ssh 2>/dev/null || \
       systemctl is-active --quiet sshd 2>/dev/null; then
        return 0
    fi

    echo "Ensuring SSH service is active on Raspberry Pi OS..."
    systemctl unmask ssh 2>/dev/null || true
    systemctl restart ssh 2>/dev/null || systemctl start ssh 2>/dev/null || true
    systemctl unmask sshd 2>/dev/null || true
    systemctl restart sshd 2>/dev/null || systemctl start sshd 2>/dev/null || true
}

ensure_wifi_ready() {
    rfkill unblock wifi 2>/dev/null || true
    if command -v iw >/dev/null 2>&1; then
        iw reg set "$WIFI_COUNTRY" 2>/dev/null || true
    fi
    nmcli device set "$WLAN_IFACE" managed yes 2>/dev/null || true
}

setup_hotspot_profile() {
    if ! nmcli connection show "$HOTSPOT_CON_NAME" >/dev/null 2>&1; then
        echo "Creating SmartHotspot profile in NetworkManager: $HOTSPOT_SSID"
        nmcli connection add \
            type wifi \
            ifname "$WLAN_IFACE" \
            con-name "$HOTSPOT_CON_NAME" \
            autoconnect no \
            ssid "$HOTSPOT_SSID" \
            802-11-wireless.mode ap \
            802-11-wireless.band bg \
            802-11-wireless-security.key-mgmt wpa-psk \
            802-11-wireless-security.proto rsn \
            802-11-wireless-security.pairwise ccmp \
            802-11-wireless-security.group ccmp \
            802-11-wireless-security.psk "$HOTSPOT_PASS" \
            ipv4.method shared \
            ipv4.addresses "${HOTSPOT_IP}/${HOTSPOT_SUBNET}" \
            ipv6.method ignore >/dev/null 2>&1
    else
        nmcli connection modify "$HOTSPOT_CON_NAME" \
            connection.interface-name "$WLAN_IFACE" \
            connection.autoconnect no \
            802-11-wireless.ssid "$HOTSPOT_SSID" \
            802-11-wireless.mode ap \
            802-11-wireless.band bg \
            802-11-wireless-security.key-mgmt wpa-psk \
            802-11-wireless-security.proto rsn \
            802-11-wireless-security.pairwise ccmp \
            802-11-wireless-security.group ccmp \
            802-11-wireless-security.psk "$HOTSPOT_PASS" \
            ipv4.method shared \
            ipv4.addresses "${HOTSPOT_IP}/${HOTSPOT_SUBNET}" \
            ipv6.method ignore >/dev/null 2>&1
    fi
}

is_connected_to_client() {
    local conn state
    conn=$(nmcli -g GENERAL.CONNECTION device show "$WLAN_IFACE" 2>/dev/null || true)
    state=$(nmcli -g GENERAL.STATE device show "$WLAN_IFACE" 2>/dev/null || true)

    if [[ "$state" =~ ^100 ]] && [ -n "$conn" ] && [ "$conn" != "--" ] && [ "$conn" != "$HOTSPOT_CON_NAME" ]; then
        return 0
    fi
    return 1
}

get_current_ssid() {
    local conn
    conn=$(nmcli -g GENERAL.CONNECTION device show "$WLAN_IFACE" 2>/dev/null || true)
    if [ -n "$conn" ] && [ "$conn" != "--" ]; then
        local ssid
        ssid=$(nmcli -g 802-11-wireless.ssid connection show "$conn" 2>/dev/null || true)
        if [ -n "$ssid" ]; then
            echo "$ssid"
            return
        fi
        echo "$conn"
    fi
}

get_current_ip() {
    local ip_addr
    ip_addr=$(nmcli -g IP4.ADDRESS device show "$WLAN_IFACE" 2>/dev/null | head -n 1 | cut -d/ -f1)
    if [ -n "$ip_addr" ]; then
        echo "$ip_addr"
    else
        ip -4 addr show dev "$WLAN_IFACE" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n 1
    fi
}

has_connected_clients() {
    # 1. Kernel-level station dump via iw
    if command -v iw >/dev/null 2>&1; then
        if iw dev "$WLAN_IFACE" station dump 2>/dev/null | grep -q "Station "; then
            return 0
        fi
    fi

    # 2. Check NetworkManager dnsmasq lease files
    for leasefile in "/var/lib/NetworkManager/dnsmasq-${WLAN_IFACE}.leases" \
                     "/var/lib/misc/dnsmasq.leases" \
                     "/var/lib/NetworkManager/dnsmasq.leases"; do
        if [ -s "$leasefile" ]; then
            return 0
        fi
    done

    # 3. Check ARP neighbor table for active devices on WLAN_IFACE
    if command -v ip >/dev/null 2>&1; then
        if ip neigh show dev "$WLAN_IFACE" 2>/dev/null | grep -E -v 'FAILED|INCOMPLETE' | grep -q -E 'REACHABLE|DELAY|STALE'; then
            return 0
        fi
    fi

    return 1
}

start_hotspot() {
    echo "Action: Activating SmartHotspot ($HOTSPOT_SSID)..."
    ensure_wifi_ready
    setup_hotspot_profile

    nmcli connection up "$HOTSPOT_CON_NAME" >/dev/null 2>&1 || true
    ensure_ssh_running

    HOTSPOT_ACTIVE=1
    local actual_ip
    actual_ip=$(get_current_ip)
    [ -z "$actual_ip" ] && actual_ip="$HOTSPOT_IP"

    echo "✅ Hotspot active! IP: $actual_ip, SSID: '$HOTSPOT_SSID'"
    echo "👉 SSH ready: ssh <user>@$actual_ip (e.g. ssh pi@$actual_ip)"
}

stop_hotspot() {
    echo "Action: Deactivating Hotspot, returning to Wi-Fi client mode..."
    nmcli connection down "$HOTSPOT_CON_NAME" >/dev/null 2>&1 || true
    nmcli device connect "$WLAN_IFACE" >/dev/null 2>&1 || true
    HOTSPOT_ACTIVE=0
}

check_and_reconnect_saved_networks() {
    local saved_conns
    saved_conns=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null | awk -F: -v hs="$HOTSPOT_CON_NAME" '($2=="802-11-wireless" || $2=="wifi") && $1!=hs {print $1}')

    if [ -z "$saved_conns" ]; then
        echo "No saved client Wi-Fi networks found in NetworkManager. Hotspot remains active."
        return 0
    fi

    echo "Status: Hotspot idle. Scanning for saved networks..."
    nmcli connection down "$HOTSPOT_CON_NAME" >/dev/null 2>&1 || true
    sleep 1

    nmcli device wifi rescan ifname "$WLAN_IFACE" >/dev/null 2>&1 || true
    sleep 3

    local scanned_ssids
    scanned_ssids=$(nmcli -t -f SSID dev wifi list ifname "$WLAN_IFACE" 2>/dev/null || true)

    local target_conn=""
    while IFS= read -r con; do
        [ -z "$con" ] && continue
        local ssid
        ssid=$(nmcli -g 802-11-wireless.ssid connection show "$con" 2>/dev/null || true)
        [ -z "$ssid" ] && ssid="$con"
        if echo "$scanned_ssids" | grep -Fqx "$ssid"; then
            target_conn="$con"
            break
        fi
    done <<< "$saved_conns"

    if [ -n "$target_conn" ]; then
        echo "Detected saved network nearby: '$target_conn'. Connecting..."
        nmcli connection up "$target_conn" >/dev/null 2>&1 || true

        local wait_conn=8
        while [ $wait_conn -gt 0 ]; do
            if is_connected_to_client; then
                echo "✅ Connected to saved network: '$(get_current_ssid)' (IP: $(get_current_ip))."
                HOTSPOT_ACTIVE=0
                return 0
            fi
            sleep 1
            wait_conn=$((wait_conn - 1))
        done
    fi

    echo "No saved networks available or connection failed. Re-activating Hotspot..."
    start_hotspot
}

main() {
    echo "--- Smart Network Initialized (Raspberry Pi OS / NetworkManager) ---"
    ensure_wifi_ready
    setup_hotspot_profile

    # Initial boot probe: wait up to 8s for NetworkManager to connect to known Wi-Fi
    echo "Checking initial Wi-Fi connection..."
    local probe=8
    while [ $probe -gt 0 ]; do
        if is_connected_to_client; then
            echo "Status: Connected to saved Wi-Fi network '$(get_current_ssid)' (IP: $(get_current_ip)) at boot."
            HOTSPOT_ACTIVE=0
            break
        fi
        sleep 1
        probe=$((probe - 1))
    done

    # If no saved Wi-Fi connected within 8s, start Hotspot immediately
    if ! is_connected_to_client; then
        echo "No saved network connected. Fast-booting Hotspot..."
        start_hotspot
    fi

    while true; do
        sleep "$CHECK_INTERVAL"

        if [ "$HOTSPOT_ACTIVE" -eq 1 ]; then
            # 1. Active session protection: If a client is connected (active SSH session), NEVER interrupt!
            if has_connected_clients; then
                echo "Status: Hotspot in use by connected client(s). Maintaining stable connection."
                continue
            fi

            # 2. Hotspot is idle (no clients). Check if saved networks are nearby before dropping AP
            check_and_reconnect_saved_networks

        else
            # Client mode: monitor connection health
            if is_connected_to_client; then
                echo "Status: Connected to saved Wi-Fi network '$(get_current_ssid)' (IP: $(get_current_ip))."
            else
                echo "Status: Disconnected from saved network. Rescanning..."
                nmcli device wifi rescan ifname "$WLAN_IFACE" >/dev/null 2>&1 || true
                sleep 4
                if is_connected_to_client; then
                    echo "Status: Reconnected to saved network '$(get_current_ssid)' (IP: $(get_current_ip))."
                else
                    echo "Action: Saved network unavailable. Activating Hotspot..."
                    start_hotspot
                fi
            fi
        fi
    done
}

main
