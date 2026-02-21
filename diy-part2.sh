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
echo "Rust 终极闭环救治脚本 (V11.0 强制救治版)"
echo "=========================================="

# 1. 配置区域
# ---------------------------------------------------------
PKGS_REPO="https://github.com/openwrt/packages.git"
PKGS_BRANCH="openwrt-23.05"  # 强制引用的底座分支

# 三大权威来源
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

REAL_RUST_DIR="$OPENWRT_ROOT/feeds/packages/lang/rust"
REAL_RUST_MK="$REAL_RUST_DIR/Makefile"
DL_DIR="$OPENWRT_ROOT/dl"
TEMP_REPO="/tmp/rust_staging_clone"
mkdir -p "$DL_DIR"

# --- 辅助函数：注入验证过的硬化优化 (本地编译核心设置) ---
apply_final_hardening() {
    local mk=$1
    echo ">>> 正在为目标 Makefile 注入本地硬化优化 (CI-LLVM, -j 2, 暴力去校验)..."
    # 开启 CI-LLVM
    sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$mk"
    sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$mk"
    # 解决补丁备份干扰 (.orig)
    sed -i '/Build\/Patch/a \	find $(HOST_BUILD_DIR) -name "*.orig" -delete\n	find $(HOST_BUILD_DIR) -name "*.rej" -delete' "$mk"
    # 暴力屏蔽 Checksum (让 Cargo 闭嘴)
    sed -i '/\$(PYTHON3) \$(HOST_BUILD_DIR)\/x.py/i \	find $(HOST_BUILD_DIR)/vendor -name .cargo-checksum.json -delete' "$mk"
    # 内存保护与任务限制 (Actions 7G 内存保命设置)
    sed -i '/export CARGO_HOME/a export CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_PROFILE_RELEASE_INCREMENTAL=false\nexport CARGO_INCREMENTAL=0' "$mk"
    sed -i 's/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py -j 2/g' "$mk"
    # 修正地址与移除冻结
    sed -i 's/--frozen//g' "$mk"
    sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$mk"
}

# =========================================================
# 第一阶段：获取救治底座 (23.05 原始 packages)
# =========================================================
echo ">>> [1/4] 正在克隆官方 $PKGS_BRANCH 到临时目录作为救治底座..."
rm -rf "$TEMP_REPO"
if ! git clone --depth=1 -b "$PKGS_BRANCH" "$PKGS_REPO" "$TEMP_REPO" 2>/dev/null; then
    echo "❌ 错误: 救治底座克隆失败，网络异常。"
    exit 1
fi

TEMP_MK="$TEMP_REPO/lang/rust/Makefile"
V_REF=$(grep '^PKG_VERSION:=' "$TEMP_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
H_REF=$(grep '^PKG_HASH:=' "$TEMP_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
FILE="rustc-${V_REF}-src.tar.xz"

# =========================================================
# 第二阶段：三方并发下载与共识比对
# =========================================================
echo ">>> [2/4] 启动三方下载验证: $V_REF ..."
wget -q --timeout=30 --tries=2 -O "$DL_DIR/${FILE}.1" "$SOURCE_1/$FILE" &
wget -q --timeout=30 --tries=2 -O "$DL_DIR/${FILE}.2" "$SOURCE_2/$FILE" &
wget -q --timeout=30 --tries=2 -O "$DL_DIR/${FILE}.3" "$SOURCE_3/$FILE" &
wait

H1=$(sha256sum "$DL_DIR/${FILE}.1" 2>/dev/null | cut -d' ' -f1)
H2=$(sha256sum "$DL_DIR/${FILE}.2" 2>/dev/null | cut -d' ' -f1)
H3=$(sha256sum "$DL_DIR/${FILE}.3" 2>/dev/null | cut -d' ' -f1)

# =========================================================
# 第三阶段：决策树 (哈希匹配 -> 共识 -> 强制替换)
# =========================================================
NEED_FORCE_REPLACE=true
FINAL_HASH=""

if [ "$H1" == "$H_REF" ] || [ "$H2" == "$H_REF" ] || [ "$H3" == "$H_REF" ]; then
    echo "✅ [判定] 级别 1: 完美匹配 23.05 基准哈希。"
    [ "$H1" == "$H_REF" ] && mv "$DL_DIR/${FILE}.1" "$DL_DIR/$FILE"
    [ "$H2" == "$H_REF" ] && [ ! -f "$DL_DIR/$FILE" ] && mv "$DL_DIR/${FILE}.2" "$DL_DIR/$FILE"
    [ "$H3" == "$H_REF" ] && [ ! -f "$DL_DIR/$FILE" ] && mv "$DL_DIR/${FILE}.3" "$DL_DIR/$FILE"
    FINAL_HASH="$H_REF"
    NEED_FORCE_REPLACE=false # 情况 1 比较稳，可以不强拆，但为了保险我们后面统一执行一次替换

elif [ -n "$H1" ] && [ "$H1" == "$H2" ] && [ "$H1" == "$H3" ]; then
    echo "⚠️  [判定] 级别 2: 三方镜像一致但与基准不符，将自动更正哈希。"
    mv "$DL_DIR/${FILE}.1" "$DL_DIR/$FILE"
    FINAL_HASH="$H1"
    NEED_FORCE_REPLACE=false
    
else
    echo "🚨 [判定] 级别 3: 三方校验不一致或哈希冲突，执行强制物理救治。"
    # 只要能下到一个(非0字节)，就拿它当种子
    if [ -s "$DL_DIR/${FILE}.1" ]; then mv "$DL_DIR/${FILE}.1" "$DL_DIR/$FILE"; FINAL_HASH="$H1";
    elif [ -s "$DL_DIR/${FILE}.2" ]; then mv "$DL_DIR/${FILE}.2" "$DL_DIR/$FILE"; FINAL_HASH="$H2";
    fi
    NEED_FORCE_REPLACE=true
fi

# 最后的兜底检查：如果源码包根本没下到
if [ ! -s "$DL_DIR/$FILE" ]; then
    echo "❌ 致命错误: 源码包在所有源中均 404 或损坏，救治失败。"
    exit 1
fi
rm -f "$DL_DIR/${FILE}."*

# =========================================================
# 第四阶段：物理替换与硬化注入 (强制执行)
# =========================================================
echo ">>> [3/4] 正在执行 lang/rust 物理替换..."

# 彻底清理当前环境
rm -rf "$REAL_RUST_DIR"
mkdir -p "$REAL_RUST_DIR"
rm -rf "$OPENWRT_ROOT/build_dir/host/rustc-*"
rm -rf "$OPENWRT_ROOT/staging_dir/host/stamp/.rust_installed"

# 从救治底座拷贝干净的代码
cp -r "$TEMP_REPO/lang/rust/"* "$REAL_RUST_DIR/"
rm -rf "$TEMP_REPO"

# 修正哈希 (基于实际下载到的那个文件)
if [ -n "$FINAL_HASH" ]; then
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$FINAL_HASH/" "$REAL_RUST_MK"
    echo "✅ Makefile 哈希已更新为物理文件实际值。"
fi

# 强制注入本地硬化优化 (无论哪种情况成功的，都要注入以保过)
apply_final_hardening "$REAL_RUST_MK"

echo "=========================================="
echo "✅ Rust 闭环救治圆满完成！"
echo ">>> 强制回滚分支: $PKGS_BRANCH"
echo ">>> 强制回滚版本: $V_REF"
echo ">>> 优化模式: CI-LLVM + 本地硬化 + 限流"
echo "=========================================="

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
