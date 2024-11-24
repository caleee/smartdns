## 当前项目中有价值的内容:

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

---

