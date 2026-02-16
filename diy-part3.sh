#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part3.sh
# Description: OpenWrt DIY script part 3 (After Update feeds)
#

echo "=========================================="
echo "执行自定义优化脚本 (diy-part3.sh)"
echo "=========================================="

# ---------------------------------------------------------
# 1. 环境路径识别与安全兜底
# ---------------------------------------------------------
TARGET_DIR="${1:-$(pwd)}"

check_openwrt_root() {
    [ -f "$1/scripts/feeds" ] && [ -f "$1/Makefile" ]
}

if check_openwrt_root "$TARGET_DIR"; then
    OPENWRT_ROOT="$TARGET_DIR"
    echo "✅ 自动识别 OpenWrt 根目录: $OPENWRT_ROOT"
else
    SUB_DIR=$(find . -maxdepth 2 -name "scripts" -type d | head -n 1 | xargs dirname 2>/dev/null)
    if [ -n "$SUB_DIR" ] && check_openwrt_root "$SUB_DIR"; then
        OPENWRT_ROOT="$(realpath "$SUB_DIR")"
        echo "✅ 在子目录找到 OpenWrt 根目录: $OPENWRT_ROOT"
    else
        # 强制兜底为当前目录，防止变量为空导致后续 rm -rf 出事故
        OPENWRT_ROOT=$(pwd)
        echo "⚠️ 警告: 未能智能识别，强制设定根目录为当前目录: $OPENWRT_ROOT"
    fi
fi

# ---------------------------------------------------------
# 2. 其他组件修复与调整
# ---------------------------------------------------------

# ----------------------------------------------------------------
# Rust 编译环境修复方案：替换为 ImmortalWrt 23.05 稳定版 (1.85.0)
# ----------------------------------------------------------------
echo "🔧 Fixing Rust environment..."

# 1. 删除当前 feeds 中可能老旧或损坏的 Rust 定义
# (不管原版是哪个版本，直接删掉，防止冲突)
rm -rf feeds/packages/lang/rust

# 2. 从 ImmortalWrt 23.05 分支拉取稳定版 Rust
# 选择 23.05 分支是因为它的 Rust 版本(1.85.0)既足够新，又非常稳定，且下载源有效
echo "   Cloning stable Rust from ImmortalWrt 23.05..."
git clone --depth 1 -b openwrt-23.05 https://github.com/immortalwrt/packages.git /tmp/temp_packages

# 3. 将下载的 Rust 搬运到当前编译环境
# 确保目录存在
mkdir -p feeds/packages/lang
cp -r /tmp/temp_packages/lang/rust feeds/packages/lang/

# 4. 清理临时文件
rm -rf /tmp/temp_packages

echo "✅ Rust replaced with version from 23.05 branch!"

# libxcrypt 编译报错修复 (忽略警告)
sed -i 's/CONFIGURE_ARGS +=/CONFIGURE_ARGS += --disable-werror/' feeds/packages/libs/libxcrypt/Makefile

# ---------------------------------------------------------
# 3. 菜单位置调整 (Tailscale & KSMBD)
# ---------------------------------------------------------
echo ">>> 调整插件菜单位置..."

# 5.1 Tailscale -> VPN
TS_FILES=$(grep -rl "admin/services/tailscale" package/tailscale 2>/dev/null)
if [ -n "$TS_FILES" ]; then
    for file in $TS_FILES; do
        [[ "$file" == *"acl.d"* ]] && continue
        sed -i 's|admin/services/tailscale|admin/vpn/tailscale|g' "$file"
        sed -i 's/"parent": "luci.services"/"parent": "luci.vpn"/g' "$file"
    done
    echo "✅ Tailscale 菜单已移动到 VPN"
fi

# 5.2 KSMBD -> NAS
# 扩大搜索范围，防止文件不在预期位置
KSMBD_FILES=$(grep -rl "admin/services/ksmbd" feeds package 2>/dev/null)
if [ -n "$KSMBD_FILES" ]; then
    for file in $KSMBD_FILES; do
        [[ "$file" == *"acl.d"* ]] && continue
        sed -i 's|admin/services/ksmbd|admin/nas/ksmbd|g' "$file"
        sed -i 's/"parent": "luci.services"/"parent": "luci.nas"/g' "$file"
        sed -i "s/'parent': 'luci.services'/'parent': 'luci.nas'/g" "$file"
    done
    echo "✅ KSMBD 菜单已移动到 NAS"
fi

# 修改默认 IP (192.168.30.1)
sed -i 's/192.168.1.1/192.168.30.1/g' package/base-files/files/bin/config_generate

# ----------------------------------------------------------------
# 5. 【最关键一步】强制重新注册所有 Feeds
# ----------------------------------------------------------------
# 这一步将修复 "does not exist" 的错误
echo "🔄 Re-installing all feeds..."
./scripts/feeds update -i
./scripts/feeds install -a -f

echo "🎉 DIY Part 2 Finished!"

echo "=========================================="
echo "自定义脚本执行完毕"
echo "=========================================="
