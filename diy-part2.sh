#!/bin/bash
# diy-part2.sh

echo "=========================================="
echo "执行 SSH2: 系统定制与 Rust 底座对齐"
echo "=========================================="

# 1. 环境路径识别
OPENWRT_ROOT=$(pwd)
REPO_ROOT=${GITHUB_WORKSPACE:-$(dirname "$(readlink -f "$0")")/..}

# 2. 核心插件替换 (MosDNS, Golang, SmartDNS)
echo ">>> [1/5] 正在物理替换核心插件源码..."
rm -rf feeds/packages/net/mosdns feeds/luci/applications/luci-app-mosdns feeds/packages/net/v2ray-geodata
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang

rm -rf feeds/packages/net/smartdns feeds/luci/applications/luci-app-smartdns
git clone --depth=1 https://github.com/pymumu/openwrt-smartdns feeds/packages/net/smartdns
git clone --depth=1 -b master https://github.com/pymumu/luci-app-smartdns feeds/luci/applications/luci-app-smartdns

# 3. 菜单位置调整 (内容追踪版)
echo ">>> [2/5] 调整插件菜单位置..."
grep -rl "admin/services/tailscale" package/tailscale 2>/dev/null | xargs sed -i 's|admin/services/tailscale|admin/vpn/tailscale|g' 2>/dev/null || true
grep -rl "admin/services/ksmbd" feeds package 2>/dev/null | xargs sed -i 's|admin/services/ksmbd|admin/nas/ksmbd|g' 2>/dev/null || true
find package feeds -name "*.json" | xargs sed -i 's/luci.services/luci.nas/g' 2>/dev/null || true
find package -name "*tailscale*.json" | xargs sed -i 's/luci.nas/luci.vpn/g' 2>/dev/null || true

# 4. Rust 专项：回滚底座与 Makefile 硬化
echo ">>> [3/5] 正在同步 Rust 稳定底座 (Master 分支)..."
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
    echo "✅ Rust 底座对齐成功"
fi

if [ -f "$RUST_MK" ]; then
    echo ">>> [Rust] 正在应用硬化配置 (安全追加模式)..."
    
    # 1. 修正 LLVM 设置
    sed -i 's/download-ci-llvm:=.*/download-ci-llvm:="if-unchanged"/g' "$RUST_MK"
    sed -i 's/download-ci-llvm=.*/download-ci-llvm="if-unchanged"/g' "$RUST_MK"
    
    # 2. 【核心修复】：使用 printf 追加环境变量到临时文件再覆盖，避开 sed 语法坑
    # 这能保证 Makefile 第一行绝对合法，消灭 @ 警告
    printf "export CARGO_NET_OFFLINE=true\nexport CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_INCREMENTAL=0\n" > "$RUST_MK.tmp"
    cat "$RUST_MK" >> "$RUST_MK.tmp"
    mv "$RUST_MK.tmp" "$RUST_MK"

    # 3. 移除锁定参数
    sed -i 's/--frozen//g' "$RUST_MK"
    sed -i 's/--locked//g' "$RUST_MK"
fi

# 5. 系统定制
# sed -i 's/192.168.1.1/192.168.30.1/g' package/base-files/files/bin/config_generate
sed -i 's/192.168.6.1/192.168.30.1/g' package/base-files/files/bin/config_generate
find feeds/luci/collections/ -type f -name "Makefile" -exec sed -i 's/+luci-theme-bootstrap/+luci-theme-argon/g' {} +

# 6. 索引强接 (核心收尾)
echo ">>> [4/5] 正在全量强制刷新系统索引与链接..."
# 物理删除旧链接，强迫重新生成
find package/feeds -name "rust" -type l -exec rm -f {} \;
rm -rf tmp
./scripts/feeds update -i
./scripts/feeds install -a -f

echo "=========================================="
echo "✅ SSH2 整合优化脚本执行完毕"
echo "=========================================="
