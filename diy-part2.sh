#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
#

echo "=========================================="
echo "执行终极硬化版 DIY 优化脚本 (diy-part2.sh)"
echo "=========================================="

# ---------------------------------------------------------
# 1. 环境路径识别
# ---------------------------------------------------------
OPENWRT_ROOT=$(pwd)
# 获取 GitHub Workspace 根目录
REPO_ROOT=${GITHUB_WORKSPACE:-$(dirname "$(readlink -f "$0")")/..}

echo "✅ 根目录: $OPENWRT_ROOT"

# ---------------------------------------------------------
# 2. 插件版本升级与替换 (MosDNS, Golang, SmartDNS)
# ---------------------------------------------------------
echo ">>> [1/7] 正在物理替换核心插件源码..."

# 2.1 彻底清理 MosDNS & v2ray-geodata
rm -rf feeds/packages/net/mosdns feeds/luci/applications/luci-app-mosdns feeds/packages/net/v2ray-geodata
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# 2.2 Golang 强制替换为 1.24.x (sbwml 版)
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang

# 2.3 SmartDNS 替换 (改用 git clone 更稳健)
rm -rf feeds/packages/net/smartdns feeds/luci/applications/luci-app-smartdns
git clone --depth=1 https://github.com/pymumu/openwrt-smartdns feeds/packages/net/smartdns
git clone --depth=1 -b master https://github.com/pymumu/luci-app-smartdns feeds/luci/applications/luci-app-smartdns

# ---------------------------------------------------------
# 3. QuickStart 首页温度显示修复
# ---------------------------------------------------------
echo ">>> [2/7] 执行 QuickStart 修复..."
CUSTOM_LUA="$REPO_ROOT/istore/istore_backend.lua"
TARGET_LUA=$(find feeds package -name "istore_backend.lua" -type f 2>/dev/null | head -n 1)

if [ -n "$TARGET_LUA" ] && [ -f "$CUSTOM_LUA" ]; then
    cp -f "$CUSTOM_LUA" "$TARGET_LUA"
    echo "✅ QuickStart 修复覆盖成功"
fi

# ---------------------------------------------------------
# 4. 其他组件修复与硬化
# ---------------------------------------------------------
echo ">>> [3/7] 正在修复组件依赖..."

# DiskMan 依赖修复
DM_MAKEFILE=$(find feeds/luci -name "Makefile" | grep "luci-app-diskman")
[ -f "$DM_MAKEFILE" ] && sed -i '/ntfs-3g-utils /d' "$DM_MAKEFILE"

# libxcrypt 编译报错修复 (忽略警告)
[ -f feeds/packages/libs/libxcrypt/Makefile ] && sed -i 's/CONFIGURE_ARGS +=/CONFIGURE_ARGS += --disable-werror/g' feeds/packages/libs/libxcrypt/Makefile

# ---------------------------------------------------------
# 5. 菜单位置调整 (内容追踪版)
# ---------------------------------------------------------
echo ">>> [4/7] 调整插件菜单位置..."

# 5.1 Tailscale -> VPN
grep -rl "admin/services/tailscale" package/tailscale 2>/dev/null | xargs sed -i 's|admin/services/tailscale|admin/vpn/tailscale|g' 2>/dev/null || true
grep -rl '"parent": "luci.services"' package/tailscale 2>/dev/null | xargs sed -i 's/"parent": "luci.services"/"parent": "luci.vpn"/g' 2>/dev/null || true

# 5.2 KSMBD -> NAS
grep -rl "admin/services/ksmbd" feeds package 2>/dev/null | xargs sed -i 's|admin/services/ksmbd|admin/nas/ksmbd|g' 2>/dev/null || true
grep -rl '"parent": "luci.services"' feeds package 2>/dev/null | xargs sed -i 's/"parent": "luci.services"/"parent": "luci.nas"/g' 2>/dev/null || true

# =========================================================
# Rust 专项：回滚底座与哈希校准 (SSH2 部分)
# =========================================================
echo ">>> [Rust] 正在同步底座并执行基础配置..."

PKGS_BRANCH="master" # 可根据需要改为 openwrt-23.05
PKGS_REPO="https://github.com/openwrt/packages.git"
RUST_DIR="feeds/packages/lang/rust"
RUST_MK="$RUST_DIR/Makefile"

# 1. 物理同步 (确保 Makefile 和补丁配套)
rm -rf "$RUST_DIR"
rm -rf build_dir/host/rustc-*
rm -rf staging_dir/host/stamp/.rust_installed

TEMP_REPO="/tmp/rust_sync_$$"
if git clone --depth=1 -b "$PKGS_BRANCH" "$PKGS_REPO" "$TEMP_REPO" 2>/dev/null; then
    mkdir -p "$RUST_DIR"
    cp -r "$TEMP_REPO/lang/rust/"* "$RUST_DIR/"
    rm -rf "$TEMP_REPO"
    echo "✅ Rust 底座同步成功。"
fi

# 2. 极简硬化 Makefile (仅修改值，不注入新行)
if [ -f "$RUST_MK" ]; then
    # 修正 LLVM 为 if-unchanged (绕过 Rust 1.90 的 CI 限制)
    sed -i 's/download-ci-llvm:=.*/download-ci-llvm:="if-unchanged"/g' "$RUST_MK"
    sed -i 's/download-ci-llvm=.*/download-ci-llvm="if-unchanged"/g' "$RUST_MK"
    
    # 物理哈希校准 (自适应官方镜像)
    V=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
    mkdir -p dl
    wget -q --timeout=30 -O "dl/rustc-${V}-src.tar.xz" "https://static.rust-lang.org/dist/rustc-${V}-src.tar.xz" || true
    if [ -s "dl/rustc-${V}-src.tar.xz" ]; then
        ACTUAL_H=$(sha256sum "dl/rustc-${V}-src.tar.xz" | cut -d' ' -f1)
        sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$ACTUAL_H/" "$RUST_MK"
        echo "✅ 哈希校准完成: $ACTUAL_H"
    fi

    # 移除锁定参数
    sed -i 's/--frozen//g' "$RUST_MK"
    sed -i 's/--locked//g' "$RUST_MK"
fi

# 3. 强制刷新索引 (关键：确保 SSH3 寻址正常)
echo "🔄 正在刷新全系统索引..."
rm -rf tmp
# 物理清理可能存在的坏链接
find package/feeds -name "rust" -type l -exec rm -f {} \;
./scripts/feeds update -i
./scripts/feeds install -a -f
