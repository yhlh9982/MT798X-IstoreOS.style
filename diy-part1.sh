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

# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# Add a feed source
echo 'src-git helloworld https://github.com/fw876/helloworld.git' >> feeds.conf.default
echo 'src-git openclash https://github.com/vernesong/OpenClash.git' >>feeds.conf.default
echo 'src-git nikiki https://github.com/nikkinikki-org/OpenWrt-nikki.git' >> feeds.conf.default
echo 'src-git passwall https://github.com/xiaorouji/openwrt-passwall.git' >>feeds.conf.default
echo 'src-git passwall2 https://github.com/xiaorouji/openwrt-passwall2.git' >>feeds.conf.default
echo 'src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git' >>feeds.conf.default

# 主题
git clone --depth=1 https://github.com/sirpdboy/luci-theme-kucat.git package/luci-theme-kucat
git clone --depth=1 -b master https://github.com/sirpdboy/luci-app-kucat-config.git package/luci-theme-kucat-config
git clone --depth=1 https://github.com/eamonxg/luci-theme-aurora.git package/luci-theme-aurora
git clone --depth=1 https://github.com/eamonxg/luci-app-aurora-config.git package/luci-theme-aurora-config

# 常用工具与应用
git clone --depth=1 https://github.com/sirpdboy/luci-app-poweroffdevice.git package/luci-app-poweroffdevice # 关机功能
git clone --depth=1 -b main https://github.com/oppen321/luci-app-wolplus package/luci-app-wolplus #网络唤醒
git clone --depth=1 https://github.com/asvow/luci-app-tailscale.git package/luci-app-tailscale # Tailscale
git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac.git package/luci-app-gecoosac # 集客 AC 控制器
git clone --depth=1 https://github.com/sirpdboy/luci-app-partexp.git package/luci-app-partexp  #一键自动格式化分区、扩容、自动挂载插件
git clone --depth=1 https://github.com/EasyTier/luci-app-easytier.git package/luci-app-easytier # EasyTier
git clone --depth=1 https://github.com/destan19/OpenAppFilter.git package/luci-app-oaf  # 应用过滤(OAF)
git clone --depth=1 https://github.com/sirpdboy/luci-app-taskplan.git package/luci-app-taskplan   #任务设置2.0版
git clone --depth=1 https://github.com/sirpdboy/luci-app-watchdog.git package/luci-app-watchdog  #看门狗
git clone --depth=1 https://github.com/sirpdboy/luci-app-advancedplus.git package/luci-app-advancedplus
git clone --depth=1 https://github.com/KyleRicardo/MentoHUST-OpenWrt-ipk.git package/luci-app-mentohust  #锐捷验证 luci-app-mentohust
git clone --depth=1 https://github.com/sbwml/luci-app-quickfile.git package/luci-app-quickfile  #文件管理
