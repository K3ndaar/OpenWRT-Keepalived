#!/bin/sh
# Handles start and stop of synchronization daemon

ACTION=$1 # start | stop
PEER_IP=$2
LOG_FILE="keepalived_sync_config_trigger.log"

# Parameters
source /etc/keepalived/scripts/.env
# Utility functions
source /etc/keepalived/scripts/utils.sh

validate_params

if [ "$ACTION" != "start" ] && [ "$ACTION" != "stop" ]; then
    log_message "ERROR: Invalid action '$ACTION'. Usage: $0 {start|stop} <peer_ip>" error
    exit 1
fi

if [ -z "$PEER_IP" ]; then
    log_message "ERROR: No peer IP provided. Usage: $0 {start|stop} <peer_ip>" error
    exit 1
fi

SYNC_SCRIPT="/etc/keepalived/scripts/sync_config_daemon.sh"
PID_FILE="/var/run/sync_config_daemon.pid"

case "$ACTION" in
    "start")
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            log_message "Sync config daemon already running."
        else
            log_message "Starting sync config daemon targeting $PEER_IP..."
            start-stop-daemon -S -b -p "$PID_FILE" -m -x "$SYNC_SCRIPT" -- "$PEER_IP"
        fi
        ;;
    "stop")
        if [ -f "$PID_FILE" ]; then
            log_message "Stopping sync config daemon."
            start-stop-daemon -K -p "$PID_FILE"
            if [ $? -eq 0 ]; then
                log_message "Sync config daemon stopped successfully." debug
            else
                log_message "Failed to stop sync config daemon." error
            fi
            rm "$PID_FILE"
        else
            log_message "Sync config daemon not running (no PID file)."
        fi
        ;;
    *)
        log_message "Usage: $0 {start|stop} <peer_ip>"
        exit 1
        ;;
esac

exit 0
