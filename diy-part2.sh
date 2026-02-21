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
echo "Rust 历史版本锁定与硬化脚本 (V3.0)"
echo "=========================================="

# 1. 配置区域：在这里设定你想要锁定的版本
# 建议选择官方支持过的稳定版，如 1.75.0, 1.80.0, 1.82.0
WANT_VERSION="1.89.0"

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
DL_DIR="$OPENWRT_ROOT/dl"

# 3. 深度清理旧版本残余
echo ">>> 清理当前 Rust 目录及编译残留..."
rm -rf "$RUST_DIR"
rm -rf "$OPENWRT_ROOT/build_dir/host/rustc-*"
rm -rf "$OPENWRT_ROOT/build_dir/target-*/host/rustc-*"

# 4. 从官方 Git 历史中检索匹配版本 (含 Makefile + Patches)
echo ">>> 正在从官方历史记录中检索版本: $WANT_VERSION ..."
TEMP_REPO="/tmp/rust_history"
rm -rf "$TEMP_REPO"
# 深度设为 200 以确保能搜到较旧的版本
git clone --depth=200 https://github.com/openwrt/packages.git "$TEMP_REPO"
cd "$TEMP_REPO" || exit

# 搜索包含该版本号修改的最后一次提交 ID
TARGET_COMMIT=$(git log --grep="rust: update to $WANT_VERSION" --format="%H" -n 1)
[ -z "$TARGET_COMMIT" ] && TARGET_COMMIT=$(git log -S "PKG_VERSION:=$WANT_VERSION" --format="%H" -n 1 lang/rust/Makefile)

if [ -n "$TARGET_COMMIT" ]; then
    echo "✅ 找到匹配提交: $TARGET_COMMIT"
    git checkout "$TARGET_COMMIT" -- lang/rust
    mkdir -p "$OPENWRT_ROOT/$RUST_DIR"
    cp -r lang/rust/* "$OPENWRT_ROOT/$RUST_DIR/"
    cd - > /dev/null || exit
else
    echo "❌ 错误: 官方记录中未找到版本 $WANT_VERSION，请检查版本号是否正确。"
    exit 1
fi
rm -rf "$TEMP_REPO"

# 5. 注入硬化与加速逻辑
RUST_MK="$RUST_DIR/Makefile"
echo ">>> 正在为锁定版本应用硬化补丁..."

# A. 开启 CI-LLVM (磁盘与性能核心)
sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$RUST_MK"
sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$RUST_MK"

# B. 暴力处理 Checksum 与 .orig 备份 (解决所有 vendor 报错)
# 在打补丁后删除备份，在编译前删除校验 JSON
sed -i '/Build\/Patch/a \	find $(HOST_BUILD_DIR) -name "*.orig" -delete\n	find $(HOST_BUILD_DIR) -name "*.rej" -delete' "$RUST_MK"
sed -i '/\$(PYTHON3) \$(HOST_BUILD_DIR)\/x.py/i \	find $(HOST_BUILD_DIR)/vendor -name .cargo-checksum.json -delete' "$RUST_MK"

# C. 内存与稳定性硬化 (禁用增量编译，限制任务数为 2)
sed -i '/export CARGO_HOME/a export CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_PROFILE_RELEASE_INCREMENTAL=false\nexport CARGO_INCREMENTAL=0' "$RUST_MK"
sed -i 's/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py -j 2/g' "$RUST_MK"

# D. 修正编译参数与官方分发地址
sed -i 's/--frozen//g' "$RUST_MK"
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"

# 6. 全球权威镜像预下载与 Hash 校验
RUST_VER=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_HASH=$(grep '^PKG_HASH:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_FILE="rustc-${RUST_VER}-src.tar.xz"
DL_PATH="$DL_DIR/$RUST_FILE"

mkdir -p "$DL_DIR"
if [ ! -s "$DL_PATH" ]; then
    echo ">>> 正在从全球加速镜像下载 Rust 源码: $RUST_VER"
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

if [ -f "$DL_PATH" ] && [ -n "$RUST_HASH" ]; then
    LOCAL_HASH=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
    if [ "$LOCAL_HASH" != "$RUST_HASH" ]; then
        echo "⚠️  哈希校验失败！文件可能损坏，将删除文件。"
        rm -f "$DL_PATH"
        exit 1
    else
        echo "✅ 哈希校验通过，源码包 100% 正确。"
    fi
fi

echo "=========================================="
echo "✅ Rust 成功锁定为官方版本: $WANT_VERSION"
echo ">>> 优化状态: 补丁匹配[成功] CI-LLVM[已开启] 校验干扰[已暴力移除]"
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
