Create a rom for my Router ( Xiaomi MiWiFi Nano )

openwrt selector https://firmware-selector.openwrt.org/


不要ipv6, ppp
####
luci luci-ssl -ppp -ppp-mod-pppoe -kmod-ppp -kmod-pppoe -kmod-pppox -luci-proto-ppp -odhcpd-ipv6only -odhcp6c -ip6tables -kmod-ip6tables -kmod-ipv6 -kmod-nf-conntrack6 -kmod-nf-ipt6 -kmod-nf-reject6 -luci-proto-ipv6

####

#!/bin/sh

# 设置 root 密码（替换 YourStrongPassword 为你的密码）
echo -e 'YourStrongPassword\nYourStrongPassword' | passwd root

# 设置时区为中国上海（北京时间）
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'

# 启用时间同步（可选，确保 NTP 服务器）
uci set system.ntp.enable_server='1'
uci delete system.ntp.server  # 清空默认
uci add_list system.ntp.server='ntp1.aliyun.com'
uci add_list system.ntp.server='time.edu.cn'
uci add_list system.ntp.server='pool.ntp.org'

uci commit system

/etc/init.d/sysntpd restart  # 重启 NTP 服务

exit 0

#!/bin/sh

# 启用 radio0 并设置基本参数
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.channel='auto'  # 或 '1'/'6'/'11'
uci set wireless.radio0.country='CN'    # 中国代码
uci set wireless.radio0.htmode='HT20'   # Nano 标准

# 配置默认 AP 接口
uci set wireless.default_radio0.ssid='MyNanoWiFi'          # 你的 Wi-Fi 名称
uci set wireless.default_radio0.encryption='psk2'         # WPA2-PSK
uci set wireless.default_radio0.key='YourStrongPassword'  # 你的密码（至少8位）
uci set wireless.default_radio0.mode='ap'
uci set wireless.default_radio0.network='lan'

# 防止重复执行（可选）
uci set wireless.default_radio0.initialized='1'

uci commit wireless
wifi reload  # 立即生效

exit 0
-------------------------------------------------------------------
# 更新软件列表
opkg update

# 更新所有 LUCI 插件
opkg list-upgradable | grep luci- | cut -f 1 -d ' ' | xargs opkg upgrade

# 如果要更新所有软件，包括 OpenWRT 内核、固件等
opkg list-upgradable | cut -f 1 -d ' ' | xargs opkg upgrade



reinstall luci :
opkg update
opkg instakk luci-compat
opkg install luci-lua-runtime
