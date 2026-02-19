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
git clone --depth=1 https://github.com/linkease/istore  package/istore
git clone --depth=1 https://github.com/linkease/nas-packages  package/nas
git clone --depth=1 https://github.com/linkease/nas-packages-luci  package/nas-luci

# 科学插件
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall  package/passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2  package/passwall2
# git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages  package/passwall-packages
git clone --depth=1 -b master https://github.com/vernesong/OpenClash  package/OpenClash
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki  package/nikki
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-momo  package/momo
git clone --depth=1 -b master https://github.com/QiuSimons/luci-app-daed  package/daed
git clone --depth=1 -b master https://github.com/fw876/helloworld  package/helloworld

# 功能插件
git clone --depth=1 https://github.com/sirpdboy/luci-app-watchdog package/watchdog
git clone --depth=1 https://github.com/sirpdboy/luci-app-taskplan package/taskplan
git clone --depth=1 https://github.com/iv7777/luci-app-authshield package/authshield
git clone --depth=1 https://github.com/EasyTier/luci-app-easytier package/easytier
git clone --depth=1 https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community package/tailscale
git clone --depth=1 https://github.com/isalikai/luci-app-owq-wol package/luci-app-owq-wol

# 主题
git clone --depth=1 -b openwrt-24.10 https://github.com/sbwml/luci-theme-argon package/argon
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora package/aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config package/aurora-config
git clone --depth=1 https://github.com/sirpdboy/luci-theme-kucat package/kucat
git clone --depth=1 -b master https://github.com/sirpdboy/luci-app-kucat-config package/kucat-config
