#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# =========================================================
# 修复 Rust 编译失败：替换为 ImmortalWrt 稳定版 Rust 
# =========================================================

# 1. 删除当前源码中有问题/下载失败的 Rust
echo "Removing broken Rust package..."
rm -rf feeds/packages/lang/rust

# 2. 克隆 ImmortalWrt 其他 分支的 packages
echo "Cloning stable Rust from ImmortalWrt..."
git clone --depth 1 -b openwrt-25.12 https://github.com/immortalwrt/packages.git temp_packages

# 3. 偷梁换柱：把稳定的 Rust 搬进来
cp -r temp_packages/lang/rust feeds/packages/lang/

# 4. 清理现场
rm -rf temp_packages

echo "Rust has been replaced with stable version 1.85.0!"

# =========================================================
# 修复 QuickStart 首页温度显示问题 (方案：修改源码)
# =========================================================

# 1. 智能获取自定义文件的绝对路径
# $0 代表当前脚本本身，dirname 获取脚本所在目录(即仓库根目录)
REPO_ROOT=$(dirname "$(readlink -f "$0")")
CUSTOM_LUA="$REPO_ROOT/istore/istore_backend.lua"

echo "Debug: Repo root is $REPO_ROOT"
echo "Debug: Looking for custom file at $CUSTOM_LUA"

# 2. 在 feeds 目录中查找目标文件
TARGET_LUA=$(find feeds -name "istore_backend.lua" -type f)

if [ -n "$TARGET_LUA" ]; then
    echo "Found target file: $TARGET_LUA"
    if [ -f "$CUSTOM_LUA" ]; then
        echo "Overwriting with custom file..."
        cp -f "$CUSTOM_LUA" "$TARGET_LUA"
        
        # 再次检查是否覆盖成功
        if cmp -s "$CUSTOM_LUA" "$TARGET_LUA"; then
             echo "✅ Overwrite Success! Files match."
        else
             echo "❌ Error: Copy failed or files do not match."
        fi
    else
        echo "❌ Error: Custom file ($CUSTOM_LUA) not found!"
        # 列出仓库根目录看看有什么，方便排错
        ls -l "$REPO_ROOT"
    fi
else
    echo "❌ Error: Target istore_backend.lua not found in feeds!"
fi

#修复DiskMan编译失败
DM_FILE="./luci-app-diskman/applications/luci-app-diskman/Makefile"
if [ -f "$DM_FILE" ]; then
	echo " "

	sed -i '/ntfs-3g-utils /d' $DM_FILE

	cd $PKG_PATH && echo "diskman has been fixed!"
fi

# 修复 libxcrypt 编译报错
# 给 configure 脚本添加 --disable-werror 参数，忽略警告
sed -i 's/CONFIGURE_ARGS +=/CONFIGURE_ARGS += --disable-werror/' feeds/packages/libs/libxcrypt/Makefile

# 自定义默认网关，后方的192.168.30.1即是可自定义的部分
sed -i 's/192.168.[0-9]*.[0-9]*/192.168.30.1/g' package/base-files/files/bin/config_generate

# 自定义主机名
#sed -i "s/hostname='ImmortalWrt'/hostname='360T7'/g" package/base-files/files/bin/config_generate

# 固件版本名称自定义
#sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='OpenWrt By gino $(date +"%Y%m%d")'/g" package/base-files/files/etc/openwrt_release

# 取消原主题luci-theme-bootstrap 为默认主题
# sed -i '/set luci.main.mediaurlbase=\/luci-static\/bootstrap/d' feeds/luci/themes/luci-theme-bootstrap/root/etc/uci-defaults/30_luci-theme-bootstrap

# 删除原默认主题
# rm -rf package/lean/luci-theme-bootstrap

# 修改 argon 为默认主题
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
