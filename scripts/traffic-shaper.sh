#!/bin/bash

DNS_HOSTNAME="representatives.nano.community"
PORT=7075

# Rate to throttle non half PRs
RATE=0.5kbps
CEIL=2kbps
MAX=1gbps

# Interface to shape
IF=eth0
IF_INGRESS=ifb0

# Specify where iptables is located
IPTABLES=/sbin/iptables
IPTABLES_SAVE=/sbin/iptables-save

# Specify where ipset is located
IPSET=/sbin/ipset

# Specify where tc is located
TC=/sbin/tc

# Save current iptables running configuration in case we want to revert back
# To restore using our example we would run "/sbin/iptables-restore < /usr/local/etc/iptables.last"
$IPTABLES_SAVE > /usr/local/etc/iptables.last

function update_ipset {
    # Flush old IPs
    $IPSET flush half-prs

    # Get IPs from DNS
    dig "$DNS_HOSTNAME" A +short | while read ip; do
        # Add IPs to IP set
        $IPSET add half-prs $ip
    done
}

function whitelist {
    install_ipset
    clear_iptables

    # Allow connections from IP set
    $IPTABLES -I INPUT -p tcp --dport $PORT -m set --match-set half-prs src -j ACCEPT
    $IPTABLES -I INPUT -p tcp --sport $PORT -m set --match-set half-prs src -j ACCEPT

    # Allow connection to IP set
    $IPTABLES -I OUTPUT -p tcp --dport $PORT -m set --match-set half-prs dst -j ACCEPT
    $IPTABLES -I OUTPUT -p tcp --sport $PORT -m set --match-set half-prs dst -j ACCEPT

    # Deny other incoming connections
    $IPTABLES -A INPUT -p tcp --dport $PORT -m limit --limit 10/s -j ACCEPT
    $IPTABLES -A INPUT -p tcp --sport $PORT -m limit --limit 10/s -j ACCEPT
    $IPTABLES -A INPUT -p tcp --dport $PORT -j DROP
    $IPTABLES -A INPUT -p tcp --sport $PORT -j DROP

    # Deny other outgoing conenctions
    $IPTABLES -A OUTPUT -p tcp --dport $PORT -m limit --limit 10/s -j ACCEPT
    $IPTABLES -A OUTPUT -p tcp --sport $PORT -m limit --limit 10/s -j ACCEPT
    $IPTABLES -A OUTPUT -p tcp --dport $PORT -j DROP
    $IPTABLES -A OUTPUT -p tcp --sport $PORT -j DROP
}

function install_ipset {
    # Create IP Set
    $IPSET create half-prs hash:ip --exist # family inet6

    update_ipset
}

function clear_tc {
    # Clear old queuing disciplines (qdisc) on the interfaces
    $TC qdisc del dev $IF root >/dev/null 2>&1
    $TC qdisc del dev $IF ingress >/dev/null 2>&1
    $TC qdisc del dev $IF_INGRESS root >/dev/null 2>&1
    # $TC qdisc del dev $IF_INGRESS ingress
}

function clear_iptables {
    # flush iptables mangle table
    $IPTABLES -F INPUT
    $IPTABLES -F OUTPUT
    $IPTABLES -t mangle -F shaper-out
    $IPTABLES -t mangle -F shaper-in
    $IPTABLES -t mangle -F PREROUTING
    $IPTABLES -t mangle -F POSTROUTING
    $IPTABLES -t mangle -F INPUT
    $IPTABLES -t mangle -F OUTPUT
}

function tc_ingress {
    # if the interace is not up bad things happen
    # ifconfig $IF_INGRESS up
    modprobe ifb numifbs=1
    ip link set dev $IF_INGRESS up

    # create ingress on external interface
    $TC qdisc add dev $IF handle ffff: ingress

    # filter ingress packet to ingress interface
    $TC filter add dev $IF parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev $IF_INGRESS

    # create root qdisc for ingress on the IFB device
    $TC qdisc add dev $IF_INGRESS root handle 1:0 htb default 10

    # create parent class for ingress
    $TC class add dev $IF_INGRESS parent 1: classid 1:1 htb rate $MAX

    # create class for default high priority ingress traffic
    $TC class add dev $IF_INGRESS parent 1:1 classid 1:10 htb rate $MAX
    # create class for high priority half PR ingress traffic
    $TC class add dev $IF_INGRESS parent 1:1 classid 1:30 htb rate $MAX
    # create class for low priority ingress traffic
    $TC class add dev $IF_INGRESS parent 1:1 classid 1:50 htb rate $RATE ceil $CEIL

    # filter high priority packets matching dns ips and send to classid 1:30
    dig "$DNS_HOSTNAME" A +short | while read ip; do
        $TC filter add dev $IF_INGRESS parent 1:0 protocol ip prio 1 u32 match ip src $ip classid 1:30
    done

    # filter low priority packets matching port send to classid 1:50
    $TC filter add dev $IF_INGRESS parent 1:0 protocol ip prio 2 u32 match ip dport $PORT 0xffff classid 1:50
    $TC filter add dev $IF_INGRESS parent 1:0 protocol ip prio 2 u32 match ip sport $PORT 0xffff classid 1:50
}

function tc_egress {
    # create root qdisc for egress, default use low priority class 20
    $TC qdisc add dev $IF root handle 1:0 htb default 10

    # create parent class for egress
    $TC class add dev $IF parent 1: classid 1:1 htb rate $MAX

    # create class for high priority half PR traffic
    $TC class add dev $IF parent 1:1 classid 1:10 htb rate $MAX
    # create class for high priority half PR traffic
    $TC class add dev $IF parent 1:1 classid 1:20 htb rate $MAX
    # create class for low priority egress traffic
    $TC class add dev $IF parent 1:1 classid 1:40 htb rate $RATE ceil $CEIL

    # filter packets marked with handle 2 and send to classid 1:20
    $TC filter add dev $IF parent 1:0 prio 1 handle 2 fw classid 1:20

    # filter packets matching port and send to classid 1:20
    $TC filter add dev $IF parent 1:0 protocol ip prio 2 u32 match ip dport $PORT 0xffff classid 1:40
    $TC filter add dev $IF parent 1:0 protocol ip prio 2 u32 match ip sport $PORT 0xffff classid 1:40
    # $TC filter add dev $IF parent 1:0 prio 2 handle 4 fw classid 1:40

    # mark low priority traffic to a half-pr with handle 4 for deprioritization
    # $IPTABLES -t mangle -A OUTPUT -p tcp --dport $PORT -j MARK --set-mark 4
    # $IPTABLES -t mangle -A OUTPUT -p tcp --sport $PORT -j MARK --set-mark 4

    # mark high priority traffic to a half-pr with handle 2 for prioritization
    $IPTABLES -t mangle -A OUTPUT -p tcp --sport $PORT -m set --match-set half-prs src -j MARK --set-mark 2
    $IPTABLES -t mangle -A OUTPUT -p tcp --sport $PORT -m set --match-set half-prs dst -j MARK --set-mark 2
    $IPTABLES -t mangle -A OUTPUT -p tcp --dport $PORT -m set --match-set half-prs src -j MARK --set-mark 2
    $IPTABLES -t mangle -A OUTPUT -p tcp --dport $PORT -m set --match-set half-prs dst -j MARK --set-mark 2
}

function shape {
    install_ipset

    clear_tc
    clear_iptables

    tc_ingress
    tc_egress
}

function uninstall {
    clear_iptables
    clear_tc

    # destroy ipset
    $IPSET destroy half-prs >/dev/null 2>&1
}

case "${1:-x}" in
    whitelist) whitelist ;;
    update) update_ipset ;;
    shape) shape ;;
    shape_ingress) tc_ingress ;;
    shape_egress) tc_egress ;;
    uninstall) uninstall ;;
    *)
        echo  >&2 "usage:"
        echo >&2 "$0 whitelist"
        echo >&2 "$0 update"
        echo >&2 "$0 shape"
        echo >&2 "$0 uninstall"
        exit 1
        ;;
esac
