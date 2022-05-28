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

    # Allow connections from IP set
    $IPTABLES -I INPUT -p tcp --dport $PORT -m set --match-set half-prs src -j ACCEPT

    # Allow connection to IP set
    $IPTABLES -I OUTPUT -p tcp --dport $PORT -m set --match-set half-prs dst -j ACCEPT

    # Deny other incoming connections
    $IPTABLES -A INPUT -p tcp --dport $PORT -j REJECT
    $IPTABLES -A INPUT -p tcp --sport $PORT -j REJECT

    # Deny other outgoing conenctions
    $IPTABLES -A OUTPUT -p tcp --dport $PORT -j REJECT
    $IPTABLES -A OUTPUT -p tcp --sport $PORT -j REJECT
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
    $TC qdisc add dev $IF_INGRESS root handle 1:0 htb

    # create parent class for egress
    $TC class add dev $IF_INGRESS parent 1: classid 1:1 htb rate $MAX

    # ceate class to rate limit non half PR ingress traffic
    $TC class add dev $IF_INGRESS parent 1:1 classid 1:10 htb rate $RATE ceil $CEIL

    # filter packets marked with handle <x> and send to classid
    $TC filter add dev $IF_INGRESS parent 1:0 prio 1 handle 4 fw classid 1:10

    # limit incoming traffic to and from port 7075 but not when its to a half-pr, mark traffic with handle <x>
    $IPTABLES -t mangle -A INPUT -i $IF_INGRESS -p tcp --dport $PORT -m set ! --match-set half-prs src -j MARK --set-mark 4
    $IPTABLES -t mangle -A INPUT -i $IF_INGRESS -p tcp --sport $PORT -m set ! --match-set half-prs src -j MARK --set-mark 4
}

function tc_egress {
    # create root qdisc for egress
    $TC qdisc add dev $IF root handle 1:0 htb

    # create parent class for egress
    $TC class add dev $IF parent 1: classid 1:1 htb rate $MAX

    # create class to rate limit non half PR egress traffic
    $TC class add dev $IF parent 1:1 classid 1:10 htb rate $RATE ceil $CEIL

    # filter packets marked with handle <x> and send to classid
    $TC filter add dev $IF parent 1:0 prio 1 handle 2 fw classid 1:10

    # limit outgoing traffic to and from port 7075 but not when its to a half-pr, mark traffic with handle <x>
    $IPTABLES -t mangle -A OUTPUT -p tcp --sport $PORT -m set ! --match-set half-prs dst -j MARK --set-mark 2
    $IPTABLES -t mangle -A OUTPUT -p tcp --dport $PORT -m set ! --match-set half-prs dst -j MARK --set-mark 2
}

function shape {
    install_ipset

    clear_tc
    clear_iptables

    tc_ingress
    tc_egress

    # create iptables mangle table
    # $IPTABLES -t mangle -N shaper-in
    # $IPTABLES -t mangle -N shaper-out

    # $IPTABLES -t mangle -I PREROUTING -i $IF -j shaper-in
    # $IPTABLES -t mangle -I POSTROUTING -o $IF -j shaper-out

    # shape traffic not included in ipset
    # $IPTABLES -t mangle -A shaper-in -p tcp --dport $PORT -m set ! --match-set half-prs src -j MARK --set-mark 2
    # $IPTABLES -t mangle -A shaper-out -p tcp --dport $PORT -m set ! --match-set half-prs dst -j MARK --set-mark 2

}

function uninstall {
    clear_iptables
    clear_tc

    # destroy ipset
    $IPSET destroy half-prs
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
