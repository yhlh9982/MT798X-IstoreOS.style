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

set -e

echo "=========================================="
echo "Rust 修复方案：替换为 23.05 稳定版 + 强制本地编译"
echo "=========================================="

# 1. 移除当前可能不稳定的 Rust
rm -rf feeds/packages/lang/rust

# 2. 从 ImmortalWrt 23.05 分支拉取稳定的 Rust (版本 1.85.0)
# 虽然我们要本地编译，但使用旧版源码更稳定，兼容性更好
echo ">>> Cloning Rust from ImmortalWrt 23.05 branch..."
git clone --depth 1 -b openwrt-23.05 https://github.com/openwrt/packages.git temp_packages

# 3. 替换
cp -r temp_packages/lang/rust feeds/packages/lang/

# 4. 清理
rm -rf temp_packages

echo ">>> Rust replaced with stable version (1.85.0)."

# 5. 【关键修改】强制关闭 CI 下载，启用本地编译
RUST_MK="feeds/packages/lang/rust/Makefile"

if [ -f "$RUST_MAKEFILE" ]; then
    echo ">>> Configuring Rust for LOCAL compilation..."
    
    # 将 download-ci-llvm = true 替换为 false
    # 注意：这里处理了可能有空格或没空格的两种情况
    sed -i 's/download-ci-llvm = true/download-ci-llvm = false/g' "$RUST_MK"
    sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$RUST_MK"
    
    echo "✅ download-ci-llvm has been DISABLED."
    echo "⚠️  WARNING: This will trigger LLVM compilation."
    echo "⚠️  Expect compilation time to increase by 1-2 hours."
else
    echo "❌ Error: Rust Makefile not found!"
fi

echo "=========================================="
echo "修复完成。准备进行本地编译。"
echo "=========================================="

# =========================================================
# 智能修复脚本（兼容 package/ 和 feeds/）
# =========================================================
REPO_ROOT=$(readlink -f "$GITHUB_WORKSPACE")
CUSTOM_LUA="$REPO_ROOT/istore/istore_backend.lua"

echo "Debug: Repo root is $REPO_ROOT"

# 1. 优先查找 package 目录
TARGET_LUA=$(find package -name "istore_backend.lua" -type f 2>/dev/null)

# 2. 如果 package 中没找到，再查找 feeds
if [ -z "$TARGET_LUA" ]; then
    echo "Not found in package/, searching in feeds/..."
    TARGET_LUA=$(find feeds -name "istore_backend.lua" -type f 2>/dev/null)
fi

# 3. 执行覆盖（逻辑与原脚本相同）
if [ -n "$TARGET_LUA" ]; then
    echo "Found target file: $TARGET_LUA"
    if [ -f "$CUSTOM_LUA" ]; then
        echo "Overwriting with custom file..."
        cp -f "$CUSTOM_LUA" "$TARGET_LUA"
        if cmp -s "$CUSTOM_LUA" "$TARGET_LUA"; then
             echo "✅ Overwrite Success! Files match."
        else
             echo "❌ Error: Copy failed or files do not match."
        fi
    else
        echo "❌ Error: Custom file ($CUSTOM_LUA) not found!"
        ls -l "$REPO_ROOT/istore" 2>/dev/null || echo "Directory not found"
    fi
else
    echo "❌ Error: istore_backend.lua not found in package/ or feeds/!"
fi

echo ">>> Patching DiskMan and libxcrypt..."

#  DiskMan 修复
DM_MAKEFILE=$(find feeds/luci -name "Makefile" | grep "luci-app-diskman")
if [ -f "$DM_MAKEFILE" ]; then
    sed -i '/ntfs-3g-utils /d' "$DM_MAKEFILE"
    echo "✅ DiskMan fix applied."
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

# 删除原默认主题
rm -rf feeds/luci/theme/luci-theme-bootstrap

# 修改 argon 为默认主题
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")

# 取消原主题luci-theme-bootstrap 为默认主题
sed -i '/set luci.main.mediaurlbase=\/luci-static\/bootstrap/d' feeds/luci/themes/luci-theme-bootstrap/root/etc/uci-defaults/30_luci-theme-bootstrap
