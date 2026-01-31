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

echo "=========================================="
echo " 修复 Rust
echo "=========================================="

# 拉取官方 Makefile 提取版本信息
curl -fsSL \
  https://raw.githubusercontent.com/immortalwrt/packages/openwrt-24.10/lang/rust/Makefile \
  -o /tmp/rust-imm.mk

VER=$(grep '^PKG_VERSION:=' /tmp/rust-imm.mk | cut -d'=' -f2 | tr -d ' ')
HASH=$(grep '^PKG_HASH:=' /tmp/rust-imm.mk | cut -d'=' -f2 | tr -d ' ')

echo "目标版本: $VER"
echo "目标哈希: $HASH"

# 同时更新本地 Makefile（确保版本一致）
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$VER/" feeds/packages/lang/rust/Makefile
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$HASH/" feeds/packages/lang/rust/Makefile

# 清理旧的 Rust 包（如果有）
echo ">>> 清理旧版本 Rust 包..."
rm -f dl/rustc-1.*-src.tar.xz* 2>/dev/null || true

# 预下载目标版本
RUST_FILE="rustc-${VER}-src.tar.xz"
RUST_URL="https://static.rust-lang.org/dist/${RUST_FILE}"

echo ">>> 下载 Rust $VER..."
wget -q --show-progress -O "dl/${RUST_FILE}" "$RUST_URL" || \
curl -fSL -o "dl/${RUST_FILE}" "$RUST_URL"

# 验证哈希
echo ">>> 验证文件完整性..."
DL_HASH=$(sha256sum "dl/${RUST_FILE}" | cut -d' ' -f1)

if [ "$DL_HASH" != "$HASH" ]; then
    echo "❌ 哈希不匹配！"
    echo "期望: $HASH"
    echo "实际: $DL_HASH"
    rm -f "dl/${RUST_FILE}"
    exit 1
fi

echo "✅ Rust $VER 已就绪: dl/${RUST_FILE}"

# 清理临时文件
rm -f /tmp/rust-imm.mk

echo ">>> Rust 准备完成"

echo "=========================================="
echo "Rust 修复完成"
echo "=========================================="

# =========================================================
# 智能修复脚本（兼容 package/ 和 feeds/）
# =========================================================

REPO_ROOT=$(dirname "$(readlink -f "$0")")
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
