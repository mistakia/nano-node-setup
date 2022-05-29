# Installation

Install dependencies

```
apt update
apt install ipset iptables iproute2
```

Download script

```
wget https://raw.githubusercontent.com/mistakia/nano-node-setup/main/scripts/traffic-shaper-beta.sh -O traffic-shaper.sh
```
```
chmod +x ./traffic-shaper.sh
```

# Usage

To start traffic shaping.

```
./traffic-shaper.sh start
```

To stop traffic shaping and cleanup.

```
./traffic-shaper.sh stop
```

> Warning: running `destroy` or `clear_whitelist` will flush your `INPUT` and `OUTPUT` iptables chains. Shouldn't have to run these anyways.
