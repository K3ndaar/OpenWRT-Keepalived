#!/bin/sh

log_message() {
    local L_MESSAGE_TEXT="$1"
    local L_LOG_LEVEL="${2:-notice}"
    local L_DATE=${DATE:-$(date +"%Y-%m-%d %H:%M:%S")}
    local L_DEBUG=${DEBUG:-0}

    if [ $L_LOG_LEVEL = "debug" ] && [ $L_DEBUG -ne 1 ]; then
        return 0
    fi

    if [ ! -z $LOG_DIR ] && [ ! -z $LOG_FILE ]; then
        echo "[$L_DATE] $L_MESSAGE_TEXT" >> "$LOG_DIR/$LOG_FILE"
    fi
    logger -t keepalived -p "user.$L_LOG_LEVEL" "$L_MESSAGE_TEXT"
}

validate_params() {
    if [ -z "$FIREWALL1_IP" ] || [ -z "$FIREWALL2_IP" ]; then
        log_message "ERROR: FIREWALL1_IP and FIREWALL2_IP must be set in .env file." error
        exit 1
    fi

    if [ -z "$FIREWALL_DOMAIN" ] || [ -z "$FIREWALL_DNS" ]; then
        log_message "ERROR: FIREWALL_DOMAIN and FIREWALL_DNS must be set in .env file." error
        exit 1
    fi

    if [ -z "$DEST_USER" ]; then
        log_message "ERROR: DEST_USER must be set in .env file." error
        exit 1
    fi

    if [ -z "$WIREGUARD_VPNS" ]; then
        log_message "ERROR: WIREGUARD_VPNS must be set in .env file." error
        exit 1
    fi
    if [ -z "$DHCP_INTERFACES" ]; then
        log_message "ERROR: DHCP_INTERFACES must be set in .env file." error
        exit 1
    fi
    if [ -z "$DHCP_LEASE_FILE" ]; then
        log_message "ERROR: DHCP_LEASE_FILE must be set in .env file." error
        exit 1
    fi
    if [ -z "$FILES_TO_MONITOR" ] || [ -z "$DIRS_TO_MONITOR" ]; then
        log_message "ERROR: FILES_TO_MONITOR and DIRS_TO_MONITOR must be set in .env file." error
        exit 1
    fi

    if [ -z "WAN_CHECK_IP" ]; then
        log_message "ERROR: WAN_CHECK_IP must be set in .env file." error
        exit 1
    fi

}
