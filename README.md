# Wireless QoS & ARP Scripts

Linux CLI scripts that use ARP spoofing and `tc` (traffic control) to enforce two-tier QoS on one or two networks (mesh + main router), with MAC-based high-priority device selection. Give your devices more bandwidth while limiting others on the same LAN.

## Requirements

- **System:** Linux (tested on Kali); root/sudo required.
- **Tools:** `arp-scan`, `arpspoof` (dsniff), `tc` (iproute2). Optional: `bc` for rate math in `qos_dual_network.sh`.

**Install on Debian/Ubuntu/Kali:**

```bash
sudo apt install arp-scan dsniff iproute2
```

## Main script: qos_dual_network.sh

The primary script: two-tier QoS on **two networks** (e.g. mesh WiFi + main router). It uses ARP spoofing so traffic from non–high-priority devices flows through your machine, and applies `tc` HTB so high-priority devices (identified by MAC address) get a larger share of bandwidth on both interfaces.

### Configuration (edit the top of the script)

| Variable | Description |
|----------|-------------|
| `MESH_INTERFACE` / `MAIN_INTERFACE` | e.g. `wlan1`, `eth0` |
| `MESH_GATEWAY` / `MAIN_GATEWAY` | Router IPs, e.g. `192.168.68.1`, `192.168.1.254` |
| `MESH_NETWORK` / `MAIN_NETWORK` | Subnets, e.g. `192.168.68.0/24`, `192.168.1.0/24` |
| `TOTAL_BANDWIDTH` | e.g. `100mbit` |
| `HIGH_PRIORITY_PERCENT` / `LOW_PRIORITY_PERCENT` | e.g. 70% / 30% |
| `HIGH_PRIORITY_MACS` | List of MAC addresses; IPs are resolved at start via `arp-scan`. Use `scan` to discover devices. |

### Commands

| Command | Description |
|---------|-------------|
| `start` | Start QoS: enable IP forwarding, ARP spoof non-priority hosts on both nets, set up tc on both interfaces, assign high/low priority by IP (from MACs + gateways). |
| `stop` | Kill arpspoof, clear tc, disable forwarding, flush ARP cache. |
| `status` | Show tc qdisc/classes and active arpspoof processes. |
| `list` | List configured high-priority MACs. |
| `scan` | Run arp-scan on both networks; show IP and MAC to fill `HIGH_PRIORITY_MACS`. |
| `add <MAC>` | Print the line to add to `HIGH_PRIORITY_MACS` and remind to restart. |

### Usage

```bash
sudo ./qos_dual_network.sh start|stop|status|list|scan|add <MAC>
```

### Install as a command (optional)

Copy to PATH and run like a normal command:

```bash
sudo cp qos_dual_network.sh /usr/local/bin/qos-dual-network
sudo chmod +x /usr/local/bin/qos-dual-network
```

Then:

```bash
sudo qos-dual-network start
sudo qos-dual-network stop
sudo qos-dual-network status
# etc.
```

## Other scripts

- **qos_simple.sh** — Single-interface, IP-based two-tier QoS (no MAC resolution). Same idea as the dual script but one subnet and explicit `HIGH_PRIORITY_IPS` list.
- **arp-spoofing.sh** — Minimal example: enable forwarding, ARP spoof one target IP, throttle it with tc.
- **arp-priority.sh** — Single-interface tc only: give one IP (e.g. your Kali) 70%, rest 30%.
- **arp-bridge.sh** — Create `br0` (eth0 + wlan0) so tc can be applied to a bridge (reference only).

## Caplets

The `caplets/` directory contains Bettercap caplets (e.g. for MITM, sniffing). See `caplets/README.md`. Use only on networks you are authorized to test.

## Legal / ethics

Use these scripts only on networks you own or have explicit permission to test. ARP spoofing and traffic interception may be illegal on networks you do not control.
