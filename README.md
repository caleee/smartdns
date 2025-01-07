- [当前项目中有价值的内容:](#当前项目中有价值的内容)
  - [SmartDNS 的 OpenRC 入口脚本(alpine等简化的Linux发行版)](#smartdns-的-openrc-入口脚本alpine等简化的linux发行版)
  - [自动化 POSIX shell(sh) 脚本: Cloudflare优选后的IP替换 smartdns.conf ip-rules 内容并重启生效](#自动化-posix-shellsh-脚本-cloudflare优选后的ip替换-smartdnsconf-ip-rules-内容并重启生效)
    - [前提条件](#前提条件)
      - [Linux 安装 SmartDNS](#linux-安装-smartdns)
      - [Linux 安装 CloudflareSpeedTest](#linux-安装-cloudflarespeedtest)
      - [SmartDNS CF-IP 优选相关规则](#smartdns-cf-ip-优选相关规则)
    - [脚本说明](#脚本说明)
    - [计划任务](#计划任务)
  - [域名名单更新脚本](#域名名单更新脚本)
- [感谢:](#感谢)

## 当前项目中有价值的内容:

### SmartDNS 的 OpenRC 入口脚本(alpine等简化的Linux发行版)

`etc/init.d/smartdns_openrc`

smartdns官方的启动脚本`etc/init.d/smartdns`对使用`OpenRC`的Linux发行版兼容性不好

表现在: 

- 设置开机自启后`rc-update add smartdns`, 重启系统smartdns不自启动
- 更改配置文件后(配置domain-set list较大domain-rules引用时)`rc-service smartdns restart`显示启动失败, 但实际上已成功启动

所以简单写了 OpenRC Service Script 用于替换原版

```bash
cp /etc/init.d/smartdns /etc/init.d/smartdns.bak
curl https://raw.githubusercontent.com/caleee/smartdns/refs/heads/main/etc/init.d/smartdns_openrc -o /etc/init.d/smartdns
chmod +x /etc/init.d/smartdns
```

### 自动化 POSIX shell(sh) 脚本: Cloudflare优选后的IP替换 smartdns.conf ip-rules 内容并重启生效

**[脚本路径](usr/local/bin/smartdns_cf-rule_update.sh)**

#### 前提条件

##### Linux 安装 SmartDNS

```bash
# 到smartdns项目 https://github.com/pymumu/smartdns/releases
# 下载配套安装包，并上传到 Linux 系统中, 标准 Linux 系统（X86 / X86_64）请执行如下命令安装：

tar zxf smartdns.1.yyyy.MM.dd-REL.x86_64-linux-all.tar.gz
cd smartdns
chmod +x ./install
./install -i
```

##### Linux 安装 CloudflareSpeedTest

```bash
# 到smartdns项目 https://github.com/XIU2/CloudflareSpeedTest/releases
# 下载配套安装包，并上传到 Linux 系统中

# 解压（不需要删除旧文件，会直接覆盖，自行根据需求替换 文件名）
tar -zxf CloudflareST_linux_amd64.tar.gz

# 赋予执行权限
chmod +x CloudflareST

# 安装
cp CloudflareST cfst_hosts.sh /usr/local/bin/
cp ip.txt /var/lib/smartdns/cloudflare-ipv4.list
cp ipv6.txt /var/lib/smartdns/cloudflare-ipv6.list
```

##### SmartDNS CF-IP 优选相关规则

```bash
# 配置 Cloudflare CDN 加速

## 设置Cloudflare IPV4别名映射
ip-set -name cloudflare-ipv4 -type list -file /var/lib/smartdns/cloudflare-ipv4.list
ip-rules ip-set:cloudflare-ipv4 -ip-alias 104.17.180.159,104.21.12.179

## 设置Cloudflare IPV6别名映射
ip-set -name cloudflare-ipv6 -type list -file /var/lib/smartdns/cloudflare-ipv6.list
ip-rules ip-set:cloudflare-ipv6 -ip-alias 2400:cb00:2049::ad:8e46:3a27,2a06:98c1:310c::e943:e21a:fe89
```

#### 脚本说明

- 理论上兼容常见的 Linux 发行版 (测试环境 PVE-lxc-alpine)
- 脚本放在 `/usr/local/bin/smartdns_cf-rule_update.sh` 并附执行权限 `chmod +x /usr/local/bin/smartdns_cf-rule_update.sh `
- 执行脚本 `smartdns_cf-rule_update.sh` or ``/usr/local/bin/smartdns_cf-rule_update.sh` or `sh /usr/local/bin/smartdns_cf-rule_update.sh`

- 注释 `ipv6="on"` 关闭 ipv6筛选
- `cat /tmp/cfst_result.csv`查看结果 (带时间戳)
- `tail -20 /var/log/smartdns/smartdns_cfip_update.log`查看日志
- 还原 smartdns 配置执行 restore 参数 `/usr/local/bin/smartdns_cf-rule_update.sh restore`
- CloudflareSpeedTest 的 CloudflareST 工具参数很多, 到大佬的项目里自行翻阅(下面有链接), 脚本中设置测试IP数量很多(50+50), 大概需要20分钟, 如需定制自行修改
- 注意: 脚本需要放在smartdns的服务器上执行, 还要注意服务器需求直连, 代理上网配置也要指定clouldflare cdn ip段直连, 否则改了smartdns配置也无用, 甚至是倒吸牙膏; 执意要 cf cdn 走代理的 CloudflareST 工具有相关参数, 自行研究

#### 计划任务

```bash
# 每日6:00执行一次
crontab -e
0 6 * * * /bin/sh /usr/local/bin/smartdns_cf-rule_update.sh >/dev/null 2>&1
```

### 域名名单更新脚本

**[脚本路径](usr/local/bin/smartdns_list_update.sh)**

#### 脚本说明

- 根据我使用的配置文件中的`domain-set`相关内容码的`list`升级脚本, 没有泛用性, 借鉴可以

  ```bash
  domain-set -name domestic-domain -type list -file /var/lib/smartdns/domestic-domain.list
  domain-set -name oversea-domain -type list -file /var/lib/smartdns/oversea-domain.list
  domain-set -name openai-domain -type list -file /var/lib/smartdns/openai-domain.list
  
  domain-rules /domain-set:domestic-domain/ -nameserver domestic -speed-check-mode ping,tcp:80,tcp:443
  domain-rules /domain-set:oversea-domain/ -nameserver oversea -speed-check-mode none -address #6
  domain-rules /domain-set:openai-domain/ -nameserver oversea -speed-check-mode none -address #6
  ```

#### 计划任务

```bash
# 每周周日2:00执行一次
crontab -e
0 2 * * 0 /bin/sh /usr/local/bin/smartdns-list-update.sh >/dev/null 2>&1
```

## 感谢: 

@[pymumu](https://github.com/pymumu)/[smartdns](https://github.com/pymumu/smartdns)

@[XIU2](https://github.com/XIU2)/[CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)

@[jiange1236](https://github.com/jiange1236)/[smartdns-rules](https://github.com/jiange1236/smartdns-rules)

---

