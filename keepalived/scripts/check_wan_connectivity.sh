#!/bin/sh
# Checks connectivity to the telco router

LOG_FILE="keepalived_check_wan_connectivity.log"
DEBUG=0

# Parameters
source /etc/keepalived/scripts/.env
# Utility functions
source /etc/keepalived/scripts/utils.sh

validate_params

# Esegui 3 ping con timeout 1 secondo
ping -c 3 -W 1 "$WAN_CHECK_IP" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    log_message "WARNING: WAN connectivity to $WAN_CHECK_IP FAILED." error
    exit -1
fi
exit 0
