Create a rom for my Router ( Xiaomi MiWiFi Nano )

openwrt selector https://firmware-selector.openwrt.org/


不要ipv6, ppp

luci luci-ssl -ppp -ppp-mod-pppoe -kmod-ppp -kmod-pppoe -kmod-pppox -luci-proto-ppp -odhcpd-ipv6only -odhcp6c -ip6tables -kmod-ip6tables -kmod-ipv6 -kmod-nf-conntrack6 -kmod-nf-ipt6 -kmod-nf-reject6 -luci-proto-ipv6


#!/bin/sh

设置 root 密码（替换 YourStrongPassword 为你的密码）

echo -e 'YourStrongPassword\nYourStrongPassword' | passwd root

设置时区为中国上海（北京时间）

uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'

启用时间同步（可选，确保 NTP 服务器）

uci set system.ntp.enable_server='1'
uci delete system.ntp.server  # 清空默认
uci add_list system.ntp.server='ntp1.aliyun.com'
uci add_list system.ntp.server='time.edu.cn'
uci add_list system.ntp.server='pool.ntp.org'

uci commit system

/etc/init.d/sysntpd restart  # 重启 NTP 服务

exit 0

#!/bin/sh

启用 radio0 并设置基本参数

uci set wireless.radio0.disabled='0'
uci set wireless.radio0.channel='auto'  # 或 '1'/'6'/'11'
uci set wireless.radio0.country='CN'    # 中国代码
uci set wireless.radio0.htmode='HT20'   # Nano 标准

配置默认 AP 接口

uci set wireless.default_radio0.ssid='MyNanoWiFi'          # 你的 Wi-Fi 名称
uci set wireless.default_radio0.encryption='psk2'         # WPA2-PSK
uci set wireless.default_radio0.key='YourStrongPassword'  # 你的密码（至少8位）
uci set wireless.default_radio0.mode='ap'
uci set wireless.default_radio0.network='lan'

防止重复执行（可选）

uci set wireless.default_radio0.initialized='1'

uci commit wireless
wifi reload  # 立即生效

exit 0
-------------------------------------------------------------------
更新软件列表

opkg update

更新所有 LUCI 插件

opkg list-upgradable | grep luci- | cut -f 1 -d ' ' | xargs opkg upgrade


如果要更新所有软件，包括 OpenWRT 内核、固件等

opkg list-upgradable | cut -f 1 -d ' ' | xargs opkg upgrade



reinstall luci:

opkg update
opkg instakk luci-compat
opkg install luci-lua-runtime

---

## 自动构建定制固件（GitHub Actions，免本地环境）

本仓库已集成基于官方 ImageBuilder 的一键固件构建（小米 MiWiFi Nano）：

1. 打开仓库 **Actions** 页面 → 选择 **构建路由器固件 (OpenWrt ImageBuilder)** → 点击 **Run workflow**
2. 参数保持默认即可直接构建；也可按需修改 Wi-Fi 名称 / Wi-Fi 密码 / root 密码 / OpenWrt 版本
3. 等待约 5–10 分钟，构建完成后在运行详情页底部 **Artifacts** 下载 `openwrt-*-xiaomi-miwifi-nano.zip`
4. 解压得到 `*-sysupgrade.bin`，在固件升级页面刷入

固件定制内容（首次开机自动生效，脚本执行后即自动删除）：

- 移除 IPv6 / PPP 相关软件包（见 `firmware/packages.txt`）
- 内置 LuCI 网页管理界面（HTTPS）+ `owut` 在线升级工具
- 时区 Asia/Shanghai；NTP：`ntp1.aliyun.com` / `time.edu.cn` / `pool.ntp.org`
- 无线默认开启（2.4GHz / HT20 / 国家码 CN），SSID 与加密按构建参数

### 本地构建

需要能访问 `downloads.openwrt.org` 的 Linux x86_64 环境：

```sh
bash firmware/build.sh
# 或者带参数：
WIFI_SSID=我的WiFi WIFI_KEY=mypassword123 ROOT_PASSWORD=mysecret bash firmware/build.sh
```

产物输出到 `out/<版本>/`（含 `.bin` 固件与 `sha256sums.txt` 校验文件）。

### 安全提示

- 默认配置下 Wi-Fi 出厂为**开放状态**（无密码），首次登录后请**立即**在 LuCI 中设置 Wi-Fi 密码与 root 密码
- 构建参数中的密码只作为工作流输入传递，不会写入仓库；root 密码在固件中也仅以哈希形式存在
- 刷入新固件后旧配置不会保留，请提前做好备份
