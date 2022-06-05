# Description

This traffic shaper uses DNS records and [TC](https://man7.org/linux/man-pages/man8/tc.8.html) to shape traffic to your node. The traffic shaper will create three classes:

##### high priorty voting nodes
- effectively uncapped bandwidth (dedfault 1gbps)
- dns records via `representatives.nano.community`
- reps with at least half the voting weight of a principal representative (~50k)

##### high priorty non-voting nodes
- bandwidth collectively capped (default 50 mbps)
- dns records via `nodes.nano.community`
- nodes that have been online for more than ~14 days in the last 90 days

##### low priority nodes
- bandwidth collectively capped (default 2mbps)
- all nodes using port `7075` and not found in dns records

# Installation

Install dependencies

```bash
apt update
apt install ipset iptables iproute2
```

Download beta script

```bash
wget https://raw.githubusercontent.com/mistakia/nano-node-setup/main/scripts/traffic-shaper-beta.sh -O traffic-shaper.sh
```

Download mainnet/live script

```bash
wget https://raw.githubusercontent.com/mistakia/nano-node-setup/main/scripts/traffic-shaper.sh -O traffic-shaper.sh
```
```bash
chmod +x ./traffic-shaper.sh
```

# Config

Edit the `IF` variable in the file to match your network device name.
```
IF=eth0
```
Edit bandwidth allocation
```bash
# Bandwidth to allocate to low priority nodes
LOW_PRIORITY_MIN=2mbps
LOW_PRIORITY_MAX=2mbps

# Bandwidth to allocate to high priority non-voting nodes
HIGH_PRIORITY_NODES_MIN=10mbps
HIGH_PRIORITY_NODES_MAX=50mbps

# Bandwidth to allocate to high priority voting nodes
HIGH_PRIORITY_REPS_MAX=1gbps
```

# Usage

> Note: root permissiones are needed, depending on your setup you may need to run with `sudo`

To start traffic shaping.

```bash
./traffic-shaper.sh start
```

To stop traffic shaping and cleanup.

```bash
./traffic-shaper.sh stop
```

> Warning: running `destroy` or `clear_whitelist` will flush your `PREROUTING` and `POSTROUTING` iptables chains. Shouldn't have to run these anyways.

# Troubleshooting

### Confirm outbound traffic shaping is happening
```bash
tc -s -d class show dev eth0 # use interface name set in config
```
```
class htb 1:1 root rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 7
 Sent 7973671 bytes 27549 pkt (dropped 0, overlimits 905 requeues 0)
 backlog 0b 0p requeues 0
 lended: 0 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:10 parent 1:1 prio 0 quantum 200000 rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 0
 Sent 403495 bytes 1106 pkt (dropped 0, overlimits 59 requeues 0)
 backlog 0b 0p requeues 0
 lended: 1106 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:20 parent 1:1 prio 0 quantum 200000 rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 0
 Sent 2553772 bytes 7798 pkt (dropped 0, overlimits 288 requeues 0)
 backlog 0b 0p requeues 0
 lended: 7798 borrowed: 0 giants: 0
 tokens: 10 ctokens: 10

class htb 1:40 parent 1:1 prio 0 quantum 200000 rate 400Mbit ceil 400Mbit linklayer ethernet burst 1600b/1 mpu 0b cburst 1600b/1 mpu 0b level 0
 Sent 3248977 bytes 12738 pkt (dropped 0, overlimits 83 requeues 0)
 backlog 0b 0p requeues 0
 lended: 12672 borrowed: 0 giants: 0
 tokens: 479 ctokens: 479

class htb 1:60 parent 1:1 prio 0 quantum 200000 rate 16Mbit ceil 16Mbit linklayer ethernet burst 1600b/1 mpu 0b cburst 1600b/1 mpu 0b level 0
 Sent 1767427 bytes 5907 pkt (dropped 0, overlimits 210 requeues 0)
 backlog 0b 0p requeues 0
 lended: 5830 borrowed: 0 giants: 0
 tokens: 11677 ctokens: 11677
```

You should see packets sent in class `1:20` (high priority reps), `1:40` (high priority nodes), and `1:60` (low priority nodes)

### Confirm inbound traffic shaping is happening
```bash
tc -s -d class show dev ifb0
```
```
class htb 1:1 root rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 7
 Sent 38732701 bytes 187660 pkt (dropped 0, overlimits 4672 requeues 0)
 backlog 0b 0p requeues 0
 lended: 0 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:10 parent 1:1 prio 0 quantum 200000 rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 0
 Sent 207974 bytes 1046 pkt (dropped 0, overlimits 24 requeues 0)
 backlog 0b 0p requeues 0
 lended: 1046 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:30 parent 1:1 prio 0 quantum 200000 rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 0
 Sent 8796592 bytes 55096 pkt (dropped 0, overlimits 1472 requeues 0)
 backlog 0b 0p requeues 0
 lended: 55096 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:50 parent 1:1 prio 0 quantum 200000 rate 400Mbit ceil 400Mbit linklayer ethernet burst 1600b/1 mpu 0b cburst 1600b/1 mpu 0b level 0
 Sent 21008094 bytes 90066 pkt (dropped 0, overlimits 28 requeues 0)
 backlog 0b 0p requeues 0
 lended: 90066 borrowed: 0 giants: 0
 tokens: 479 ctokens: 479

class htb 1:70 parent 1:1 prio 0 quantum 200000 rate 16Mbit ceil 16Mbit linklayer ethernet burst 1600b/1 mpu 0b cburst 1600b/1 mpu 0b level 0
 Sent 8720041 bytes 41452 pkt (dropped 0, overlimits 70 requeues 0)
 backlog 0b 0p requeues 0
 lended: 41452 borrowed: 0 giants: 0
 tokens: 11529 ctokens: 11529
```
You should see packets sent in class `1:30` (high priority reps), `1:50` (high priority nodes), and `1:70` (low priority nodes)
