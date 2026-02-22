# On Kali, prioritize your own traffic
INTERFACE="wlan0"  # or eth0
KALI_IP="192.168.68.75"  # Your IP

# Create hierarchy
sudo tc qdisc add dev $INTERFACE root handle 1: htb default 20

# Create classes - 70% for you, 30% for others
TOTAL_BANDWIDTH="100mbit"  # Adjust to your actual speed
YOUR_SHARE="70mbit"
OTHER_SHARE="30mbit"

sudo tc class add dev $INTERFACE parent 1: classid 1:1 htb rate $YOUR_SHARE ceil $TOTAL_BANDWIDTH
sudo tc class add dev $INTERFACE parent 1: classid 1:2 htb rate $OTHER_SHARE ceil $OTHER_SHARE

# Filter your traffic to high priority class
sudo tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip src $KALI_IP flowid 1:1

# All other traffic gets lower priority
sudo tc filter add dev $INTERFACE protocol ip parent 1:0 prio 2 match any flowid 1:2
