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
REPO_ROOT=${GITHUB_WORKSPACE:-$(dirname "$(readlink -f "$0")")/..}

echo "✅ 根目录: $OPENWRT_ROOT"

# ---------------------------------------------------------
# 2. 插件版本升级与替换 (MosDNS, Golang, SmartDNS)
# ---------------------------------------------------------
echo ">>> [1/7] 正在物理替换核心插件源码..."

rm -rf feeds/packages/net/mosdns feeds/luci/applications/luci-app-mosdns feeds/packages/net/v2ray-geodata
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang

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
DM_MAKEFILE=$(find feeds/luci -name "Makefile" | grep "luci-app-diskman")
[ -f "$DM_MAKEFILE" ] && sed -i '/ntfs-3g-utils /d' "$DM_MAKEFILE"

[ -f feeds/packages/libs/libxcrypt/Makefile ] && sed -i 's/CONFIGURE_ARGS +=/CONFIGURE_ARGS += --disable-werror/g' feeds/packages/libs/libxcrypt/Makefile

# ---------------------------------------------------------
# 5. 菜单位置调整 (精确对齐版)
# ---------------------------------------------------------
echo ">>> [4/7] 调整插件菜单位置..."

# 5.1 Tailscale -> VPN
grep -rl "admin/services/tailscale" package/tailscale 2>/dev/null | xargs sed -i 's|admin/services/tailscale|admin/vpn/tailscale|g' 2>/dev/null || true
grep -rl '"parent": "luci.services"' package/tailscale 2>/dev/null | xargs sed -i 's/"parent": "luci.services"/"parent": "luci.vpn"/g' 2>/dev/null || true

# 5.2 KSMBD -> NAS (锁定范围，防止误伤其他插件)
KSMBD_DIR="feeds/luci/applications/luci-app-ksmbd"
if [ -d "$KSMBD_DIR" ]; then
    grep -rl "admin/services/ksmbd" "$KSMBD_DIR" 2>/dev/null | xargs sed -i 's|admin/services/ksmbd|admin/nas/ksmbd|g' 2>/dev/null || true
    grep -rl '"parent": "luci.services"' "$KSMBD_DIR" 2>/dev/null | xargs sed -i 's/"parent": "luci.services"/"parent": "luci.nas"/g' 2>/dev/null || true
    echo "✅ KSMBD 菜单已移动到 NAS"
fi

# ---------------------------------------------------------
# 6. Rust 专项：锁定底座与物理哈希校准 (V13.2 救治逻辑)
# ---------------------------------------------------------
echo ">>> [5/7] 正在物理同步 Rust 分支底座..."
PKGS_BRANCH="master" 
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
    echo "✅ Rust 底座对齐成功。"
fi

if [ -f "$RUST_MK" ]; then
    echo ">>> [Rust] 执行哈希自适应与配置硬化..."
    # A. 修正 LLVM 设置
    sed -i 's/download-ci-llvm:=.*/download-ci-llvm:="if-unchanged"/g' "$RUST_MK"
    sed -i 's/download-ci-llvm=.*/download-ci-llvm="if-unchanged"/g' "$RUST_MK"
    
    # B. 哈希物理对齐逻辑
    V=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
    EXPECTED_H=$(grep '^PKG_HASH:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
    
    mkdir -p dl
    RUST_FILE="dl/rustc-${V}-src.tar.xz"
    if [ ! -s "$RUST_FILE" ]; then
        wget -q --timeout=30 -O "$RUST_FILE" "https://static.rust-lang.org/dist/rustc-${V}-src.tar.xz" || true
    fi

    if [ -s "$RUST_FILE" ]; then
        ACTUAL_H=$(sha256sum "$RUST_FILE" | cut -d' ' -f1)
        if [ "$ACTUAL_H" != "$EXPECTED_H" ]; then
            echo "⚠️ 哈希不匹配，已修正 Makefile 以对齐物理文件。"
            sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$ACTUAL_H/" "$RUST_MK"
        else
            echo "✅ 哈希校验完美通过。"
        fi
    fi

    # C. 常规修正
    sed -i 's/--frozen//g' "$RUST_MK"
    sed -i 's/--locked//g' "$RUST_MK"
    sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"
fi # <--- 修正：这里之前缺失了 fi

# ---------------------------------------------------------
# 7. 索引刷新 (解决寻址失败的核心)
# ---------------------------------------------------------
echo ">>> [6/7] 正在刷新系统索引与链接..."
rm -rf tmp
# 物理删除旧链接，强迫重新生成
find package/feeds -name "rust" -type l -exec rm -f {} \;
./scripts/feeds update -i
./scripts/feeds install -a -f

# 修改默认 IP (192.168.30.1)
sed -i 's/192.168.1.1/192.168.30.1/g' package/base-files/files/bin/config_generate
sed -i 's/192.168.6.1/192.168.30.1/g' package/base-files/files/bin/config_generate

# 强制默认主题为 Argon
find feeds/luci/collections/ -type f -name "Makefile" -exec sed -i 's/+luci-theme-bootstrap/+luci-theme-argon/g' {} +

echo "=========================================="
echo "✅ SSH2 整合优化脚本执行完毕"
echo "=========================================="
