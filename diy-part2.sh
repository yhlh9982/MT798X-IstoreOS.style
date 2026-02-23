#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

echo "=========================================="
echo "执行自定义优化脚本 (diy-part2.sh)"
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
# 3. QuickStart 首页温度显示修复
# ---------------------------------------------------------
echo ">>> 执行 QuickStart 修复..."
# 获取 GitHub Workspace 根目录 (diy-part2.sh 在 openwrt/ 下运行)
REPO_ROOT=$(dirname "$(readlink -f "$0")")/.. 
# 如果在 Actions 环境中，直接使用环境变量更稳
if [ -n "$GITHUB_WORKSPACE" ]; then
    REPO_ROOT="$GITHUB_WORKSPACE"
fi

CUSTOM_LUA="$REPO_ROOT/istore/istore_backend.lua"
# 查找目标文件 (feeds 和 package 都找)
TARGET_LUA=$(find feeds package -name "istore_backend.lua" -type f 2>/dev/null | head -n 1)

if [ -n "$TARGET_LUA" ]; then
    echo "定位到目标文件: $TARGET_LUA"
    if [ -f "$CUSTOM_LUA" ]; then
        echo "正在覆盖自定义文件..."
        cp -f "$CUSTOM_LUA" "$TARGET_LUA"
        if cmp -s "$CUSTOM_LUA" "$TARGET_LUA"; then
             echo "✅ QuickStart 修复成功"
        else
             echo "❌ 错误: 文件复制校验失败"
        fi
    else
        echo "⚠️ 警告: 仓库中未找到自定义文件 $CUSTOM_LUA"
    fi
else
    echo "⚠️ 警告: 未在源码中找到 istore_backend.lua，跳过修复"
fi

# ---------------------------------------------------------
# 4. 其他组件修复与调整
# ---------------------------------------------------------

# DiskMan 依赖修复
DM_MAKEFILE=$(find feeds/luci -name "Makefile" | grep "luci-app-diskman")
if [ -f "$DM_MAKEFILE" ]; then
    sed -i '/ntfs-3g-utils /d' "$DM_MAKEFILE"
    echo "✅ DiskMan 依赖修复完成"
fi

# libxcrypt 编译报错修复 (忽略警告)
sed -i 's/CONFIGURE_ARGS +=/CONFIGURE_ARGS += --disable-werror/' feeds/packages/libs/libxcrypt/Makefile

# 升级替换 mosdns
# drop mosdns and v2ray-geodata packages that come with the source
find ./ | grep Makefile | grep v2ray-geodata | xargs rm -f
find ./ | grep Makefile | grep mosdns | xargs rm -f

git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# requires golang 1.24.x or latest version
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 24.x feeds/packages/lang/golang

# 升级替换 smartdns
WORKINGDIR="`pwd`/feeds/packages/net/smartdns"
mkdir $WORKINGDIR -p
rm $WORKINGDIR/* -fr
wget https://github.com/pymumu/openwrt-smartdns/archive/master.zip -O $WORKINGDIR/master.zip
unzip $WORKINGDIR/master.zip -d $WORKINGDIR
mv $WORKINGDIR/openwrt-smartdns-master/* $WORKINGDIR/
rmdir $WORKINGDIR/openwrt-smartdns-master
rm $WORKINGDIR/master.zip

LUCIBRANCH="master" #更换此变量
WORKINGDIR="`pwd`/feeds/luci/applications/luci-app-smartdns"
mkdir $WORKINGDIR -p
rm $WORKINGDIR/* -fr
wget https://github.com/pymumu/luci-app-smartdns/archive/${LUCIBRANCH}.zip -O $WORKINGDIR/${LUCIBRANCH}.zip
unzip $WORKINGDIR/${LUCIBRANCH}.zip -d $WORKINGDIR
mv $WORKINGDIR/luci-app-smartdns-${LUCIBRANCH}/* $WORKINGDIR/
rmdir $WORKINGDIR/luci-app-smartdns-${LUCIBRANCH}
rm $WORKINGDIR/${LUCIBRANCH}.zip

# ---------------------------------------------------------
# 5. 菜单位置调整 (Tailscale & KSMBD)
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

set -e

# 1. 配置区域  
# 可选packages 分支  openwrt-23.05  目前rust版本为 1.85.0 ，为最稳定的版本，但是编译时间会延长
# 可选packages 分支  openwrt-24.10  目前rust版本为 1.90.0   
# 可选packages 分支  master  目前rust版本为 1.90.0  此后的分支 rust 版本可能不与24.10 同时更新版本，如果需要更改，需要核实
# 可选packages 分支  openwrt-25.12  目前rust版本为 1.90.0
#  packages 核实的地址 ：https://github.com/openwrt/packages/blob/openwrt-24.10/lang/rust/Makefile

echo "=========================================="
echo "Rust 终极救治脚本 V16.0 (环境隔离版)"
echo "=========================================="

# 1. 基础配置
PKGS_REPO="https://github.com/openwrt/packages.git"
PKGS_BRANCH="master"  # 强制回滚到最稳的补丁集
RUST_OFFICIAL_URL="https://static.rust-lang.org/dist"

OPENWRT_ROOT=$(pwd)
RUST_DIR="$OPENWRT_ROOT/feeds/packages/lang/rust"
RUST_MK="$RUST_DIR/Makefile"
DL_DIR="$OPENWRT_ROOT/dl"

# ==========================================
# 第一步：彻底物理清洗 (确保无残留)
# ==========================================
echo ">>> [1/5] 清洗环境并同步 $PKGS_BRANCH 源码定义..."
rm -rf "$RUST_DIR"
rm -rf "$OPENWRT_ROOT/build_dir/host/rustc-*"
rm -rf "$OPENWRT_ROOT/staging_dir/host/stamp/.rust_installed"
# 清除宿主机的 Rust 缓存干扰
rm -rf "$OPENWRT_ROOT/dl/cargo" 

TEMP_REPO="/tmp/rust_nuke_v16"
git clone --depth=1 -b "$PKGS_BRANCH" "$PKGS_REPO" "$TEMP_REPO" 2>/dev/null
mkdir -p "$RUST_DIR"
cp -r "$TEMP_REPO/lang/rust/"* "$RUST_DIR/"
rm -rf "$TEMP_REPO"

# ==========================================
# 第二步：物理哈希校准
# ==========================================
V=$(grep -E '^PKG_VERSION[:=]+' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_FILE="rustc-${V}-src.tar.xz"
DL_PATH="$DL_DIR/$RUST_FILE"

echo ">>> [2/5] 确保权威源码包下载: $V"
mkdir -p "$DL_DIR"
wget -q --timeout=60 --tries=3 -O "$DL_PATH" "$RUST_OFFICIAL_URL/$RUST_FILE"

FINAL_H=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
sed -i "s/^PKG_HASH[:=].*/PKG_HASH:=$FINAL_H/" "$RUST_MK"
echo "✅ 哈希物理对齐: $FINAL_H"

# ==========================================
# 第三步：Makefile 深度硬化（解决 .orig 报错的根源）
# ==========================================
echo ">>> [3/5] 正在执行 Makefile 深度“硬化”手术..."

# 1. 核心修复：禁止 patch 工具产生备份文件 (.orig)
# 这是解决 Cargo 洁癖的最底层手段，直接在 Makefile 头部注入
sed -i '1i export QUILT_PATCH_OPTS:=--no-backup' "$RUST_MK"
sed -i '1i export PATCH_GET:=0' "$RUST_MK"

# 2. 开启 CI-LLVM
sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$RUST_MK"
sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$RUST_MK"

# 3. 注入暴力清理逻辑（覆盖所有关键节点）
# 定义清理命令
CLEAN_LOGIC="find \$(HOST_BUILD_DIR) -name \"*.orig\" -delete -o -name \"*.rej\" -delete -o -name \".cargo-checksum.json\" -delete"

# 在打补丁后执行清理
sed -i "/Build\/Patch/a \	$CLEAN_LOGIC" "$RUST_MK"

# 在执行 python 编译命令前执行清理，并加入 RUST_BACKTRACE 调试
sed -i "s|python3 \$(HOST_BUILD_DIR)/x.py|export RUST_BACKTRACE=1 \&\& $CLEAN_LOGIC \&\& python3 \$(HOST_BUILD_DIR)/x.py|g" "$RUST_MK"

# 4. 强制单线程编译 (虽然慢，但能看到真实报错，且防止内存崩溃)
# 先尝试用 -j 1 确保 100% 成功率
sed -i "s/x.py/x.py -j 1/g" "$RUST_MK"

# 5. 移除限制参数
sed -i 's/--frozen//g' "$RUST_MK"
sed -i 's/--locked//g' "$RUST_MK"

# ==========================================
# 第四步：索引全量重映射
# ==========================================
echo ">>> [4/5] 刷新编译索引..."
rm -rf "$OPENWRT_ROOT/tmp"
./scripts/feeds update -i
./scripts/feeds install -a -f

# ==========================================
# 第五步：错误预警（如果在本地运行，建议直接看输出）
# ==========================================
echo ">>> [5/5] Makefile 硬化完成。即将开始的 Rust 编译已处于隔离状态。"
echo ">>> 如果依然失败，请在 Actions 日志中向上搜索 'error:' 关键字。"

echo "=========================================="
echo "✅ Rust V16.0 硬化版配置完毕"
echo "=========================================="

# ==========================================
# 额外：最终一致性核查 (可选，用于在日志中确认)
# ==========================================
echo ">>> 最终环境核对:"
echo "Rust 版本: $(grep '^PKG_VERSION:=' $RUST_MK | cut -d'=' -f2)"
echo "Golang 路径: $(ls -d feeds/packages/lang/golang 2>/dev/null || echo '缺失')"
echo "MosDNS 路径: $(find package feeds -name "mosdns" -type d | head -1)"

# 修改默认 IP (192.168.30.1)
sed -i 's/192.168.6.1/192.168.30.1/g' package/base-files/files/bin/config_generate

echo "=========================================="
echo "自定义脚本执行完毕"
echo "=========================================="
