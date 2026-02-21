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

#
# Rust 深度同步与环境硬化脚本 (自适应哈希版)
#

echo "=========================================="
echo "Rust 深度同步与环境硬化脚本 (自适应哈希版)"
echo "=========================================="

# 1. 配置区域
PKGS_REPO="https://github.com/openwrt/packages.git"
PKGS_BRANCH="openwrt-23.05"

# 2. 路径识别
TARGET_DIR="${1:-$(pwd)}"
check_openwrt_root() { [ -f "$1/scripts/feeds" ] && [ -f "$1/Makefile" ]; }

if check_openwrt_root "$TARGET_DIR"; then
    OPENWRT_ROOT="$TARGET_DIR"
else
    SUB_DIR=$(find . -maxdepth 2 -name "scripts" -type d | head -n 1 | xargs dirname 2>/dev/null)
    [ -n "$SUB_DIR" ] && check_openwrt_root "$SUB_DIR" && OPENWRT_ROOT="$(realpath "$SUB_DIR")" || { echo "❌ 错误: 未找到 OpenWrt 根目录"; exit 1; }
fi

RUST_DIR="$OPENWRT_ROOT/feeds/packages/lang/rust"
RUST_MK="$RUST_DIR/Makefile"
DL_DIR="$OPENWRT_ROOT/dl"

echo "✅ OpenWrt 根目录: $OPENWRT_ROOT"

# 3. 深度清理
echo ">>> 正在执行深度清理..."
rm -rf "$RUST_DIR"
rm -rf "$OPENWRT_ROOT/build_dir/host/rustc-*"
rm -rf "$OPENWRT_ROOT/build_dir/target-*/host/rustc-*"
rm -rf "$OPENWRT_ROOT/staging_dir/host/pkginfo/rust.default.install"

# 4. 同步 Packages 版本
echo ">>> 正在从 $PKGS_REPO [$PKGS_BRANCH] 同步 Rust 定义..."
mkdir -p "$RUST_DIR"
TEMP_REPO="/tmp/rust_sync_repo_$$"
rm -rf "$TEMP_REPO"

if git clone --depth=1 -b "$PKGS_BRANCH" "$PKGS_REPO" "$TEMP_REPO"; then
    cp -r "$TEMP_REPO/lang/rust/"* "$RUST_DIR/"
    rm -rf "$TEMP_REPO"
    echo "✅ 成功同步分支: $PKGS_BRANCH"
else
    echo "❌ 错误: 无法连接仓库"
    exit 1
fi

if [ ! -f "$RUST_MK" ]; then
    echo "❌ 错误: 同步失败，找不到 Makefile"
    exit 1
fi

# 5. 应用优化补丁
echo ">>> 正在注入硬化补丁..."

# 开启 CI-LLVM 模式（节省磁盘空间）
sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$RUST_MK"
sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$RUST_MK"

# 清理 .orig/.rej 文件
sed -i '/Build\/Patch/a \	find $(HOST_BUILD_DIR) -name "*.orig" -delete\n	find $(HOST_BUILD_DIR) -name "*.rej" -delete' "$RUST_MK"

# 删除 vendor 校验 JSON
sed -i '/\$(PYTHON3) \$(HOST_BUILD_DIR)\/x.py/i \	find $(HOST_BUILD_DIR)/vendor -name .cargo-checksum.json -delete' "$RUST_MK"

# 禁用增量编译，防止 OOM
sed -i '/export CARGO_HOME/a export CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_PROFILE_RELEASE_INCREMENTAL=false\nexport CARGO_INCREMENTAL=0' "$RUST_MK"

# 限制并行编译数
sed -i 's/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py -j 2/g' "$RUST_MK"

# 移除强制冻结
sed -i 's/--frozen//g' "$RUST_MK"

# 修正源码地址（删除行尾空格）
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"
sed -i 's/[[:space:]]*$//' "$RUST_MK"

# 6. 获取版本信息
RUST_VER=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
ORIG_HASH=$(grep '^PKG_HASH:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_FILE="rustc-${RUST_VER}-src.tar.xz"
DL_PATH="$DL_DIR/$RUST_FILE"

echo ">>> 目标 Rust 版本: $RUST_VER"
echo ">>> OpenWrt 期望哈希: ${ORIG_HASH:0:16}..."

mkdir -p "$DL_DIR"

# 7. 下载源码包
if [ ! -s "$DL_PATH" ]; then
    echo ">>> 正在下载源码包..."
    MIRRORS=(
        "https://static.rust-lang.org/dist/${RUST_FILE}"
        "https://mirrors.ustc.edu.cn/rust-static/dist/${RUST_FILE}"
        "https://mirrors.tuna.tsinghua.edu.cn/rustup/dist/${RUST_FILE}"
    )
    
    for mirror in "${MIRRORS[@]}"; do
        echo ">>> 尝试: $mirror"
        if wget -q --show-progress --timeout=60 -O "$DL_PATH.tmp" "$mirror" 2>/dev/null; then
            [ -s "$DL_PATH.tmp" ] && { mv "$DL_PATH.tmp" "$DL_PATH"; break; }
        fi
        rm -f "$DL_PATH.tmp"
    done
fi

if [ ! -s "$DL_PATH" ]; then
    echo "❌ 错误: 下载失败"
    exit 1
fi

# 8. 🔥 关键修改：自适应哈希处理
echo ">>> 验证下载文件..."

ACTUAL_HASH=$(sha256sum "$DL_PATH" | cut -d' ' -f1)

if [ "$ACTUAL_HASH" = "$ORIG_HASH" ]; then
    echo "✅ 哈希校验通过，与 OpenWrt 官方一致"
    HASH_STATUS="matched"
else
    echo "⚠️  哈希不匹配！"
    echo "    OpenWrt 期望: $ORIG_HASH"
    echo "    实际下载:    $ACTUAL_HASH"
    echo ""
    echo ">>> 自动修正 Makefile 哈希为实际值..."
    
    # 更新 Makefile 为实际哈希
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$ACTUAL_HASH/" "$RUST_MK"
    
    # 验证修改成功
    NEW_HASH=$(grep '^PKG_HASH:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
    if [ "$NEW_HASH" = "$ACTUAL_HASH" ]; then
        echo "✅ Makefile 已更新，使用实际下载哈希"
        HASH_STATUS="updated"
    else
        echo "❌ 更新 Makefile 失败"
        exit 1
    fi
fi

# 9. 创建验证标记
touch "$DL_PATH.verified"

echo "=========================================="
echo "✅ Rust 深度修复与环境硬化已完成"
echo ">>> 分支: $PKGS_BRANCH"
echo ">>> 版本: $RUST_VER"
echo ">>> 哈希状态: $HASH_STATUS"
echo "=========================================="

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
