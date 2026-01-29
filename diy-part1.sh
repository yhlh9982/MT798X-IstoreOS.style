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
echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
echo 'src-git nas https://github.com/linkease/nas-packages.git;master' >> feeds.conf.default
echo 'src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main' >> feeds.conf.default

# 科学插件
git clone --depth=1 https://github.com/QiuSimons/luci-app-daed package/luci-app-daed
git clone --depth=1 -b main https://github.com/fw876/helloworld package/luci-app-ssr-plus
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-app-passwall2
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-momo package/luci-app-momo
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki package/luci-app-nikki
git clone --depth=1 -b master https://github.com/vernesong/OpenClash package/luci-app-openclash
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
