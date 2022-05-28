#!/bin/bash

DNS_HOSTNAME="representatives.nano.community"
PORT=7075

# Rate to throttle non half PRs
RATE=0.5kbps
CEIL=2kbps

# Interface to shape
IF=eth0

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

function update {
    # Flush old IPs
    $IPSET flush half-prs

    # Get IPs from DNS
    dig "$DNS_HOSTNAME" A +short | while read ip; do
        # Add IPs to IP set
        $IPSET add half-prs $ip
    done
}

function whitelist {
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

function install {
    # Create IP Set
    $IPSET create half-prs hash:ip # family inet6

    update
}

function shape {
    # create root qdisc
    $TC qdisc add dev $IF root handle 1:0 htb

    # create class to rate limit non half PR traffic
    $TC class add dev $IF parent 1: classid 1:1 htb rate $RATE ceil $CEIL
    $TC class add dev $IF parent 1:1 classid 1:10 htb rate $RATE ceil $CEIL
    $TC filter add dev $IF parent 1:0 prio 1 handle 2 fw classid 1:10

    # flush iptables mangle table
    $IPTABLES -F INPUT
    $IPTABLES -t mangle -F shaper-out
    $IPTABLES -t mangle -F shaper-in
    $IPTABLES -t mangle -F PREROUTING
    $IPTABLES -t mangle -F POSTROUTING
    $IPTABLES -t mangle -F INPUT
    $IPTABLES -t mangle -F OUTPUT

    # create iptables mangle table
    # $IPTABLES -t mangle -N shaper-in
    # $IPTABLES -t mangle -N shaper-out

    # $IPTABLES -t mangle -I PREROUTING -i $IF -j shaper-in
    # $IPTABLES -t mangle -I POSTROUTING -o $IF -j shaper-out

    # shape traffic not included in ipset
    # $IPTABLES -t mangle -A shaper-in -p tcp --dport $PORT -m set ! --match-set half-prs src -j MARK --set-mark 2
    # $IPTABLES -t mangle -A shaper-out -p tcp --dport $PORT -m set ! --match-set half-prs dst -j MARK --set-mark 2

    $IPTABLES -t mangle -A INPUT -p tcp --dport $PORT -m set ! --match-set half-prs src -j MARK --set-mark 2
    $IPTABLES -t mangle -A INPUT -p tcp --sport $PORT -m set ! --match-set half-prs src -j MARK --set-mark 2
    $IPTABLES -t mangle -A OUTPUT -p tcp --sport $PORT -m set ! --match-set half-prs dst -j MARK --set-mark 2
    $IPTABLES -t mangle -A OUTPUT -p tcp --dport $PORT -m set ! --match-set half-prs dst -j MARK --set-mark 2
}

function uninstall {
    # delete class to rate limit non half PR traffic
    $TC filter del dev $IF parent 1:0 prio 1 handle 2 fw classid 1:10
    $TC class del dev $IF parent 1:1 classid 1:10 htb rate $RATE ceil $CEIL
    $TC class del dev $IF parent 1: classid 1:1 htb rate $RATE ceil $CEIL

    # delete root qdisc
    $TC qdisc del dev $IF root handle 1:0 htb

    # flush iptables mangle table
    $IPTABLES -F INPUT
    $IPTABLES -F OUTPUT
    $IPTABLES -t mangle -F shaper-in
    $IPTABLES -t mangle -F shaper-out
    $IPTABLES -t mangle -F PREROUTING
    $IPTABLES -t mangle -F POSTROUTING
    $IPTABLES -t mangle -F INPUT
    $IPTABLES -t mangle -F OUTPUT

    # destroy ipset
    $IPSET destroy half-prs
}

case "${1:-x}" in
    install) install ;;
    update) update ;;
    shape) shape ;;
    whitelist) whitelist ;;
    uninstall) uninstall ;;
    *)
        echo  >&2 "usage:"
        echo >&2 "$0 install"
        echo >&2 "$0 uninstall"
        echo >&2 "$0 shape"
        echo >&2 "$0 whitelist"
        echo >&2 "$0 update"
        exit 1
        ;;
esac
