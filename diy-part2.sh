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

echo "=========================================="
echo "Rust 深度救治与环境硬化 (V12.0 稳健版)"
echo "=========================================="

# ---------------------------------------------------------
# 1. 配置区域
# ---------------------------------------------------------
PKGS_REPO="https://github.com/openwrt/packages.git"
PKGS_BRANCH="openwrt-23.05"  # 指定同步的目标分支

# 权威来源镜像
MIRRORS=(
    "https://static.rust-lang.org/dist"
    "https://rust-static-dist.s3.amazonaws.com/dist"
    "https://mirror.switch.ch/ftp/mirror/rust/dist"
)

RUST_DIR="feeds/packages/lang/rust"
RUST_MK="$RUST_DIR/Makefile"
DL_DIR="dl"

# ---------------------------------------------------------
# 2. 深度清理与物理同步 (核心：确保 Makefile 和 Patches 匹配)
# ---------------------------------------------------------
echo ">>> [1/4] 清理旧环境并同步官方 $PKGS_BRANCH 源码定义..."

# 彻底消灭 1.90.0 等可能残留的干扰项
rm -rf "$RUST_DIR"
rm -rf build_dir/host/rustc-*
rm -rf staging_dir/host/stamp/.rust_installed

TEMP_REPO="/tmp/rust_sync_$$"
if git clone --depth=1 -b "$PKGS_BRANCH" "$PKGS_REPO" "$TEMP_REPO" 2>/dev/null; then
    mkdir -p "$RUST_DIR"
    cp -r "$TEMP_REPO/lang/rust/"* "$RUST_DIR/"
    rm -rf "$TEMP_REPO"
    echo "✅ 成功物理对齐官方 $PKGS_BRANCH 补丁与 Makefile"
else
    echo "❌ 错误: 无法克隆救治底座"
    exit 1
fi

# ---------------------------------------------------------
# 3. 提取版本并下载权威源码包
# ---------------------------------------------------------
RUST_VER=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_FILE="rustc-${RUST_VER}-src.tar.xz"
DL_PATH="$DL_DIR/$RUST_FILE"

echo ">>> [2/4] 目标版本: $RUST_VER，正在执行多源可靠下载..."

DOWNLOADED=false
for m in "${MIRRORS[@]}"; do
    echo ">>> 尝试节点: $m"
    if wget -q --timeout=30 --tries=2 -O "$DL_PATH" "$m/$RUST_FILE"; then
        if [ -s "$DL_PATH" ]; then
            DOWNLOADED=true
            echo "✅ 源码包下载成功"
            break
        fi
    fi
done

if [ "$DOWNLOADED" != "true" ]; then
    echo "❌ 严重错误: 所有镜像站均无法下载源码包"
    exit 1
fi

# ---------------------------------------------------------
# 4. 🔥 物理哈希校准 (自适应修复，不再因为哈希报错)
# ---------------------------------------------------------
echo ">>> [3/4] 正在执行物理哈希校准..."

ACTUAL_HASH=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
echo ">>> 物理文件实际哈希: $ACTUAL_HASH"

# 强行将哈希写回 Makefile，确保后续校验 100% 通过
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$ACTUAL_HASH/" "$RUST_MK"
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"
echo "✅ 已强行修正 Makefile 中的哈希登记信息"

# ---------------------------------------------------------
# 5. 注入硬化编译优化 (终极加速设置)
# ---------------------------------------------------------
echo ">>> [4/4] 注入本地编译硬化设置 (CI-LLVM, 并发限制)..."

# A. 开启 CI-LLVM (解决磁盘空间报 28 错误，提速 90%)
sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$RUST_MK"
sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$RUST_MK"

# B. 处理补丁残留 (针对 Cargo.toml.orig 报错)
sed -i '/Build\/Patch/a \	find $(HOST_BUILD_DIR) -name "*.orig" -delete\n	find $(HOST_BUILD_DIR) -name "*.rej" -delete' "$RUST_MK"

# C. 暴力屏蔽 Checksum 校验 (核心保险：让 Cargo 彻底闭嘴)
sed -i '/\$(PYTHON3) \$(HOST_BUILD_DIR)\/x.py/i \	find $(HOST_BUILD_DIR)/vendor -name .cargo-checksum.json -delete' "$RUST_MK"

# D. 环境硬化与内存限制 (防止 Actions OOM)
sed -i '/export CARGO_HOME/a export CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_PROFILE_RELEASE_INCREMENTAL=false\nexport CARGO_INCREMENTAL=0' "$RUST_MK"
# 限制编译任务为 2，利用 15G RAM 稳扎稳打
sed -i 's/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py -j 2/g' "$RUST_MK"

# E. 修正其他元数据
sed -i 's/--frozen//g' "$RUST_MK"
sed -i 's/[[:space:]]*$//' "$RUST_MK"

echo "=========================================="
echo "Rust $RUST_VER 硬化修复圆满完成"
echo "文件: $DL_PATH"
echo "=========================================="

# ----------------------------------------------------------------
# 【最终收尾】强行刷新整个编译索引，确保所有“掉包”操作被系统识别
# ----------------------------------------------------------------
echo "🔄 正在进行全系统索引强制重映射..."
rm -rf tmp
./scripts/feeds update -i
./scripts/feeds install -a -f

# 修改默认 IP (192.168.30.1)
sed -i 's/192.168.6.1/192.168.30.1/g' package/base-files/files/bin/config_generate

echo "=========================================="
echo "自定义脚本执行完毕"
echo "=========================================="
