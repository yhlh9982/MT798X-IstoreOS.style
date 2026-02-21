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
echo "Rust 深度同步与环境硬化脚本 (旗舰版)"
echo "=========================================="

# 1. 配置区域：设定 Packages 仓库的来源
# ---------------------------------------------------------
# 指定官方 packages 仓库地址
PKGS_REPO="https://github.com/openwrt/packages.git"
# 指定想要同步的分支 (如: openwrt-24.10, openwrt-23.05, master)
PKGS_BRANCH="master"
# ---------------------------------------------------------

# 2. 路径识别与环境检查
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

# 3. 彻底清理旧残余 (解决 Cargo.toml.orig 报错的先决条件)
echo ">>> 正在执行深度清理，确保编译环境纯净..."
rm -rf "$RUST_DIR"
rm -rf "$OPENWRT_ROOT/build_dir/host/rustc-*"
rm -rf "$OPENWRT_ROOT/build_dir/target-*/host/rustc-*"
rm -rf "$OPENWRT_ROOT/staging_dir/host/pkginfo/rust.default.install"

# 4. 深度同步指定的 Packages 版本
echo ">>> 正在从 $PKGS_REPO [$PKGS_BRANCH] 同步 Rust 定义..."
mkdir -p "$RUST_DIR"
TEMP_REPO="/tmp/rust_sync_repo"
rm -rf "$TEMP_REPO"

if git clone --depth=1 -b "$PKGS_BRANCH" "$PKGS_REPO" "$TEMP_REPO"; then
    cp -r "$TEMP_REPO/lang/rust/"* "$RUST_DIR/"
    rm -rf "$TEMP_REPO"
    echo "✅ 成功同步分支: $PKGS_BRANCH"
else
    echo "❌ 错误: 无法连接仓库同步源码定义"
    exit 1
fi

if [ ! -f "$RUST_MK" ]; then
    echo "❌ 错误: 同步失败，找不到 Makefile"
    exit 1
fi

# 5. 应用“保过”级优化与硬化逻辑
echo ">>> 正在注入硬化补丁与优化参数..."

# [优化] 开启 CI-LLVM 模式: 解决磁盘空间爆满 (从 12GB 降至 1GB)，提速 30 分钟以上
sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$RUST_MK"
sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$RUST_MK"

# [暴力修复] 解决 Cargo.toml.orig 报错和 Checksum 不匹配
# 打完 Patch 后立即清理所有备份文件 (.orig/.rej)
sed -i '/Build\/Patch/a \	find $(HOST_BUILD_DIR) -name "*.orig" -delete\n	find $(HOST_BUILD_DIR) -name "*.rej" -delete' "$RUST_MK"
# 编译前强行删除 vendor 目录下的所有校验 JSON (Cargo 报错的“银弹”)
sed -i '/\$(PYTHON3) \$(HOST_BUILD_DIR)\/x.py/i \	find $(HOST_BUILD_DIR)/vendor -name .cargo-checksum.json -delete' "$RUST_MK"

# [稳定性] 环境变量硬化: 禁用增量编译，强制单任务链接，防止 GitHub Actions 内存溢出 (OOM)
sed -i '/export CARGO_HOME/a export CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_PROFILE_RELEASE_INCREMENTAL=false\nexport CARGO_INCREMENTAL=0' "$RUST_MK"
# 限制 Rust 的并行编译数为 2，防止撑爆 7GB 内存
sed -i 's/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py -j 2/g' "$RUST_MK"

# [兼容性] 移除强制冻结，修正源码地址
sed -i 's/--frozen//g' "$RUST_MK"
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"

# 6. 源码预下载与 SHA256 哈希核实
RUST_VER=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_HASH=$(grep '^PKG_HASH:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_FILE="rustc-${RUST_VER}-src.tar.xz"
DL_PATH="$DL_DIR/$RUST_FILE"

echo ">>> 目标 Rust 版本: $RUST_VER"
mkdir -p "$DL_DIR"

if [ ! -s "$DL_PATH" ]; then
    echo ">>> 正在通过全球权威镜像下载源码包..."
    MIRRORS=(
        "https://static.rust-lang.org/dist/${RUST_FILE}"
        "https://rust-static-dist.s3.amazonaws.com/dist/${RUST_FILE}"
        "https://mirror.switch.ch/ftp/mirror/rust/dist/${RUST_FILE}"
    )
    for mirror in "${MIRRORS[@]}"; do
        echo ">>> 尝试节点: $mirror"
        if wget -q --show-progress --timeout=30 --tries=3 -O "$DL_PATH" "$mirror"; then
            [ -s "$DL_PATH" ] && break
        fi
    done
fi

# [验证] 核心步骤：哈希核实。如果本地文件 Hash 不对，证明下载损坏，脚本报错退出。
if [ -f "$DL_PATH" ] && [ -n "$RUST_HASH" ]; then
    LOCAL_HASH=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
    if [ "$LOCAL_HASH" != "$RUST_HASH" ]; then
        echo "⚠️  错误: 源码 Hash 校验失败！"
        echo "期望: $RUST_HASH"
        echo "实际: $LOCAL_HASH"
        rm -f "$DL_PATH"
        exit 1
    else
        echo "✅ 哈希校验通过，源码包 100% 正确。"
    fi
fi

echo "=========================================="
echo "✅ Rust 深度修复与环境硬化已完成"
echo ">>> 分支: $PKGS_BRANCH | 版本: $RUST_VER"
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
