#!/bin/bash

DNS_HOSTNAME="beta.nano.community"
PORT=54000

# Bandwidth to allocate to low priority nodes
LOW_PRIORITY_MIN=1mbps
LOW_PRIORITY_MAX=1mbps

# Bandwidth to allocate to high priority nodes
HIGH_PRIORITY_MAX=1gbps

# Interface to shape
IF=eth0

# Virtual interface to handle incoming shaping
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

function clear_iptables {
    $IPTABLES -F PREROUTING
    $IPTABLES -F POSTROUTING
}

function clear_tc {
    # Clear queuing disciplines (qdisc) on the interfaces
    $TC qdisc del dev $IF root > /dev/null 2>&1
    $TC qdisc del dev $IF ingress > /dev/null 2>&1
    $TC qdisc del dev $IF_INGRESS root > /dev/null 2>&1
}

function create_ipset {
    # Create IP Set
    $IPSET create half-prs hash:ip --exist # family inet6

    update_ipset
}

function update_ipset {
    # Flush old IPs
    $IPSET flush half-prs

    # Get IPs from DNS
    dig "$DNS_HOSTNAME" A +short | while read ip; do
        # Add ip to ipset
        $IPSET add half-prs $ip
    done
}

function whitelist {
    create_ipset

    clear_iptables

    # Allow connections from ipset
    $IPTABLES -I PREROUTING -p tcp --dport $PORT -m set --match-set half-prs src -j ACCEPT
    $IPTABLES -I PREROUTING -p tcp --sport $PORT -m set --match-set half-prs src -j ACCEPT

    # Allow connection to ipset
    $IPTABLES -I POSTROUTING -p tcp --dport $PORT -m set --match-set half-prs dst -j ACCEPT
    $IPTABLES -I POSTROUTING -p tcp --sport $PORT -m set --match-set half-prs dst -j ACCEPT

    # Deny other incoming connections
    # $IPTABLES -A PREROUTING -p tcp --dport $PORT -m limit --limit 10/s -j ACCEPT
    # $IPTABLES -A PREROTUING -p tcp --sport $PORT -m limit --limit 10/s -j ACCEPT
    $IPTABLES -A PREROUTING -p tcp --dport $PORT -j DROP
    $IPTABLES -A PREROUTING -p tcp --sport $PORT -j DROP

    # Deny other outgoing conenctions
    # $IPTABLES -A POSTROUTING -p tcp --dport $PORT -m limit --limit 10/s -j ACCEPT
    # $IPTABLES -A POSTROUTING -p tcp --sport $PORT -m limit --limit 10/s -j ACCEPT
    $IPTABLES -A POSTROUTING -p tcp --dport $PORT -j DROP
    $IPTABLES -A POSTROUTING -p tcp --sport $PORT -j DROP
}

function tc_ingress {
    # if the interace is not up bad things happen
    # ifconfig $IF_INGRESS up
    modprobe ifb numifbs=1
    ip link set dev $IF_INGRESS up

    # create ingress on external interface
    $TC qdisc add dev $IF handle ffff: ingress

    # redirect ingress packet to ingress interface
    $TC filter add dev $IF parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev $IF_INGRESS

    # create root qdisc for ingress on the IFB device, default use general high priority class
    $TC qdisc add dev $IF_INGRESS root handle 1:0 htb default 10

    # create parent class for ingress
    $TC class add dev $IF_INGRESS parent 1: classid 1:1 htb rate $HIGH_PRIORITY_MAX

    # create class for general high priority ingress traffic
    $TC class add dev $IF_INGRESS parent 1:1 classid 1:10 htb rate $HIGH_PRIORITY_MAX
    # create class for high priority half PR ingress traffic
    $TC class add dev $IF_INGRESS parent 1:1 classid 1:30 htb rate $HIGH_PRIORITY_MAX
    # create class for low priority nano network ingress traffic
    $TC class add dev $IF_INGRESS parent 1:1 classid 1:50 htb rate $LOW_PRIORITY_MIN ceil $LOW_PRIORITY_MAX

    # filter high priority packets matching dns ips and send to classid 1:30
    dig "$DNS_HOSTNAME" A +short | while read ip; do
        $TC filter add dev $IF_INGRESS parent 1:0 protocol ip prio 1 u32 match ip src $ip classid 1:30
    done

    # filter low priority packets matching nano network port send to classid 1:50
    $TC filter add dev $IF_INGRESS parent 1:0 protocol ip prio 2 u32 match ip dport $PORT 0xffff classid 1:50
    $TC filter add dev $IF_INGRESS parent 1:0 protocol ip prio 2 u32 match ip sport $PORT 0xffff classid 1:50
}

function tc_egress {
    # create root qdisc for egress, default use general high priority class 10
    $TC qdisc add dev $IF root handle 1:0 htb default 10

    # create parent class for egress
    $TC class add dev $IF parent 1: classid 1:1 htb rate $HIGH_PRIORITY_MAX

    # create class for high priority general egress traffic
    $TC class add dev $IF parent 1:1 classid 1:10 htb rate $HIGH_PRIORITY_MAX
    # create class for high priority half PR egress traffic
    $TC class add dev $IF parent 1:1 classid 1:20 htb rate $HIGH_PRIORITY_MAX
    # create class for low priority nano network egress traffic
    $TC class add dev $IF parent 1:1 classid 1:40 htb rate $LOW_PRIORITY_MIN ceil $LOW_PRIORITY_MAX

    # filter high priority packets matching dns ips and send to classid 1:30
    dig "$DNS_HOSTNAME" A +short | while read ip; do
        $TC filter add dev $IF parent 1:0 protocol ip prio 1 u32 match ip dst $ip classid 1:20
    done

    # filter packets matching nano network port and send to classid 1:20
    $TC filter add dev $IF parent 1:0 protocol ip prio 2 u32 match ip dport $PORT 0xffff classid 1:40
    $TC filter add dev $IF parent 1:0 protocol ip prio 2 u32 match ip sport $PORT 0xffff classid 1:40
}

function shape {
    clear_tc

    tc_ingress
    tc_egress
}

function destroy {
    clear_iptables
    clear_tc

    # destroy ipset
    $IPSET destroy half-prs > /dev/null 2>&1
}

case "${1:-x}" in
    start) shape ;;
    stop) clear_tc ;;
    whitelist) whitelist ;;
    clear_whitelist) clear_iptables ;;
    update) update_ipset ;;
    destroy) destroy ;;
    *)
        echo  >&2 "usage:"
        echo >&2 "$0 start"
        echo >&2 "$0 stop"
        echo >&2 "$0 whitelist"
        echo >&2 "$0 clear_whitelist"
        echo >&2 "$0 update"
        echo >&2 "$0 destroy"
        exit 1
        ;;
esac
