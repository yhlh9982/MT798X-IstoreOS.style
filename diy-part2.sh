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

set -e

echo "=========================================="
echo "DIY Part 2: 同步 OpenWrt 23.05 Rust 版本"
echo "=========================================="
echo "当前目录: $(pwd)"

# ==========================================
# 1. 获取 OpenWrt 官方 Rust 配置
# ==========================================
echo ">>> 获取 OpenWrt 23.05 官方 Rust 配置..."

OFFICIAL_URL="https://raw.githubusercontent.com/openwrt/packages/openwrt-23.05/lang/rust/Makefile"
TMP_FILE="/tmp/rust_official.mk"

curl -fsSL "$OFFICIAL_URL" -o "$TMP_FILE" || {
    echo "❌ 下载官方 Makefile 失败: $OFFICIAL_URL"
    exit 1
}

# 提取版本和哈希
RUST_VER=$(grep '^PKG_VERSION:=' "$TMP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_HASH=$(grep '^PKG_HASH:=' "$TMP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' ')

if [ -z "$RUST_VER" ] || [ -z "$RUST_HASH" ]; then
    echo "❌ 无法解析版本或哈希"
    echo "文件内容:"
    head -20 "$TMP_FILE"
    exit 1
fi

echo "目标版本: $RUST_VER"
echo "目标哈希: ${RUST_HASH:0:16}..."

# ==========================================
# 2. 替换本地 Makefile
# ==========================================
echo ">>> 替换本地 Rust Makefile..."

LOCAL_MK="feeds/packages/lang/rust/Makefile"

if [ ! -f "$LOCAL_MK" ]; then
    echo "❌ 错误: 找不到 $LOCAL_MK"
    exit 1
fi

# 备份
cp "$LOCAL_MK" "$LOCAL_MK.bak"

# 替换版本、哈希、URL
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$RUST_VER/" "$LOCAL_MK"
sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$RUST_HASH/" "$LOCAL_MK"
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$LOCAL_MK"
sed -i 's/[[:space:]]*$//' "$LOCAL_MK"  # 删除行尾空格

echo "✅ 已替换为: $RUST_VER"
grep -E '^(PKG_VERSION|PKG_HASH|PKG_SOURCE_URL):=' "$LOCAL_MK"

# ==========================================
# 3. 预下载 Rust 源码包
# ==========================================
echo ">>> 预下载 Rust $RUST_VER..."

RUST_FILE="rustc-${RUST_VER}-src.tar.xz"
DL_PATH="dl/$RUST_FILE"

mkdir -p dl

# 检查是否已存在且有效
if [ -f "$DL_PATH" ]; then
    echo "检查现有文件..."
    LOCAL_HASH=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
    if [ "$LOCAL_HASH" = "$RUST_HASH" ]; then
        echo "✅ 文件已存在且哈希匹配，跳过下载"
    else
        echo "⚠️ 哈希不匹配，重新下载..."
        rm -f "$DL_PATH"
    fi
fi

# 需要下载时
if [ ! -f "$DL_PATH" ]; then
    RUST_URL="https://static.rust-lang.org/dist/${RUST_FILE}"
    echo "从官方下载: $RUST_URL"
    
    # 下载（带重试）
    if wget --timeout=120 -O "${DL_PATH}.tmp" "$RUST_URL" 2>/dev/null || \
       curl -fsSL --connect-timeout 120 -o "${DL_PATH}.tmp" "$RUST_URL"; then
        
        # 验证哈希
        DL_HASH=$(sha256sum "${DL_PATH}.tmp" | cut -d' ' -f1)
        if [ "$DL_HASH" = "$RUST_HASH" ]; then
            mv "${DL_PATH}.tmp" "$DL_PATH"
            echo "✅ 下载并验证成功"
        else
            echo "❌ 哈希验证失败"
            echo "期望: $RUST_HASH"
            echo "实际: $DL_HASH"
            rm -f "${DL_PATH}.tmp"
            exit 1
        fi
    else
        echo "❌ 下载失败: $RUST_URL"
        exit 1
    fi
fi

ls -lh "$DL_PATH"

# ==========================================
# 4. 清理旧版本冲突文件
# ==========================================
echo ">>> 清理旧版本 Rust 文件..."

for old_file in dl/rustc-1.*-src.tar.xz dl/rustc-1.*-src.tar.xz.*; do
    if [ -f "$old_file" ] && [ "$old_file" != "$DL_PATH" ] && [ "$old_file" != "${DL_PATH}.verified" ]; then
        echo "删除旧版本: $old_file"
        rm -f "$old_file"
    fi
done

# 创建验证标记
touch "${DL_PATH}.verified"

# 清理临时文件
rm -f "$TMP_FILE"

echo "=========================================="
echo "Rust $RUST_VER 准备完成"
echo "文件: $DL_PATH"
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
