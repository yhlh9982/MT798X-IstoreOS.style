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

echo "=========================================="
echo "Rust 修复脚本 (V4.2 强制同步版)"
echo "=========================================="

# 1. 配置区域
# ---------------------------------------------------------
# 强制指定要使用的官方分支（在此修改你想要的分支）
PKGS_BRANCH="openwrt-23.05"
PKGS_REPO="https://github.com/openwrt/packages.git"

# 全球三大权威镜像源
SOURCE_1="https://static.rust-lang.org/dist"
SOURCE_2="https://rust-static-dist.s3.amazonaws.com/dist"
SOURCE_3="https://mirror.switch.ch/ftp/mirror/rust/dist"
# ---------------------------------------------------------

# 2. 路径识别
TARGET_DIR="${1:-$(pwd)}"
check_openwrt_root() { [ -f "$1/scripts/feeds" ] && [ -f "$1/Makefile" ]; }

if check_openwrt_root "$TARGET_DIR"; then
    OPENWRT_ROOT=$(readlink -f "$TARGET_DIR")
else
    SUB_DIR=$(find . -maxdepth 2 -name "scripts" -type d | head -n 1 | xargs dirname 2>/dev/null)
    [ -n "$SUB_DIR" ] && check_openwrt_root "$SUB_DIR" && OPENWRT_ROOT=$(readlink -f "$SUB_DIR") || { echo "❌ 错误: 未找到 OpenWrt 根目录"; exit 1; }
fi

RUST_DIR="$OPENWRT_ROOT/feeds/packages/lang/rust"
RUST_MK="$RUST_DIR/Makefile"
DL_DIR="$OPENWRT_ROOT/dl"
mkdir -p "$DL_DIR"

echo "✅ 运行环境: $OPENWRT_ROOT"

# --- 辅助函数：应用硬化优化 ---
apply_hardening() {
    local mk=$1
    echo ">>> 正在注入硬化优化 (CI-LLVM, 暴力去校验, -j 2)..."
    sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$mk"
    sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$mk"
    sed -i '/Build\/Patch/a \	find $(HOST_BUILD_DIR) -name "*.orig" -delete\n	find $(HOST_BUILD_DIR) -name "*.rej" -delete' "$mk"
    sed -i '/\$(PYTHON3) \$(HOST_BUILD_DIR)\/x.py/i \	find $(HOST_BUILD_DIR)/vendor -name .cargo-checksum.json -delete' "$mk"
    sed -i '/export CARGO_HOME/a export CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_PROFILE_RELEASE_INCREMENTAL=false\nexport CARGO_INCREMENTAL=0' "$mk"
    sed -i 's/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py -j 2/g' "$mk"
    sed -i 's/--frozen//g' "$mk"
    sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$mk"
}

# --- 核心函数：共识下载与哈希修正 ---
consensus_check() {
    local ver=$1
    local expected_h=$2
    local file="rustc-${ver}-src.tar.xz"
    
    echo ">>> 启动三方并发下载: 版本 $ver"
    wget -q --timeout=30 --tries=2 -O "$DL_DIR/${file}.1" "$SOURCE_1/$file" &
    wget -q --timeout=30 --tries=2 -O "$DL_DIR/${file}.2" "$SOURCE_2/$file" &
    wget -q --timeout=30 --tries=2 -O "$DL_DIR/${file}.3" "$SOURCE_3/$file" &
    wait

    local h1=$(sha256sum "$DL_DIR/${file}.1" 2>/dev/null | cut -d' ' -f1)
    local h2=$(sha256sum "$DL_DIR/${file}.2" 2>/dev/null | cut -d' ' -f1)
    local h3=$(sha256sum "$DL_DIR/${file}.3" 2>/dev/null | cut -d' ' -f1)

    if [ "$h1" == "$expected_h" ] || [ "$h2" == "$expected_h" ] || [ "$h3" == "$expected_h" ]; then
        echo "✅ 级别 1: 发现匹配 Makefile 的权威源码包。"
        [ "$h1" == "$expected_h" ] && mv "$DL_DIR/${file}.1" "$DL_DIR/$file"
        [ "$h2" == "$expected_h" ] && [ ! -f "$DL_DIR/$file" ] && mv "$DL_DIR/${file}.2" "$DL_DIR/$file"
        [ "$h3" == "$expected_h" ] && [ ! -f "$DL_DIR/$file" ] && mv "$DL_DIR/${file}.3" "$DL_DIR/$file"
        rm -f "$DL_DIR/${file}."*
        return 0
    fi

    if [ -n "$h1" ] && [ "$h1" == "$h2" ] && [ "$h2" == "$h3" ]; then
        echo "⚠️  级别 2: 三方一致但与 Makefile 不同，修正哈希为 $h1"
        sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$h1/" "$RUST_MK"
        mv "$DL_DIR/${file}.1" "$DL_DIR/$file"
        rm -f "$DL_DIR/${file}."*
        return 0
    fi
    rm -f "$DL_DIR/${file}."*
    return 1
}

# =========================================================
# 强制执行流程：先同步，再下载
# =========================================================

# 第一步：强制同步指定的分支定义（覆盖当前环境已有的 Rust）
echo "🚨 正在强制同步官方 $PKGS_BRANCH 分支的 Rust 定义..."
rm -rf "$RUST_DIR"
mkdir -p "$RUST_DIR"
# 清理旧的编译残余
rm -rf "$OPENWRT_ROOT/build_dir/host/rustc-*"
rm -rf "$OPENWRT_ROOT/build_dir/target-*/host/rustc-*"

TEMP="/tmp/rust_force_sync_$$"
if git clone --depth=1 -b "$PKGS_BRANCH" "$PKGS_REPO" "$TEMP"; then
    cp -r "$TEMP/lang/rust/"* "$RUST_DIR/"
    rm -rf "$TEMP"
    echo "✅ 分支同步完成。"
else
    echo "❌ 错误: 无法连接仓库强制同步。"
    exit 1
fi

# 第二步：基于新同步的 Makefile 执行下载校验
if [ -f "$RUST_MK" ]; then
    V=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
    H=$(grep '^PKG_HASH:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
    if consensus_check "$V" "$H"; then
        apply_hardening "$RUST_MK"
        echo "✅ Rust 救治与强制同步优化已全部完成。"
    else
        echo "❌ 严重错误: 下载校验失败。"
        exit 1
    fi
else
    echo "❌ 错误: 未能找到 Makefile 文件。"
    exit 1
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

# ----------------------------------------------------------------
# 6. 【最关键一步】强制重新注册所有 Feeds
# ----------------------------------------------------------------
# 这一步将修复 "does not exist" 的错误
echo "🔄 Re-installing all feeds..."
./scripts/feeds update -i
./scripts/feeds install -a -f

echo "🎉 DIY Part 2 Finished!"

# 修改默认 IP (192.168.30.1)
sed -i 's/192.168.6.1/192.168.30.1/g' package/base-files/files/bin/config_generate

echo "=========================================="
echo "自定义脚本执行完毕"
echo "=========================================="
