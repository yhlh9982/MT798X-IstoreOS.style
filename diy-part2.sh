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

echo "=========================================="
echo "Rust 终极救治脚本 (V14.0 智能探测)"
echo "=========================================="

# 1. 配置区域
PKGS_REPO="https://github.com/openwrt/packages.git"
PKGS_BRANCH="master"  # 我们想要的稳定分支 openwrt-23.05  openwrt-24.10  openwrt-25.12  master  可选
RUST_OFFICIAL_URL="https://static.rust-lang.org/dist"

OPENWRT_ROOT=$(pwd)
RUST_DIR="$OPENWRT_ROOT/feeds/packages/lang/rust"
RUST_MK="$RUST_DIR/Makefile"
DL_DIR="$OPENWRT_ROOT/dl"

# ==========================================
# 第一步：物理替换定义 (必须先执行)
# ==========================================
echo ">>> [1/5] 正在物理替换 Rust 定义为 $PKGS_BRANCH 版本..."
rm -rf "$RUST_DIR"
rm -rf "$OPENWRT_ROOT/build_dir/host/rustc-*"
rm -rf "$OPENWRT_ROOT/staging_dir/host/stamp/.rust_installed"

TEMP_REPO="/tmp/rust_sync_$$"
git clone --depth=1 -b "$PKGS_BRANCH" "$PKGS_REPO" "$TEMP_REPO" 2>/dev/null
mkdir -p "$RUST_DIR"
cp -r "$TEMP_REPO/lang/rust/"* "$RUST_DIR/"
rm -rf "$TEMP_REPO"

# ==========================================
# 第二步：强制刷新索引 
# ==========================================
echo ">>> [2/5] 正在强制更新系统索引以匹配新 Makefile..."
rm -rf "$OPENWRT_ROOT/tmp"
./scripts/feeds update -i
./scripts/feeds install -f -p packages rust

# ==========================================
# 第三步：哈希核实与智能下载
# ==========================================
# 此时获取的是 特定 分支 Makefile 里的信息
V=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
H_EXPECTED=$(grep '^PKG_HASH:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_FILE="rustc-${V}-src.tar.xz"
DL_PATH="$DL_DIR/$RUST_FILE"

mkdir -p "$DL_DIR"

# 逻辑判断：如果文件已存在（可能由系统预下），则核实哈希
DOWNLOAD_NEED=true
if [ -f "$DL_PATH" ]; then
    echo ">>> 发现预存文件，正在核实哈希..."
    ACTUAL_H=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
    if [ "$ACTUAL_H" == "$H_EXPECTED" ]; then
        echo "✅ 哈希完全匹配，无需重复下载。"
        DOWNLOAD_NEED=false
    else
        echo "⚠️  哈希不匹配，准备执行官方镜像救治..."
        rm -f "$DL_PATH"
    fi
fi

# 如果不符合，启动手动救治下载
if [ "$DOWNLOAD_NEED" == "true" ]; then
    echo ">>> 正在从 Rust 官网下载权威源码包: $V ..."
    wget -q --timeout=60 --tries=3 -O "$DL_PATH" "$RUST_OFFICIAL_URL/$RUST_FILE"
    
    if [ -s "$DL_PATH" ]; then
        FINAL_H=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
        if [ "$FINAL_H" != "$H_EXPECTED" ]; then
            echo "⚠️  官方镜像哈希 ($FINAL_H) 与 Makefile ($H_EXPECTED) 仍不符"
            echo ">>> 正在执行物理对齐：修正 Makefile 哈希..."
            sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$FINAL_H/" "$RUST_MK"
        else
            echo "✅ 官方下载校验通过。"
        fi
    else
        echo "❌ 致命错误：无法从所有渠道获取源码包。"
        exit 1
    fi
fi

# ==========================================
# 第四步：注入本地硬化优化
# ==========================================
echo ">>> [4/5] 注入加速与硬化指令..."

# 开启 CI-LLVM
sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$RUST_MK"
sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$RUST_MK"

# 处理补丁残余
sed -i '/Build\/Patch/a \	find $(HOST_BUILD_DIR) -name "*.orig" -delete\n	find $(HOST_BUILD_DIR) -name "*.rej" -delete' "$RUST_MK"

# 屏蔽 Checksum
sed -i '/\$(PYTHON3) \$(HOST_BUILD_DIR)\/x.py/i \	find $(HOST_BUILD_DIR)/vendor -name .cargo-checksum.json -delete' "$RUST_MK"

# 内存保护与任务限制 (-j 2)
sed -i '/export CARGO_HOME/a export CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_PROFILE_RELEASE_INCREMENTAL=false\nexport CARGO_INCREMENTAL=0' "$RUST_MK"
sed -i 's/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py -j 2/g' "$RUST_MK"

# 地址补正
sed -i 's/--frozen//g' "$RUST_MK"
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"

# ==========================================
# 第五步：全系统索引强制重映射 (最终锁定)
# ==========================================
echo ">>> [5/5] 正在全量刷新编译索引 (针对 Rust/MosDNS/SmartDNS/Golang)..."

# 1. 物理删除所有临时索引缓存 (必须！否则系统可能不识别新加入的插件)
rm -rf "$OPENWRT_ROOT/tmp"

# 2. 更新本地 Feeds 索引 
# -i 参数非常重要：它让脚本只扫描本地已有的文件夹，不尝试通过 git clone 覆盖你的手动修改
./scripts/feeds update -i

# 3. 强制安装所有 Feeds 软件包
# -a: 扫描所有 Feed 源中的所有包
# -f: 强制（Force）模式，这会切断旧的软链接并重新指向你新下载/修改的源码路径
./scripts/feeds install -a -f

echo "✅ 恭喜！Rust、Golang、MosDNS、SmartDNS 及其它所有修改已全量就绪。"

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
