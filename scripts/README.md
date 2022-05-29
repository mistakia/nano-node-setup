# Installation

Install dependencies

```
apt update
apt install ipset iptables iproute2
```

Download beta script

```
wget https://raw.githubusercontent.com/mistakia/nano-node-setup/main/scripts/traffic-shaper-beta.sh -O traffic-shaper.sh
```
Download mainnet/live script

```
wget https://raw.githubusercontent.com/mistakia/nano-node-setup/main/scripts/traffic-shaper.sh -O traffic-shaper.sh
```
```
chmod +x ./traffic-shaper.sh
```

# Config

Edit the `IF` variable in the file to match your network device name.
```
IF=eth0
```

# Usage

> Note: root permissiones are needed, depending on your setup you may need to run with `sudo`

To start traffic shaping.

```
./traffic-shaper.sh start
```

To stop traffic shaping and cleanup.

```
./traffic-shaper.sh stop
```

> Warning: running `destroy` or `clear_whitelist` will flush your `INPUT` and `OUTPUT` iptables chains. Shouldn't have to run these anyways.

# Troubleshooting

### Confirm outbound traffic shaping is happening
```
tc -s -d class show dev eth0
```
```
class htb 1:1 root rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 7
 Sent 24084 bytes 44 pkt (dropped 0, overlimits 9 requeues 0)
 backlog 0b 0p requeues 0
 lended: 0 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:10 parent 1:1 prio 0 quantum 200000 rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 0
 Sent 724 bytes 6 pkt (dropped 0, overlimits 0 requeues 0)
 backlog 0b 0p requeues 0
 lended: 6 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:20 parent 1:1 prio 0 quantum 200000 rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 0
 Sent 1210 bytes 7 pkt (dropped 0, overlimits 0 requeues 0)
 backlog 0b 0p requeues 0
 lended: 7 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:40 parent 1:1 prio 0 quantum 5000 rate 400Kbit ceil 400Kbit linklayer ethernet burst 1600b/1 mpu 0b cburst 1600b/1 mpu 0b level 0
 Sent 22150 bytes 31 pkt (dropped 0, overlimits 10 requeues 0)
 backlog 0b 0p requeues 0
 lended: 26 borrowed: 0 giants: 0
 tokens: 479375 ctokens: 479375
 ```

You should see packets sent in class `1:20` (high priority) and `1:40` (low priority)

### Confirm inbound traffic shaping is happening
```
tc -s -d class show dev ifb0
```
```
class htb 1:1 root rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 7
 Sent 539007 bytes 2581 pkt (dropped 0, overlimits 127 requeues 0)
 backlog 0b 0p requeues 0
 lended: 0 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:10 parent 1:1 prio 0 quantum 200000 rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 0
 Sent 56461 bytes 322 pkt (dropped 0, overlimits 0 requeues 0)
 backlog 0b 0p requeues 0
 lended: 322 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:30 parent 1:1 prio 0 quantum 200000 rate 8Gbit ceil 8Gbit linklayer ethernet burst 0b/1 mpu 0b cburst 0b/1 mpu 0b level 0
 Sent 88508 bytes 730 pkt (dropped 0, overlimits 0 requeues 0)
 backlog 0b 0p requeues 0
 lended: 730 borrowed: 0 giants: 0
 tokens: 13 ctokens: 13

class htb 1:50 parent 1:1 prio 0 quantum 5000 rate 400Kbit ceil 400Kbit linklayer ethernet burst 1600b/1 mpu 0b cburst 1600b/1 mpu 0b level 0
 Sent 394038 bytes 1529 pkt (dropped 0, overlimits 41 requeues 0)
 backlog 0b 0p requeues 0
 lended: 1529 borrowed: 0 giants: 0
 tokens: 339375 ctokens: 339375
```
You should see packets sent in class `1:30` (high priority) and `1:50` (low priority)
