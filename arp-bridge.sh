# Enable bridging if you want to control both from Kali
sudo apt install bridge-utils

# Create bridge
sudo brctl addbr br0
sudo brctl addif br0 eth0  # Main network
sudo brctl addif br0 wlan0  # Mesh network
sudo ifconfig br0 up

# Now apply tc rules to br0 instead
sudo tc qdisc add dev br0 root handle 1: htb default 30
# ... rest of tc commands targeting br0
