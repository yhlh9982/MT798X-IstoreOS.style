#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# istore
git clone --depth=1 https://github.com/linkease/istore package/istore
git clone --depth=1 https://github.com/linkease/nas-packages package/nas
git clone --depth=1 https://github.com/linkease/nas-packages-luci package/nas-luci

git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/passwall2
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages
git clone --depth=1 -b master https://github.com/vernesong/OpenClash package/OpenClash
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki package/nikki
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-momo package/OpenWrt-momo
git clone --depth=1 -b master https://github.com/QiuSimons/luci-app-daed package/daed
git clone --depth=1 -b master https://github.com/fw876/helloworld package/helloworld

# 插件添加
git clone --depth=1 https://github.com/sirpdboy/luci-app-watchdog package/watchdog
git clone --depth=1 https://github.com/sirpdboy/luci-app-taskplan package/taskplan
git clone --depth=1 https://github.com/iv7777/luci-app-authshield package/authshield
git clone --depth=1 https://github.com/EasyTier/luci-app-easytier package/easytier
git clone --depth=1 https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community package/tailscale
# 主题
git clone --depth=1 -b openwrt-24.10 https://github.com/sbwml/luci-theme-argon.git package/argon
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora.git package/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config.git package/luci-app-aurora-config
git clone --depth=1 https://github.com/sirpdboy/luci-theme-kucat.git package/luci-theme-kucat
git clone --depth=1 -b master https://github.com/sirpdboy/luci-app-kucat-config.git package/luci-app-kucat-config
