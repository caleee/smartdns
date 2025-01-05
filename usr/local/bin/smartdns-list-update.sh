#!/bin/sh
#
# Filename: smartdns-list-update.sh
# Author: Cao Lei <caolei@mail.com>
# Version:  \  Date:
#   1.0.0   -    2025/01/04
# Description: This script is used to download the latest domain lists for SmartDNS.
# Usage: Run this script: `chmod +x smartdns-list-update.sh && ./smartdns-list-update.sh` (root privileges may be required depending on the output directory and usage in crontab)
# Note: Ensure that you understand every command's behaviour. Be aware that processing extremely large files might lead to memory issues.
#
# For crontab(root): 0 0 7 * * /bin/sh /path/to/your/script/smartdns-list-update.sh >/dev/null 2>&1
#
# # !!! Necessary services or software: 'sh', 'curl', 'awk', 'systemd or openrc' (for service management if applicable)
#

# Function switch: Rotate logs
rotatelogs="true"

# Script-level Variables
test_dir="/tmp/test" # 临时目录，用于测试
log_file="$test_dir/var/log/$(basename "$0").log"
backup_dir="$test_dir/var/backup/smartdns"
domestic_domain_url="https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/china-list.txt"
oversea_domain_url="https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/proxy-list.txt"
openai_domain_url="https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/openai.json"
domestic_domain_list="/var/lib/smartdns/domestic-domain.list"
oversea_domain_list="/var/lib/smartdns/oversea-domain.list"
openai_domain_list="/var/lib/smartdns/openai-domain.list"

# Function: Generate session ID
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

    # 使用 mkdir -p 确保日志目录存在
    mkdir -p "$(dirname "$log_file")"

    printf '{"timestamp":"%s","log_level":"%s","message":"%s","host_name":"%s","user_name":"%s",' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$log_level" "$message" "$(hostname)" "$USER" >>"$log_file"
    printf '"logger_name":"%s","command":"%s","line":"%s","session_id":"%s"}\n' \
        "$(basename "$0")" "$command" "$line_number" "$session_id" >>"$log_file"
}

# Function: Rotate log files
rotate_logs() {
    if [ ! -f "$log_file" ]; then
        return
    fi

    current_size=$(wc -c <"$log_file")
    max_size="$((1 * 1024 * 1024))" # 1MB

    if [ "$current_size" -lt "$max_size" ]; then
        return
    fi

    log "INFO" "Rotate logs" "tar" "$LINENO"

    # 使用 mkdir -p 确保备份目录存在
    mkdir -p "$backup_dir"

    if tar -czf "${backup_dir}/$(basename "$log_file")_$(date +%Y%m%d-%H%M%S).tar.gz" "$log_file" >/dev/null 2>&1; then
        : >"$log_file"
        log "INFO" "Rotate log completed" "tar" "$LINENO"
    else
        log "ERROR" "Rotate log failed" "tar" "$LINENO"
        return 1
    fi

    log_dir="$backup_dir"
    log_base="$(basename "$log_file")"
    file_count="$(find "$log_dir" -maxdepth 1 -name "${log_base}*tar.gz" | wc -l)"
    max_num="5" # 保留最近 5 个备份

    if [ "$file_count" -gt "$max_num" ]; then
        ls -tr "$log_dir"/${log_base}*tar.gz 2>/dev/null | head -n "$((file_count - max_num))" | xargs rm -f
        log "INFO" "Rotate log completed, cleaned $((file_count - max_num)) old files" "rm" "$LINENO"
    fi
}

# Function: Backup original lists
backup_lists() {
    log "INFO" "Backup original lists" "cp" "$LINENO"
    # 使用 mkdir -p 确保备份目录存在
    mkdir -p "$backup_dir"
    for list_file in "$domestic_domain_list" "$oversea_domain_list" "$openai_domain_list"; do
        if [ -f "$list_file" ]; then
            cp -p "$list_file" "${backup_dir}/$(basename "$list_file").$(date +%Y%m%d-%H%M%S)"
            log "INFO" "Backup $list_file completed" "cp" "$LINENO"
        else
            log "WARNING" "$list_file does not exist, skipping backup" "cp" "$LINENO"
        fi
    done
}

# Function: Check SmartDNS status
check_smartdns_status() {
    log "INFO" "Check smartdns status" "systemctl/rc-service" "$LINENO"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet smartdns; then
            log "INFO" "SmartDNS is running" "systemctl" "$LINENO"
            return 0
        else
            log "ERROR" "SmartDNS is not running" "systemctl" "$LINENO"
            return 1
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        if rc-service smartdns status | grep -q "status: started"; then
            log "INFO" "SmartDNS is running" "rc-service" "$LINENO"
            return 0
        else
            log "ERROR" "SmartDNS is not running" "rc-service" "$LINENO"
            return 1
        fi
    else
        log "ERROR" "Cannot determine service manager (systemctl/rc-service)" "check_smartdns_status" "$LINENO"
        return 1
    fi
}

# Function: Download domain lists with validation
download_domain_lists() {
    # 使用 mkdir -p 确保目标目录存在
    mkdir -p "$(dirname "$domestic_domain_list")"
    mkdir -p "$(dirname "$oversea_domain_list")"
    mkdir -p "$(dirname "$openai_domain_list")"

    # Download and validate domestic domain list
    if ! curl -s "$domestic_domain_url" -o "$domestic_domain_list.tmp"; then
        log "ERROR" "Failed to download domestic domain list" "curl" "$LINENO"
        return 1
    fi
    if ! grep -q '\.' "$domestic_domain_list.tmp"; then
        log "ERROR" "Domestic domain list validation failed (no '.' found)" "grep" "$LINENO"
        rm "$domestic_domain_list.tmp"
        return 1
    fi
    mv "$domestic_domain_list.tmp" "$domestic_domain_list"
    log "INFO" "Domestic domain list updated" "curl" "$LINENO"

    # Download and validate oversea domain list
    if ! curl -s "$oversea_domain_url" -o "$oversea_domain_list.tmp"; then
        log "ERROR" "Failed to download oversea domain list" "curl" "$LINENO"
        return 1
    fi
    if ! grep -q '\.' "$oversea_domain_list.tmp"; then
        log "ERROR" "Oversea domain list validation failed (no '.' found)" "grep" "$LINENO"
        rm "$oversea_domain_list.tmp"
        return 1
    fi
    mv "$oversea_domain_list.tmp" "$oversea_domain_list"
    log "INFO" "Oversea domain list updated" "curl" "$LINENO"

    # Download and validate OpenAI domain list
    if ! curl -s "$openai_domain_url" | sed '/[:{}]/d; /]/d; s/.*"\(.*\)".*/\1/' >"$openai_domain_list.tmp"; then
        log "ERROR" "Failed to download or process OpenAI domain list" "curl/sed" "$LINENO"
        return 1
    fi
    if ! grep -q '\.' "$openai_domain_list.tmp"; then
        log "ERROR" "OpenAI domain list validation failed (no '.' found)" "grep" "$LINENO"
        rm "$openai_domain_list.tmp"
        return 1
    fi
    mv "$openai_domain_list.tmp" "$openai_domain_list"
    log "INFO" "OpenAI domain list updated" "curl/sed" "$LINENO"
}

# Function: Restore lists from backup
restore_lists() {
    log "INFO" "Restoring lists from backup" "mv" "$LINENO"
    for list_file in "$domestic_domain_list" "$oversea_domain_list" "$openai_domain_list"; do
        backup_file=$(find "$backup_dir" -name "$(basename "$list_file").*" -print0 | sort -rz | tr '\0' '\n' | head -n 1)
        if [ -n "$backup_file" ]; then
            mv "$backup_file" "$list_file"
            log "INFO" "Restored $list_file from backup" "mv" "$LINENO"
        else
            log "WARNING" "No backup found for $list_file, skipping restore" "mv" "$LINENO"
        fi
    done
}

# Function: Restart SmartDNS
restart_smartdns() {
    log "INFO" "Restart smartdns" "systemctl/rc-service" "$LINENO"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart smartdns
        if ! systemctl is-active --quiet smartdns; then
            log "ERROR" "Restart smartdns failed" "systemctl" "$LINENO"
            restore_lists
            systemctl restart smartdns
            if systemctl is-active --quiet smartdns; then
                log "INFO" "SmartDNS restarted after list restoration" "systemctl" "$LINENO"
            else
                log "ERROR" "SmartDNS restart failed even after list restoration" "systemctl" "$LINENO"
            fi
            return 1
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service smartdns restart
        if ! rc-service smartdns status | grep -q "status: started"; then
            log "ERROR" "Restart smartdns failed" "rc-service" "$LINENO"
            restore_lists
            rc-service smartdns restart
            if rc-service smartdns status | grep -q "status: started"; then
                log "INFO" "SmartDNS restarted after list restoration" "rc-service" "$LINENO"
            else
                log "ERROR" "SmartDNS restart failed even after list restoration" "rc-service" "$LINENO"
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

# Main execution
main() {
    log "INFO" "Main function started" "main" "$LINENO"

    if [ "$rotatelogs" = "true" ]; then
        rotate_logs
    fi

    if ! check_smartdns_status; then
        log "ERROR" "SmartDNS is not running, exiting" "main" "$LINENO"
        exit 1
    fi

    backup_lists

    if ! download_domain_lists; then
        log "ERROR" "Failed to download or validate domain lists, exiting" "main" "$LINENO"
        exit 1
    fi

    if restart_smartdns; then
        log "INFO" "SmartDNS update completed with restart" "main" "$LINENO"
    else
        log "ERROR" "SmartDNS update failed" "main" "$LINENO"
    fi

    log "INFO" "Main function finished" "main" "$LINENO"
}

# Run main function
main
