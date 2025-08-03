#!/bin/sh
# Script invoked by Keepalived vrrp_sync_group at stae change

ROLE=$1  # can be MASTER, BACKUP, FAULT
LOG_FILE="keepalived_global_state_change.log"
DEBUG=0

# Parameters
source /etc/keepalived/scripts/.env
# Utility functions
source /etc/keepalived/scripts/utils.sh

validate_params

if [ "$ROLE" != "MASTER" ] && [ "$ROLE" != "BACKUP" ] && [ "$ROLE" != "FAULT" ]; then
    log_message "ERROR: Invalid role '$ROLE'. Env var ROLE must be set outside" error
    exit 1
fi

CURRENT_IP=$(uci get network.lan.ipaddr)
PEER_IP=""
if [ "$CURRENT_IP" = "$FIREWALL1_IP" ]; then
    PEER_IP="$FIREWALL2_IP"
elif [ "$CURRENT_IP" = "$FIREWALL2_IP" ]; then
    PEER_IP="$FIREWALL1_IP"
else
    log_message "ERROR: Unknown current IP $CURRENT_IP. Cannot determine peer." error
    exit 1
fi

log_message "Keepalived group state changed to: $ROLE" debug

case $ROLE in
    "MASTER")
        log_message "Becoming MASTER. Activating services and starting sync."

        # 1. Wireguard VPN management
        log_message "Enabling and starting WireGuard interfaces..."
        for VPN in $WIREGUARD_VPNS; do
            log_message "Enabling WireGuard interface: $VPN" debug
            uci set network.$VPN.disabled='0'
        done
        uci commit network
        for VPN in $WIREGUARD_VPNS; do
            log_message "Starting WireGuard interface: $VPN" debug
            ifup $VPN
        done

        # 2. Dnsmasq management
        log_message "Enabling and starting Dnsmasq (DHCP/DNS)."
        for INTERFACE in $DHCP_INTERFACES; do
            log_message "Enabling DHCP for interface: $INTERFACE" debug
            uci set dhcp.$INTERFACE.ignore='0'
        done
        uci commit dhcp
        /etc/init.d/dnsmasq enable
        /etc/init.d/dnsmasq start

        # 3. Start config syncrhonizatin (only on MASTER)
        log_message "Starting config synchronization daemon..."
        /etc/keepalived/scripts/sync_config_daemon_trigger.sh start "$PEER_IP"
        echo "$ROLE" > /tmp/keepalived_status
        ;;

    "BACKUP"|"FAULT")
        if [ "$ROLE" = "BACKUP" ]; then
            log_message "Becoming BACKUP. Deactivating services and stopping sync."
        else
            log_message "Entering FAULT state. Deactivating services and stopping sync."
        fi

        # 1. Wireguard VPN management
        log_message "Disabling and stopping WireGuard interfaces..."
        for VPN in $WIREGUARD_VPNS; do
            log_message "Enabling WireGuard interface: $VPN" debug
            uci set network.$VPN.disabled='1'
        done
        uci commit network
        for VPN in $WIREGUARD_VPNS; do
            log_message "Starting WireGuard interface: $VPN" debug
            ifdown $VPN
        done

        # 2. Dnsmasq management
        log_message "Disabling and stopping Dnsmasq (DHCP/DNS)."
        for INTERFACE in $DHCP_INTERFACES; do
            log_message "Disabling DHCP for interface: $INTERFACE" debug
            uci set dhcp.$INTERFACE.ignore='1'
        done
        uci commit dhcp
        /etc/init.d/dnsmasq enable
        /etc/init.d/dnsmasq start


        # Rebuild resolv.conf
        log_message "Rebuilding resolv.conf with domain and nameserver." debug
        echo "search ${FIREWALL_DOMAIN}" > /tmp/resolv.conf.d/resolv.conf.auto
        echo "nameserver ${FIREWALL_DNS}" >> /tmp/resolv.conf.d/resolv.conf.auto
        ln -sf /tmp/resolv.conf.d/resolv.conf.auto /etc/resolv.conf

        # 3. Stop config synchronization (only on BACKUP)
        log_message "Stopping config synchronization daemon..."
        /etc/keepalived/scripts/sync_config_daemon_trigger.sh stop "$PEER_IP"
        echo "$ROLE" > /tmp/keepalived_status
        ;;

    *)
        log_message "Unknown state: $ROLE."
        echo "" > /tmp/keepalived_status
        ;;
esac

exit 0
