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
echo "Rust修复"
echo "=========================================="

# 确保在源码根目录执行
[ -f "scripts/feeds" ] || { echo "❌ Error: Not in OpenWrt root"; exit 1; }

RUST_MK="feeds/packages/lang/rust/Makefile"

# 1. 自动补全 Rust 定义 (防止 Feed 拉取缺失)
if [ ! -f "$RUST_MK" ]; then
    echo ">>> Rust Makefile missing, forcing sync from ImmortalWrt..."
    mkdir -p feeds/packages/lang
    # 使用临时目录避免 set -e 触发后的残留
    TEMP_DIR=$(mktemp -d)
    git clone --depth=1 https://github.com/immortalwrt/packages.git "$TEMP_DIR"
    cp -r "$TEMP_DIR/lang/rust" feeds/packages/lang/
    rm -rf "$TEMP_DIR"
fi

# 2. 修改配置：强制本地编译 LLVM 和 Rust
echo ">>> Modifying Makefile for local compilation..."

IMM_URL="https://raw.githubusercontent.com/immortalwrt/packages/openwrt-24.10/lang/rust/Makefile"
curl -fsSL "$IMM_URL" -o /tmp/rust_ref.mk

RUST_VER=$(grep '^PKG_VERSION:=' /tmp/rust_ref.mk | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_HASH=$(grep '^PKG_HASH:=' /tmp/rust_ref.mk | head -1 | cut -d'=' -f2 | tr -d ' ')

if [ -n "$RUST_VER" ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$RUST_VER/" "$RUST_MK"
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$RUST_HASH/" "$RUST_MK"
fi

# 【核心修改】：关闭预编译的 CI LLVM，强制从源码编译
sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$RUST_MK"
# 修正官方下载地址后缀问题
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"

echo "✅ Configuration set: Rust $RUST_VER will be built from source."

# 3. 源码包预下载
RUST_FILE="rustc-${RUST_VER}-src.tar.xz"
mkdir -p dl
if [ ! -f "dl/$RUST_FILE" ]; then
    echo ">>> Pre-downloading source tarball from mirrors..."
    MIRRORS=(
        "https://mirrors.ustc.edu.cn/rust-static/dist/${RUST_FILE}"
        "https://mirrors.tuna.tsinghua.edu.cn/rustup/dist/${RUST_FILE}"
        "https://static.rust-lang.org/dist/${RUST_FILE}"
    )
    for mirror in "${MIRRORS[@]}"; do
        if wget --timeout=30 --tries=2 -O "dl/$RUST_FILE" "$mirror"; then
            echo "✅ Source tarball cached."
            break
        fi
    done
fi
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

# 取消原主题luci-theme-bootstrap 为默认主题
# sed -i '/set luci.main.mediaurlbase=\/luci-static\/bootstrap/d' feeds/luci/themes/luci-theme-bootstrap/root/etc/uci-defaults/30_luci-theme-bootstrap

# 删除原默认主题
# rm -rf package/lean/luci-theme-bootstrap

# 修改 argon 为默认主题
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
sed -i "s/luci-theme-bootstrap/luci-theme-argon/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
