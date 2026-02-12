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
echo "Rust 修复（高稳定性 / 高妥协性模式）"
echo "=========================================="

# 确保在源码根目录执行
[ -f "scripts/feeds" ] || { echo "❌ Error: Not in OpenWrt root"; exit 1; }

RUST_MK="feeds/packages/lang/rust/Makefile"
REF_MK="/tmp/rust_ref.mk"

#--------------------------------------------------
# 1. 确保 Rust Makefile 存在
#--------------------------------------------------
if [ ! -f "$RUST_MK" ]; then
    echo ">>> Rust Makefile missing, syncing from ImmortalWrt packages..."
    mkdir -p feeds/packages/lang

    TEMP_DIR=$(mktemp -d)
    if git clone --depth=1 https://github.com/immortalwrt/packages.git "$TEMP_DIR"; then
        cp -r "$TEMP_DIR/lang/rust" feeds/packages/lang/
    else
        echo "❌ Failed to clone ImmortalWrt packages"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    rm -rf "$TEMP_DIR"
fi

#--------------------------------------------------
# 2. 获取权威 Rust 版本信息（多级 fallback）
#--------------------------------------------------
IMM_URL="https://raw.githubusercontent.com/openwrt/packages/openwrt-24.10/lang/rust/Makefile"

echo ">>> Fetching reference Rust Makefile..."

if ! curl -fsSL "$IMM_URL" -o "$REF_MK"; then
    echo "⚠️ Failed to fetch remote Makefile, falling back to local one"
    cp "$RUST_MK" "$REF_MK"
fi

RUST_VER=$(grep '^PKG_VERSION:=' "$REF_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_HASH=$(grep '^PKG_HASH:=' "$REF_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')

if [ -z "$RUST_VER" ]; then
    echo "❌ Unable to determine Rust version"
    exit 1
fi

echo ">>> Detected Rust version: $RUST_VER"

#--------------------------------------------------
# 3. 同步版本 / Hash，并强制源码编译
#--------------------------------------------------
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$RUST_VER/" "$RUST_MK"
[ -n "$RUST_HASH" ] && sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$RUST_HASH/" "$RUST_MK"

# 关闭 CI LLVM，强制本地构建
sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$RUST_MK"

# 修正源码地址
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"

echo "✅ Rust Makefile adjusted for source build"

#--------------------------------------------------
# 4. 预下载 Rust 源码（多镜像 + 校验）
#--------------------------------------------------
RUST_FILE="rustc-${RUST_VER}-src.tar.xz"
DL_PATH="dl/$RUST_FILE"

mkdir -p dl

if [ ! -s "$DL_PATH" ]; then
    echo ">>> Pre-downloading Rust source tarball..."

    MIRRORS=(
        "https://mirrors.ustc.edu.cn/rust-static/dist/${RUST_FILE}"
        "https://mirrors.tuna.tsinghua.edu.cn/rustup/dist/${RUST_FILE}"
        "https://static.rust-lang.org/dist/${RUST_FILE}"
    )

    DOWNLOADED=false
    for mirror in "${MIRRORS[@]}"; do
        echo ">>> Trying $mirror"
        rm -f "$DL_PATH"
        if wget --timeout=30 --tries=3 -O "$DL_PATH" "$mirror"; then
            if [ -s "$DL_PATH" ]; then
                DOWNLOADED=true
                echo "✅ Rust source cached successfully"
                break
            fi
        fi
    done

    if [ "$DOWNLOADED" != "true" ]; then
        echo "❌ Failed to download Rust source from all mirrors"
        exit 1
    fi
else
    echo ">>> Rust source already cached"
fi

echo "=========================================="
echo "Rust 修复完成：$RUST_VER"
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
