#!/bin/sh
#
# Filename: smartdns_cf-rule_update.sh
# Author: Cao Lei <caolei@mail.com>
# Version:  \  Date:
#   1.0.0   -    2024/11/25
#   1.0.1   -    2024/11/26
#   1.0.2   -    2024/11/28
# Description: This script is used to write the preferred Cloudflare IP to the SmartDNS IP rules.
# Usage: Run this script as root: `chmod +x smartdns_cf-rule_update.sh && sh smartdns_cf-rule_update.sh`
# # If you need to restore the DNS configuration: `sh smartdns_cf-rule_update.sh restore`
# Note: Ensure that you understand every command's behaviour and be careful when identifying large files
#
# For crontab(root): 0 6 * * * /bin/sh /usr/local/bin/smartdns_cf-rule_update.sh >/dev/null 2>&1
#
# # !!! Necessary services or software: 'sh' 'systemd or openrc' 'CloudflareST' 'awk' 'sed'
# # !!! Necessary data or dir '/var/lib/smartdns/cloudflare-ipv4.list' '/var/lib/smartdns/cloudflare-ipv6.list'
# # '/etc/smartdns/smartdns.conf-<cloudflare ip-rules>' '/var/log/smartdns/'
# # [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)
#

# Function switch
ipv6="on"
frfile="no"

# Variables
log_file="/var/log/smartdns/$(basename "$0").log"
dns_conf="/etc/smartdns/smartdns.conf"
result_file="/tmp/cfst_result.csv"
temp_file="$(mktemp)"

# Format result file
format_result_file() {
    if [ ! -f $result_file ]; then
        echo "IP 地址,已发送,已接收,丢包率,平均延迟,下载速度 (MB/s),时间" >$result_file
    fi
}

if [ $frfile = "yes" ]; then
    format_result_file
fi

# Generate session id
generate_session_id() {
    echo "$(date +%Y%m%d%H%M%S)$RANDOM"
}

# Log function
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

# CloudflareST function
cloudflarest() {
    log "INFO" "CF-$1 speedtest" "CloudflareST" "$LINENO"
    if /usr/local/bin/CloudflareST -n 1000 -t 10 -dn 50 -tl 200 -tlr 0.1 -sl 5 -p 50 \
        -f /var/lib/smartdns/cloudflare-"$1".list -o "$temp_file"; then
        log "INFO" "CF-$1 speedtest -> done" "CloudflareST" "$LINENO"
    else
        log "ERROR" "CF-$1 speedtest -> failed" "CloudflareST" "$LINENO"
        exit 1
    fi

    log "INFO" "CF-$1 write to <$result_file>" "awk" "$LINENO"
    awk 'NR==2 || NR==3 {
        cmd = "TZ=\"Asia/Shanghai\" date +\"%Y-%m-%d_%H:%M\"";
        cmd | getline timestamp;
        close(cmd);
        print $0 "," timestamp
    }' "$temp_file" >>$result_file
}

# Alter SmartDNS configuration
alter_smartdns_conf() {
    log "INFO" "Alter smartdns.conf" "sed" "$LINENO"

    cf_ip="$(awk -F',' 'NR==2 {printf "%s,", $1} NR==3 {print $1}' "$temp_file")"
    cf_rule="ip-set:cloudflare-$1 -ip-alias"

    sed -i.bak "s/$cf_rule .*/$cf_rule $cf_ip/" "$dns_conf"
    rm "$temp_file"
}

# Restart SmartDNS server
restart_smartdns() {
    log "INFO" "Restart smartdns" "restart" "$LINENO"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart smartdns
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service smartdns restart
    else
        log "ERROR" "Restart smartdns -> failed" "restart" "$LINENO"
        exit 1
    fi
}

# Backup SmartDNS configuration
restore() {
    log "INFO" "Restore smartdns.conf" "restore" "$LINENO"

    if [ -f "${dns_conf}.bak" ]; then
        cp $dns_conf.bak $dns_conf
    fi

    restart_smartdns
}

if [ "$1" = "restore" ]; then
    restore
fi

# Action
main() {
    if [ "$ipv6" = "on" ]; then
        for i in "ipv4" "ipv6"; do
            cloudflarest $i
            alter_smartdns_conf $i
        done
    else
        cloudflarest ipv4
        alter_smartdns_conf ipv4
    fi

    restart_smartdns
}

main
