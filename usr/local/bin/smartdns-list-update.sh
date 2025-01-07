#!/bin/sh
#
# Filename: smartdns-list-update.sh
# Author: Cao Lei <caolei@mail.com>
# Version:  \  Date:
#   1.0.0   -    2025/01/04
#   1.0.1   -    2025/01/07
# Description: This script is used to download the latest domain lists for SmartDNS.
# Usage: Run this script: `chmod +x smartdns-list-update.sh && ./smartdns-list-update.sh` (root privileges may be required depending on the output directory and usage in crontab)
# Note: Ensure that you understand every command's behaviour. Be aware that processing extremely large files might lead to memory issues.
#
# For crontab(root): 0 2 * * 0 /bin/sh /path/to/your/script/smartdns-list-update.sh >/dev/null 2>&1
#
# # !!! Necessary services or software: 'sh', 'curl', 'awk', 'systemd or openrc' (for service management if applicable)
#

# Function switch: Rotate logs
rotatelogs="true"

# Script-level Variables
log_dir="/var/log/smartdns"                # Directory for storing logs
log_file="${log_dir}/$(basename "$0").log" # Log file path
list_dir="/var/lib/smartdns"               # Directory for storing domain lists

# Use a space-separated string to simulate an array
domain_urls="https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/china-list.txt \
             https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/proxy-list.txt \
             https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/openai.json"

domain_lists="$list_dir/domestic-domain.list \
              $list_dir/oversea-domain.list \
              $list_dir/openai-domain.list"

# Function: Generate session ID for logging
generate_session_id() {
    echo "$(date +%Y%m%d%H%M%S)$RANDOM"
}

# Function: Log messages in JSON format
log() {
    log_level="$1"
    message="$2"
    command="$3"
    line_number="$4"
    session_id=$(generate_session_id)

    printf '{"timestamp":"%s","log_level":"%s","message":"%s","host_name":"%s","user_name":"%s",' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$log_level" "$message" "$(hostname)" "$USER" >>"$log_file"
    printf '"logger_name":"%s","command":"%s","line":"%s","session_id":"%s"}\n' \
        "$(basename "$0")" "$command" "$line_number" "$session_id" >>"$log_file"
}

# Function: Check required directories
check_log_dir() {
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
        log "INFO" "Created log directory: $log_dir" "check_log_dir" "$LINENO"
    fi
}

# Function: Rotate log files when they exceed size limit
rotate_logs() {
    if [ ! -f "$log_file" ]; then
        log "WARNING" "Log file does not exist: $log_file" "rotate_logs" "$LINENO"
        return 0
    fi

    if [ ! -w "$log_file" ]; then
        log "ERROR" "No write permission for log file: $log_file" "rotate_logs" "$LINENO"
        return 1
    fi

    current_size=$(wc -c <"$log_file")
    max_size="$((1 * 1024 * 1024))" # 1MB max size

    if [ "$current_size" -lt "$max_size" ]; then
        return
    fi

    log "INFO" "Rotate logs" "tar" "$LINENO"

    if tar -czf "${log_file}_$(date +%Y%m%d-%H%M%S).tar.gz" "$log_file" >/dev/null 2>&1; then
        : >"$log_file"
        log "INFO" "Rotate log completed" "tar" "$LINENO"
    else
        log "ERROR" "Rotate log failed" "tar" "$LINENO"
        return 1
    fi

    log_dir="$(dirname "$log_file")"
    log_base="$(basename "$log_file")"
    file_count="$(find "$log_dir" -maxdepth 1 -name "${log_base}*tar.gz" | wc -l)"
    max_num="5" # Keep maximum 5 rotated logs

    if [ "$file_count" -gt "$max_num" ]; then
        find "$log_dir" -maxdepth 1 -name "${log_base}*tar.gz" -type f -exec ls -1t {} + | \
            tail -n +$((max_num + 1)) | xargs rm -f --
        log "INFO" "Rotate log completed, cleaned $((file_count - max_num)) old files" "rm" "$LINENO"
    fi
}

# Function: Check required commands availability
check_commands() {
    for cmd in curl awk tar; do
        if ! command -v $cmd >/dev/null 2>&1; then
            log "ERROR" "Required command $cmd not found" "main" "$LINENO"
            exit 1
        fi
    done
}

# Function: Cleanup temporary files and directories
cleanup() {
    [ -n "$backup_dir" ] && rm -rf "$backup_dir"
    [ -n "$tmp_file" ] && rm -f "$tmp_file"
    log "INFO" "Cleanup completed" "cleanup" "$LINENO"
}

# Trap cleanup on exit, interrupt, and termination
trap cleanup EXIT INT TERM

# Function: Backup original lists before update
backup_lists() {
    log "INFO" "Backup original lists" "cp" "$LINENO"

    backup_dir=$(mktemp -d)
    log "INFO" "Created temporary backup directory: $backup_dir" "mktemp" "$LINENO"

    IFS=" "
    for list_file in $domain_lists; do
        if [ -f "$list_file" ]; then
            cp -p "$list_file" "$backup_dir"
            log "INFO" "Backup $list_file to $backup_dir" "cp" "$LINENO"
        else
            log "WARNING" "$list_file does not exist, skipping backup" "cp" "$LINENO"
        fi
    done
    unset IFS
}

# Function: Restore lists from backup if update fails
restore_lists() {
    log "INFO" "Restoring lists from backup" "mv" "$LINENO"

    if [ -d "$backup_dir" ]; then
        IFS=" "
        for list_file in $domain_lists; do
            backup_file="$backup_dir/$(basename "$list_file")"
            if [ -f "$backup_file" ]; then
                mv "$backup_file" "$list_file"
                log "INFO" "Restored $list_file from $backup_file" "mv" "$LINENO"
            else
                log "WARNING" "No backup found for $list_file in $backup_dir, skipping restore" "mv" "$LINENO"
            fi
        done
        unset IFS
    else
        log "ERROR" "Backup directory $backup_dir does not exist" "mv" "$LINENO"
    fi
}

# Function: Check SmartDNS service status
check_smartdns_status() {
    log "INFO" "Check smartdns status" "systemctl/rc-service" "$LINENO"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet smartdns; then
            log "INFO" "Smartdns is running" "systemctl" "$LINENO"
            return 0
        else
            log "ERROR" "Smartdns is not running" "systemctl" "$LINENO"
            return 1
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        if rc-service smartdns status >/dev/null 2>&1; then
            log "INFO" "Smartdns is running" "rc-service" "$LINENO"
            return 0
        else
            log "ERROR" "Smartdns is not running" "rc-service" "$LINENO"
            return 1
        fi
    else
        log "ERROR" "Cannot determine service manager (systemctl/rc-service)" "check_smartdns_status" "$LINENO"
        return 1
    fi
}

# Function: Restart SmartDNS service
restart_smartdns() {
    log "INFO" "Restart smartdns" "systemctl/rc-service" "$LINENO"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart smartdns >/dev/null 2>&1
        sleep 1
        if ! systemctl is-active --quiet smartdns; then
            log "ERROR" "Restart smartdns failed" "systemctl" "$LINENO"
            restore_lists
            systemctl restart smartdns >/dev/null 2>&1
            sleep 1
            if systemctl is-active --quiet smartdns; then
                log "INFO" "Smartdns restarted after list restoration" "systemctl" "$LINENO"
            else
                log "ERROR" "Smartdns restart failed even after list restoration" "systemctl" "$LINENO"
            fi
            return 1
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service smartdns restart >/dev/null 2>&1
        sleep 1
        if ! rc-service smartdns status >/dev/null 2>&1; then
            log "WARNING" "Restart smartdns failed" "rc-service" "$LINENO"
            if [ -d "$backup_dir" ]; then
                restore_lists
            fi
            rc-service smartdns restart >/dev/null 2>&1
            sleep 1
            if rc-service smartdns status >/dev/null 2>&1; then
                log "INFO" "Smartdns restarted after list restoration" "rc-service" "$LINENO"
            else
                log "ERROR" "Smartdns restart failed even after list restoration" "rc-service" "$LINENO"
            fi
            return 1
        fi
    else
        log "ERROR" "Cannot determine service manager (systemctl/rc-service)" "restart_smartdns" "$LINENO"
        return 1
    fi
    log "INFO" "SmartDNS restarted successfully" "systemctl/rc-service" "$LINENO"
    return 0
}

# Function: Download domain lists with validation
download_domain_lists() {
    log "INFO" "Start downloading domain lists" "download_domain_lists" "$LINENO"

    # Initialize a variable to track if any file is updated
    any_updated=false

    # Use a while loop to process variables
    i=1
    while true; do
        # Get URL and corresponding list file path
        url=$(echo "$domain_urls" | awk -v i=$i '{print $i}')
        list_file=$(echo "$domain_lists" | awk -v i=$i '{print $i}')

        # Exit the loop if no more URLs are found
        [ -z "$url" ] && break

        tmp_file="${list_file}.tmp"

        # Download domain list with retry mechanism
        retries=3
        delay=5
        retry_count=0
        while [ "$retry_count" -lt "$retries" ]; do
            if curl -f -s "$url" -o "$tmp_file"; then
                log "INFO" "Download successful: $url" "curl" "$LINENO"
                break
            else
                retry_count=$((retry_count + 1))
                if [ "$retry_count" -lt "$retries" ]; then
                    log "WARNING" "Download failed (attempt $retry_count/$retries): $url" "curl" "$LINENO"
                    sleep "$delay"
                else
                    log "ERROR" "Download failed after $retries attempts: $url" "curl" "$LINENO"
                    rm -f "$tmp_file"
                    return 1
                fi
            fi
        done

        # Process OpenAI domain list (special case)
        if echo "$url" | grep -q "openai.json"; then
            sed -i '/[:{}]/d; /]/d; s/.*"\(.*\)".*/\1/' "$tmp_file"
        fi

        # Validate domain list contains valid domains
        if ! grep -q '\.' "$tmp_file"; then
            log "ERROR" "Domain list validation failed (no '.' found) for $url" "grep" "$LINENO"
            rm -f "$tmp_file"
            return 1
        fi

        # Compare temporary file with existing file content
        if [ -f "$list_file" ] && cmp -s "$tmp_file" "$list_file"; then
            log "INFO" "Domain list unchanged: $list_file" "cmp" "$LINENO"
            rm -f "$tmp_file"
        else
            # Move temporary file to final location
            mv "$tmp_file" "$list_file"
            log "INFO" "Domain list updated: $list_file" "curl" "$LINENO"
            any_updated=true
        fi

        # Increment index
        i=$((i + 1))
    done

    # Terminate update if no files were updated
    if ! $any_updated; then
        log "INFO" "All domain lists are up to date, no changes made" "download_domain_lists" "$LINENO"
        return 2
    fi

    log "INFO" "All domain lists downloaded and validated successfully" "download_domain_lists" "$LINENO"
    return 0
}

# Main execution
main() {
    log "INFO" "Main function started" "main" "$LINENO"

    check_log_dir

    if [ ! -w "$list_dir" ]; then
        log "ERROR" "No write permission for directory: $list_dir" "main" "$LINENO"
        exit 1
    fi

    check_commands

    # Check if SmartDNS is running
    if ! check_smartdns_status; then
        log "ERROR" "SmartDNS is not running, exiting" "main" "$LINENO"
        exit 1
    fi

    # Rotate logs if enabled
    if [ "$rotatelogs" = "true" ]; then
        rotate_logs
    fi

    # Backup existing lists
    backup_lists

    # Download and update domain lists
    download_status=0
    download_domain_lists
    download_status=$?

    # Handle download results
    case $download_status in
    0) # Success with updates
        if restart_smartdns; then
            log "INFO" "SmartDNS update completed successfully" "main" "$LINENO"
            cleanup
            exit 0
        else
            log "ERROR" "SmartDNS restart failed after update" "main" "$LINENO"
            restore_lists
            exit 1
        fi
        ;;
    1) # Download or validation failed
        log "ERROR" "Domain list update failed, restoring backups" "main" "$LINENO"
        restore_lists
        exit 1
        ;;
    2) # No updates needed
        log "INFO" "No domain list updates available" "main" "$LINENO"
        cleanup
        exit 0
        ;;
    *) # Unknown status
        log "ERROR" "Unknown download status: $download_status" "main" "$LINENO"
        exit 1
        ;;
    esac
}

# Run main function
main
