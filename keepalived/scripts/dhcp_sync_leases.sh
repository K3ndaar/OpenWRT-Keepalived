#!/bin/sh

LOG_FILE="keepalived_dhcp_sync_leases.log"
DATE=$(date +"%Y-%m-%d %H:%M:%S")

DEBUG=0


# Parameters
source /etc/keepalived/scripts/.env
# Utility functions
source /etc/keepalived/scripts/utils.sh

validate_params

ACTION=$1  # can be arp-add, arp-del, add, old, del
MAC_ADDRESS=$2
IP_ADDRESS=$3

### Logging activities with details
log_message "DNSMASQ DHCP Event: { \"action\": \"$ACTION\"; \"mac_address\": \"$MAC_ADDRESS\"; \"ip\": \"$IP\"; \"supplied_hostname\": \"${DNSMASQ_SUPPLIED_HOSTNAME}\"}" debug


#### LEASE SYNCHRONIZATION

# Action validation: avoid running commands if not a real lease change
case "$ACTION" in
    "add"|"old"|"del")
        # managed actions
        log_message "Valid action discovered: $ACTION" debug
        ;;
    "arp-add"|"arp-del")
        # ignored actions
        log_message "Ignored action discovered: $ACTION" debug
        exit 0
        ;; 
    *)
        # anything else
        log_message "Unsupported action $ACTION" warning
        exit 1
        ;;
esac


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

ROLE=$(cat /tmp/keepalived_status)

if [ "$ROLE" == "MASTER" ]; then

    # Check if the DHCP lease file exists before attempting to sync.
    if [ -f "$DHCP_LEASE_FILE" ]; then
        log_message "Syncing DHCP leases to $PEER_IP..."
    
        # Use rsync to copy the lease file from the master's /tmp to the backup's /tmp.
        rsync -avz "$DHCP_LEASE_FILE" "$DEST_USER@$PEER_IP:/tmp/" > /dev/null 2>&1 
    
        if [ $? -eq 0 ]; then
            log_message "DHCP leases synced successfully. Reloading dnsmasq on peer."
        
            # After a successful sync, SSH into the backup and reload dnsmasq.
            # This ensures the backup loads the new lease file and is ready for a failover.
            # This command is safe because dnsmasq's DHCP on the backup is in a "stopped" state,
            # but the reload command will handle it gracefully.

            ssh "$DEST_USER@$PEER_IP" "/etc/init.d/dnsmasq reload"
        else
            log_message "ERROR: Failed to sync DHCP leases to $PEER_IP." error
        fi
    else
        log_message "WARNING: DHCP lease file $DHCP_LEASE_FILE not found on master." warning
    fi
else
    log_message "Not syncing DHCP leases as our role is $ROLE" debug
fi
