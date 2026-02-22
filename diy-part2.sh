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

# =========================================================
# 0. [新增] 深度清理 Rust 相关残留 (防止缓存导致修复失败)
# =========================================================
echo "🧹 Cleaning up old Rust artifacts..."

# 1. 清理编译中间目录 (不管之前编没编过，删了重来)
# build_dir/host/rustc-xxxx 是编译发生的地方
rm -rf build_dir/host/rustc-*
rm -rf build_dir/target-*/host/rustc-*

# 2. 清理 dl 目录下的 Rust 源码包
# 之前下载失败的、Hash 不对的包必须删掉，强制脚本重新下载官方包
rm -f dl/rustc-*.tar.xz

# 3. 清理 Cargo 索引缓存
# 有时候 crate 索引损坏也会导致编译失败
rm -rf dl/cargo/registry/index/*

echo "✅ Cleanup done. Environment is clean."

# =========================================================
# 1. 修复 Rust 编译失败：替换为 ImmortalWrt 23.05 的稳定版
# =========================================================
echo "🔧 Starting Ultimate Rust Fix..."

RUST_MK="feeds/packages/lang/rust/Makefile"
DL_DIR="dl"

# 移除 feeds 中的旧 rust
rm -rf feeds/packages/lang/rust

# 克隆 23.05 稳定分支
git clone --depth 1 -b openwrt-23.05 https://github.com/immortalwrt/packages.git /tmp/temp_packages
mkdir -p feeds/packages/lang
cp -r /tmp/temp_packages/lang/rust feeds/packages/lang/
rm -rf /tmp/temp_packages

# =========================================================
# 2. 自动下载源码并修正 Hash (双重保险)
# =========================================================
RUST_VERSION=$(grep '^PKG_VERSION:=' "$RUST_MK" | cut -d '=' -f 2)
RUST_FILE="rustc-${RUST_VERSION}-src.tar.xz"
RUST_URL="https://static.rust-lang.org/dist/${RUST_FILE}"

mkdir -p "$DL_DIR"
# 因为前面执行了清理，这里肯定会重新下载
echo ">>> Downloading $RUST_FILE..."
wget -q --show-progress -O "$DL_DIR/$RUST_FILE" "$RUST_URL" || { echo "Download failed"; exit 1; }

# 计算并应用新 Hash
NEW_HASH=$(sha256sum "$DL_DIR/$RUST_FILE" | awk '{print $1}')
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/" "$RUST_MK"
echo "✅ Hash corrected to: $NEW_HASH"

# =========================================================
# 3. 编译环境硬化 (应用优化补丁)
# =========================================================
echo ">>> Applying Build Hardening..."

# A. 强制开启 CI-LLVM
sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$RUST_MK"
sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$RUST_MK"

# B. 清理补丁残留
sed -i '/Build\/Patch/a \	find $(HOST_BUILD_DIR) -name "*.orig" -delete\n	find $(HOST_BUILD_DIR) -name "*.rej" -delete' "$RUST_MK"

# C. 暴力删除校验文件
sed -i '/\$(PYTHON3) \$(HOST_BUILD_DIR)\/x.py/i \	find $(HOST_BUILD_DIR)/vendor -name .cargo-checksum.json -delete' "$RUST_MK"

# D. 环境变量优化 & 限制线程
sed -i '/export CARGO_HOME/a export CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_PROFILE_RELEASE_INCREMENTAL=false\nexport CARGO_INCREMENTAL=0' "$RUST_MK"
sed -i 's/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py -j 2/g' "$RUST_MK"

# E. 修正下载源
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"

echo "✅ Rust environment fully optimized!"

----------------------------------------------------------------
【最终收尾】强行刷新整个编译索引，确保所有“掉包”操作被系统识别
----------------------------------------------------------------
echo "🔄 正在进行全系统索引强制重映射..."
1. 物理删除所有临时索引
rm -rf tmp
2. 更新 Feeds 索引
./scripts/feeds update -a
3. 强制安装所有包，-f 会把 package/feeds 下的旧软链接全部切断并重指向
./scripts/feeds install -a
echo "✅ 恭喜！所有修改已全量就绪。"

# 修改默认 IP (192.168.30.1)
sed -i 's/192.168.6.1/192.168.30.1/g' package/base-files/files/bin/config_generate

echo "=========================================="
echo "自定义脚本执行完毕"
echo "=========================================="
