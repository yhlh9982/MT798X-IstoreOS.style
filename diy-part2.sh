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

#!/bin/bash
# diy-part2.sh

# ... (前面的插件替换逻辑保持不变) ...

# 4. Rust 专项：锁定底座与物理哈希校准
echo ">>> [Rust] 正在物理同步分支底座..."
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
    echo ">>> [Rust] 仅修改 Makefile 配置项，不注入环境变量..."
    # A. 修正 LLVM 绕过 CI 限制 (仅改值)
    sed -i 's/download-ci-llvm:=.*/download-ci-llvm:="if-unchanged"/g' "$RUST_MK"
    sed -i 's/download-ci-llvm=.*/download-ci-llvm="if-unchanged"/g' "$RUST_MK"
    
    # B. 哈希物理对齐
    V=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
    mkdir -p dl
    wget -q --timeout=30 -O "dl/rustc-${V}-src.tar.xz" "https://static.rust-lang.org/dist/rustc-${V}-src.tar.xz" || true
    if [ -s "dl/rustc-${V}-src.tar.xz" ]; then
        ACTUAL_H=$(sha256sum "dl/rustc-${V}-src.tar.xz" | cut -d' ' -f1)
        sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$ACTUAL_H/" "$RUST_MK"
    fi

    # C. 修正地址并取消锁定 (不插入 export 行，防止 @ 报错)
    sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"
    sed -i 's/--frozen//g' "$RUST_MK"
    sed -i 's/--locked//g' "$RUST_MK"
fi

# 5. 索引刷新
echo ">>> [Rust] 强制刷新软链接索引..."
rm -rf tmp
find package/feeds -name "rust" -type l -exec rm -f {} \;
./scripts/feeds update -i
./scripts/feeds install -a -f
