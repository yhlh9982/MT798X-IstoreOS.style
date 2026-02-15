#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part4.sh
# Description: OpenWrt DIY script part 4 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# 功能插件
git clone --depth=1 https://github.com/asvow/luci-app-tailscale package/tailscale

# 添加 openwrt 18.06-21.02 插件库
git clone --depth=1 -b Immortalwrt https://github.com/makebl/openwrt-package  package/openwrt-package

# theme
git clone --depth=1 -b openwrt-23.05 https://github.com/sbwml/luci-theme-argon package/argon
