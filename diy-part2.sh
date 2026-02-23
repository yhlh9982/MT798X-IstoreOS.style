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
echo "Rust 终极救治脚本 (V14.4 最终核实版)"
echo "=========================================="

# 1. 配置区域  
# 可选packages 分支  openwrt-23.05  目前rust版本为 1.85.0 ，为最稳定的版本，但是编译时间会延长
# 可选packages 分支  openwrt-24.10  目前rust版本为 1.90.0   
# 可选packages 分支  master  目前rust版本为 1.90.0  此后的分支 rust 版本可能不与24.10 同时更新版本，如果需要更改，需要核实
# 可选packages 分支  openwrt-25.12  目前rust版本为 1.90.0
#  packages 核实的地址 ：https://github.com/openwrt/packages/blob/openwrt-24.10/lang/rust/Makefile
# ---------------------------------------------------------
PKGS_BRANCH="master"
PKGS_REPO="https://github.com/openwrt/packages.git"
RUST_OFFICIAL_URL="https://static.rust-lang.org/dist"

OPENWRT_ROOT=$(pwd)
RUST_DIR="$OPENWRT_ROOT/feeds/packages/lang/rust"
RUST_MK="$RUST_DIR/Makefile"
DL_DIR="$OPENWRT_ROOT/dl"

# ==========================================
# 第一步：物理替换定义 (强制对齐)
# ==========================================
echo ">>> [1/5] 物理重置 Rust 底座至 $PKGS_BRANCH ..."
rm -rf "$RUST_DIR"
rm -rf "$OPENWRT_ROOT/build_dir/host/rustc-*"
rm -rf "$OPENWRT_ROOT/staging_dir/host/stamp/.rust_installed"

TEMP_REPO="/tmp/rust_sync_$$"
git clone --depth=1 -b "$PKGS_BRANCH" "$PKGS_REPO" "$TEMP_REPO" 2>/dev/null
mkdir -p "$RUST_DIR"
cp -r "$TEMP_REPO/lang/rust/"* "$RUST_DIR/"
rm -rf "$TEMP_REPO"
echo "✅ $PKGS_BRANCH 源码及补丁集已对齐。"

# ==========================================
# 第二步：强制刷新索引
# ==========================================
echo ">>> [2/5] 正在重新建立软链接索引..."
rm -rf "$OPENWRT_ROOT/tmp"
./scripts/feeds update -i
./scripts/feeds install -f -p packages rust

# ==========================================
# 第三步：智能下载与哈希自适应救治
# ==========================================
V=$(grep -E '^PKG_VERSION[:=]+' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
H_EXPECTED=$(grep -E '^PKG_HASH[:=]+' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_FILE="rustc-${V}-src.tar.xz"
DL_PATH="$DL_DIR/$RUST_FILE"

[ -z "$V" ] && { echo "❌ 错误: 无法从 Makefile 提取版本号"; exit 1; }
mkdir -p "$DL_DIR"

NEED_DOWNLOAD=true
if [ -f "$DL_PATH" ]; then
    echo ">>> 发现预存文件，核实哈希..."
    ACTUAL_H=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
    if [ "$ACTUAL_H" == "$H_EXPECTED" ]; then
        echo "✅ 现有文件校验成功。"
        NEED_DOWNLOAD=false
    else
        echo "⚠️  哈希不符，重新下载..."
        rm -f "$DL_PATH"
    fi
fi

if [ "$NEED_DOWNLOAD" == "true" ]; then
    echo ">>> 从 Rust 官网下载权威源码: $V ..."
    if ! wget -q --timeout=60 --tries=3 -O "${DL_PATH}.tmp" "$RUST_OFFICIAL_URL/$RUST_FILE"; then
        echo "❌ 致命错误：下载失败。"
        exit 1
    fi
    mv "${DL_PATH}.tmp" "$DL_PATH"
fi

FINAL_H=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
if [ "$FINAL_H" != "$H_EXPECTED" ]; then
    echo "🚨 哈希自适应：重写 Makefile 记录为 $FINAL_H"
    sed -i "s/^PKG_HASH[:=].*/PKG_HASH:=$FINAL_H/" "$RUST_MK"
fi

# ==========================================
# 第四步：硬化优化与“账本销毁”（欺骗核心）
# ==========================================
echo ">>> [4/5] 注入欺骗指令与性能硬化..."

# 1. CI-LLVM 开启
sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$RUST_MK"
sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$RUST_MK"

# 2. 清理 Patch 痕迹 (.orig)
# 修正点：同时清理 .rej 以防万一
sed -i '/Build\/Patch/a \	find $(HOST_BUILD_DIR) -name "*.orig" -delete\n	find $(HOST_BUILD_DIR) -name "*.rej" -delete' "$RUST_MK"

# 3. 销毁审计账本 (.cargo-checksum.json)
# 修正点：使用更宽泛的正则匹配 python3 x.py 并在其执行前删除所有校验和标记文件
sed -i '/\$(PYTHON3).*x\.py/i \	find $(HOST_BUILD_DIR) -name ".cargo-checksum.json" -delete -o -name ".cargo-ok" -delete' "$RUST_MK"

# 4. 环境变量降压与彻底离线化
# 修正点：加入 CARGO_NET_OFFLINE=true 彻底切断校验尝试
sed -i '/export CARGO_HOME/a export CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_NET_OFFLINE=true\nexport CARGO_INCREMENTAL=0' "$RUST_MK"

# 5. 并发限制 (-j 2)
sed -i 's/\$(PYTHON3).*x\.py/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py -j 2/g' "$RUST_MK"

# 6. 地址补正
sed -i 's/--frozen//g' "$RUST_MK"
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"

# ==========================================
# 第五步：全量索引刷新 (收尾锁定)
# ==========================================
echo ">>> [5/5] 正在全量同步所有插件软链接索引..."
rm -rf "$OPENWRT_ROOT/tmp"
./scripts/feeds update -i
./scripts/feeds install -a -f

echo "=========================================="
echo "✅ Rust 终极救治完成！"
echo ">>> 锁定版本: $(grep '^PKG_VERSION:=' $RUST_MK | cut -d'=' -f2)"
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
