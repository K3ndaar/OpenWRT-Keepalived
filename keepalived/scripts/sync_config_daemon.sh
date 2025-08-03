#!/bin/sh
# Daemon that monitors configuration files for changes and synchronizes them via rsync.
# It excludes files like 'network' and 'keepalived.conf' that have node-specific configurations.

PEER_IP=$1
LOG_FILE="keepalived_sync_config_daemon.log"

DEBUG=0

# Parameters
source /etc/keepalived/scripts/.env
# Utility functions
source /etc/keepalived/scripts/utils.sh

validate_params

if [ -z "$PEER_IP" ]; then
    log_message "ERROR: No peer IP provided. Exiting." error
    exit 1
fi

get_monitored_dir() {
    local changed_file=$1
    for dir in $DIRS_TO_MONITOR; do
        # Append a slash to the directory name to ensure we match
        # subdirectories correctly (e.g., /path/to/dir/file vs. /path/to/dir-other).
        if [ "${changed_file#${dir%/}/}" != "$changed_file" ]; then
            echo "${dir%/}/"
            return 0
        fi
    done
    return 1
}

# A function to clean up and exit gracefully.
cleanup() {
    log_message "Caught signal. Terminating inotifywait process and cleaning up..." debug
    # Kill the inotifywait process
    kill "$inotify_pid" 2>/dev/null
    # Remove the FIFO pipe
    rm -f "$FIFO_PIPE"
    exit 0
}

# --- Signal Handling ---
# We will use a temporary file to act as a pipe for inotifywait's output.
FIFO_PIPE="/tmp/inotify_fifo_$$"
mkfifo "$FIFO_PIPE"

# Trap SIGTERM (sent by start-stop-daemon -K) and SIGINT (Ctrl+C).
# This ensures a clean shutdown on receipt of these signals.
trap cleanup TERM INT

log_message "Starting monitorng config for synchronization to $PEER_IP..."
# Combine the lists of files to be monitored and synchronized
ALL_PATHS="$FILES_TO_MONITOR $DIRS_TO_MONITOR"
# Launch inotifywait in the background and redirect its output to our named pipe.
inotifywait -m -r -e close_write,create,delete,move --format '%w%f' $ALL_PATHS > "$FIFO_PIPE" &
inotify_pid=$!

while read -r changed_file; do
    log_message "Change detected: $event on $changed_file." debug

    # Use command substitution to get the top-level monitored directory from the function.
    # The 'if' statement is true if the function returns a non-empty string.
    if monitored_dir=$(get_monitored_dir "$changed_file"); then
        log_message "Change in a monitored directory ($monitored_dir). Syncing the entire directory..."
        rsync -avz --delete "${monitored_dir}" "$DEST_USER@$PEER_IP:${monitored_dir}"
        if [ $? -ne 0 ]; then
            log_message "ERROR: rsync --delete failed for $monitored_dir to $PEER_IP." error
        fi       
    else
        log_message "Change in a monitored file $changed_file. Syncing..."
        rsync -avz -R "${changed_file}/" "$DEST_USER@$PEER_IP:/"
        if [ $? -ne 0 ]; then
            log_message "ERROR: rsync failed for $changed_file to $PEER_IP." error
        fi       
    fi

    # Restart services if files related to them are changed.
    if [ "$changed_file" = "/etc/config/firewall" ]; then
        log_message "Firewall configuration changed. Reloading firewall on $DEST_USER@$PEER_IP."
        ssh -o BatchMode=yes "$DEST_USER@$PEER_IP" "uci commit firewall && /etc/init.d/firewall reload"
        if [ $? -ne 0 ]; then
            log_message "ERROR: Failed to reload firewall on $DEST_USER@$PEER_IP." error
        else
            log_message "Successfully reloaded firewall on $DEST_USER@$PEER_IP." debug
        fi
    elif [ "$changed_file" = "/etc/config/dhcp" ]; then
        log_message "DHCP configuration changed. Committing changes on $DEST_USER@$PEER_IP."
        ssh -o BatchMode=yes "$DEST_USER@$PEER_IP" "uci commit dhcp"
        if [ $? -ne 0 ]; then
            log_message "ERROR: Failed to commit dhcp changes on $DEST_USER@$PEER_IP." error
        else
            log_message "Successfully commit dhcp changes on $DEST_USER@$PEER_IP." debug
        fi
    fi
done < "$FIFO_PIPE"

wait $inotify_pid 2>/dev/null

log_message "Monitorng config for synchronization to $PEER_IP ended."
