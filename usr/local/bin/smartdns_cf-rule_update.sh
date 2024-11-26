#!/bin/sh
#
# Filename: smartdns_cf-rule_update.sh
# Author: Cao Lei <caolei@mail.com>
# Version:  \  Date:
#   1.0.0   -    2024/11/25
#   1.0.1   -    2024/11/26
# Description: This script is used to write the preferred Cloudflare IP to the SmartDNS IP rules.
# Usage: Run this script as root: `chmod +x smartdns_cf-rule_update.sh && sh smartdns_cf-rule_update.sh`
# # If you need to restore the DNS configuration: `sh smartdns_cf-rule_update.sh restore`
# Note: Ensure that you understand every command's behaviour and be careful when identifying large files
#
# For crontab(root): 0 6 * * * /bin/sh /usr/local/bin/smartdns_cf-rule_update.sh >/dev/null 2>&1
#
# # !!! Necessary services or software: 'sh' 'systemd or openrc' 'CloudflareST' 'awk' 'sed'
# # !!! Necessary data or dir '/var/lib/smartdns/cloudflare-ipv4.list' '/var/lib/smartdns/cloudflare-ipv6.list' '/etc/smartdns/smartdns.conf-<cloudflare ip-rules>' '/var/log/smartdns/'
# # [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)
#

set -e

ipv6="on"
log_file="/var/log/smartdns/smartdns_cfip_update.log"
dns_conf="/etc/smartdns/smartdns.conf"
file_result="/tmp/cfst_result.csv"

if [ ! -f $file_result ]; then
    echo "IP 地址,已发送,已接收,丢包率,平均延迟,下载速度 (MB/s),时间" >$file_result
fi

log() {
    status="$1"
    cmd="$2"
    message="$3"
    datetime=$(date '+%Y-%m-%dT%H:%M:%S.%6N%:z')
    script_name=$(basename "$0")
    user=$(whoami)

    echo "${datetime} ${status} ${script_name} (${user}) CMD (${cmd}) MSG (${message})" >>"${log_file}"
}

cloudflarest() {
    log "INFO" "CloudflareST" "Start cloudflare IP speed test."

    file_out="$(mktemp)"
    /usr/local/bin/CloudflareST -n 1000 -t 10 -dn 50 -tl 200 -tlr 0.1 -sl 5 -p 50 -f /var/lib/smartdns/cloudflare-"$1".list -o "$file_out"
    
    log "INFO" "CloudflareST" "Cloudflare IP speed test completed."
    log "INFO" "awk" "Cloudflare IP speed ranking data written to <$file_result>."

    awk 'NR==2 || NR==3 {
        cmd = "TZ=\"Asia/Shanghai\" date +\"%Y-%m-%d_%H:%M\"";
        cmd | getline timestamp;
        close(cmd);
        print $0 "," timestamp
    }' "$file_out" >>$file_result
}

alter_smartdns_conf() {
    log "INFO" "sed" "Alter the SmartDNS configuration."

    cf_ip="$(awk -F',' 'NR==2 {printf "%s,", $1} NR==3 {print $1}' "$file_out")"
    cf_rule="ip-set:cloudflare-$1 -ip-alias"

    sed -i.bak "s/$cf_rule .*/$cf_rule $cf_ip/" "$dns_conf"

    rm "$file_out"
}

restart_smartdns() {
    log "INFO" "restart" "Restart SmartDNS server."
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart smartdns
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service smartdns restart
    else
        log "ERROR" "Service check" "No compatible service manager found (systemctl or rc-service)"
        exit 1
    fi
}

restore() {
    log "INFO" "backup" "Restore SmartDNS configuration."

    if [ -f "${dns_conf}.bak" ]; then
        cp $dns_conf.bak $dns_conf
    fi

    restart_smartdns
}

if [ "$1" = "restore" ]; then
    restore
fi

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
