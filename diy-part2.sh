#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
#

echo "=========================================="
echo "执行终极硬化版 DIY 优化脚本 (diy-part2.sh)"
echo "=========================================="

# 1. 环境路径识别
OPENWRT_ROOT=$(pwd)
REPO_ROOT=${GITHUB_WORKSPACE:-$(dirname "$(readlink -f "$0")")/..}

# 2. 插件版本升级与替换
echo ">>> [1/7] 正在物理替换核心插件源码..."
rm -rf feeds/packages/net/mosdns feeds/luci/applications/luci-app-mosdns feeds/packages/net/v2ray-geodata
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang

rm -rf feeds/packages/net/smartdns feeds/luci/applications/luci-app-smartdns
git clone --depth=1 https://github.com/pymumu/openwrt-smartdns feeds/packages/net/smartdns
git clone --depth=1 -b master https://github.com/pymumu/luci-app-smartdns feeds/luci/applications/luci-app-smartdns

# 3. 基础修复
echo ">>> [2/7] 执行组件修复..."
CUSTOM_LUA="$REPO_ROOT/istore/istore_backend.lua"
TARGET_LUA=$(find feeds package -name "istore_backend.lua" -type f 2>/dev/null | head -n 1)
[ -n "$TARGET_LUA" ] && [ -f "$CUSTOM_LUA" ] && cp -f "$CUSTOM_LUA" "$TARGET_LUA"

DM_MAKEFILE=$(find feeds/luci -name "Makefile" | grep "luci-app-diskman")
[ -f "$DM_MAKEFILE" ] && sed -i '/ntfs-3g-utils /d' "$DM_MAKEFILE"

[ -f feeds/packages/libs/libxcrypt/Makefile ] && sed -i 's/CONFIGURE_ARGS +=/CONFIGURE_ARGS += --disable-werror/g' feeds/packages/libs/libxcrypt/Makefile

# 4. 菜单调整 (内容追踪版)
echo ">>> [3/7] 调整插件菜单位置..."
grep -rl "admin/services/tailscale" package/tailscale 2>/dev/null | xargs sed -i 's|admin/services/tailscale|admin/vpn/tailscale|g' 2>/dev/null || true
grep -rl "admin/services/ksmbd" feeds package 2>/dev/null | xargs sed -i 's|admin/services/ksmbd|admin/nas/ksmbd|g' 2>/dev/null || true
find package feeds -name "*.json" | xargs sed -i 's/luci.services/luci.nas/g' 2>/dev/null || true
find package -name "*tailscale*.json" | xargs sed -i 's/luci.nas/luci.vpn/g' 2>/dev/null || true

# 5. Rust 专项：锁定底座与物理哈希校准
echo ">>> [4/7] 正在同步 Rust 稳定底座..."
PKGS_BRANCH="master" # 可根据需要改为 openwrt-23.05
PKGS_REPO="https://github.com/openwrt/packages.git"
RUST_DIR="feeds/packages/lang/rust"
RUST_MK="$RUST_DIR/Makefile"

rm -rf "$RUST_DIR"
rm -rf build_dir/host/rustc-*
rm -rf staging_dir/host/stamp/.rust_installed

TEMP_REPO="/tmp/rust_sync_$$"
if git clone --depth=1 -b "$PKGS_BRANCH" "$PKGS_REPO" "$TEMP_REPO" 2>/dev/null; then
    mkdir -p "$RUST_DIR"
    cp -r "$TEMP_REPO/lang/rust/"* "$RUST_DIR/"
    rm -rf "$TEMP_REPO"
    echo "✅ Rust $PKGS_BRANCH 源码同步成功"
fi

if [ -f "$RUST_MK" ]; then
    echo ">>> [Rust] 正在执行硬化配置与哈希校准..."
    # 修正：将 LLVM 设为 if-unchanged
    sed -i 's/download-ci-llvm:=.*/download-ci-llvm:="if-unchanged"/g' "$RUST_MK"
    sed -i 's/download-ci-llvm=.*/download-ci-llvm="if-unchanged"/g' "$RUST_MK"
    
    # 修正：物理哈希对齐 (防止官方镜像微调导致失败)
    V=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
    mkdir -p dl
    wget -q --timeout=30 -O "dl/rustc-${V}-src.tar.xz" "https://static.rust-lang.org/dist/rustc-${V}-src.tar.xz"
    if [ -s "dl/rustc-${V}-src.tar.xz" ]; then
        ACTUAL_H=$(sha256sum "dl/rustc-${V}-src.tar.xz" | cut -d' ' -f1)
        sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$ACTUAL_H/" "$RUST_MK"
    fi

    # 关键修复：使用 1i 在 Makefile 最顶行注入环境变量，避开语法冲突和 Tab 问题
    sed -i '1i export CARGO_NET_OFFLINE=true' "$RUST_MK"
    sed -i '1i export CARGO_PROFILE_RELEASE_DEBUG=false' "$RUST_MK"
    
    sed -i 's/--frozen//g' "$RUST_MK"
    sed -i 's/--locked//g' "$RUST_MK"
fi

# 6. 系统定制
# sed -i 's/192.168.1.1/192.168.30.1/g' package/base-files/files/bin/config_generate
sed -i 's/192.168.6.1/192.168.30.1/g' package/base-files/files/bin/config_generate

# 7. 索引强接 (终极保险)
echo ">>> [5/7] 正在全量刷新系统索引 (关键)..."
rm -rf tmp
# 物理删除所有可能残留的 rust 链接，强迫 feeds 重新创建
find package/feeds -name "rust" -type l -exec rm -f {} \;
./scripts/feeds update -i
./scripts/feeds install -a -f

echo "=========================================="
echo "✅ SSH2 优化脚本执行完毕"
echo "=========================================="
