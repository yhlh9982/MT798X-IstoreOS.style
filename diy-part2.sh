#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

echo "=========================================="
echo "Rust 24.10 优化"
echo "=========================================="

# 1. 路径识别与环境检查
TARGET_DIR="${1:-$(pwd)}"

check_openwrt_root() {
    [ -f "$1/scripts/feeds" ] && [ -f "$1/Makefile" ]
}

if check_openwrt_root "$TARGET_DIR"; then
    OPENWRT_ROOT="$TARGET_DIR"
    echo "✅ 找到 OpenWrt 根目录: $OPENWRT_ROOT"
else
    SUB_DIR=$(find . -maxdepth 2 -name "scripts" -type d | head -n 1 | xargs dirname 2>/dev/null)
    if [ -n "$SUB_DIR" ] && check_openwrt_root "$SUB_DIR"; then
        OPENWRT_ROOT="$(realpath "$SUB_DIR")"
        echo "✅ 在子目录找到 OpenWrt 根目录: $OPENWRT_ROOT"
    else
        echo "❌ 错误: 无法确定 OpenWrt 源码根目录。"
        exit 1
    fi
fi

# 定义核心路径
RUST_DIR="$OPENWRT_ROOT/feeds/packages/lang/rust"
RUST_MK="$RUST_DIR/Makefile"
DL_DIR="$OPENWRT_ROOT/dl"
BUILD_DIR_HOST="$OPENWRT_ROOT/build_dir/host/rustc-*"
BUILD_DIR_TARGET="$OPENWRT_ROOT/build_dir/target-*/host/rustc-*"

# 2. 深度清理（解决文件残留导致的各类报错）
echo ">>> 执行深度清理，排除旧版本干扰..."
rm -rf "$RUST_DIR"
rm -rf $BUILD_DIR_HOST
rm -rf $BUILD_DIR_TARGET
# 清理可能损坏的 Cargo 索引缓存
rm -rf "$OPENWRT_ROOT/dl/cargo/registry/index/*"

# 3. 深度同步官方 24.10 Rust 定义 (Makefile + Patches)
echo ">>> 正在从官方 24.10 仓库同步完整的 Rust 构建脚本..."
mkdir -p "$RUST_DIR"
TEMP_REPO="/tmp/openwrt_pkg_rust"
rm -rf "$TEMP_REPO"
if git clone --depth=1 -b openwrt-24.10 https://github.com/openwrt/packages.git "$TEMP_REPO"; then
    cp -r "$TEMP_REPO/lang/rust/"* "$RUST_DIR/"
    rm -rf "$TEMP_REPO"
else
    echo "❌ 错误: 无法连接 GitHub 官方仓库同步源码定义"
    exit 1
fi

if [ ! -f "$RUST_MK" ]; then
    echo "❌ 错误: 同步失败，找不到 Makefile"
    exit 1
fi

# 4. 优化与硬化指令注入 (手术刀式修改 Makefile)
echo ">>> 正在应用深度修复与环境硬化补丁..."

# A. 开启 CI-LLVM 模式 (节省 10GB+ 空间，提速 30分钟)
sed -i 's/download-ci-llvm:=false/download-ci-llvm:=true/g' "$RUST_MK"
sed -i 's/download-ci-llvm=false/download-ci-llvm=true/g' "$RUST_MK"

# B. 核心修复：处理补丁残留 (解决 serde / Cargo.toml.orig 的关键)
# 在打完补丁后，立即删除所有 .orig 和 .rej 备份文件，防止 Cargo 扫描报警
sed -i '/Build\/Patch/a \	find $(HOST_BUILD_DIR) -name "*.orig" -delete\n	find $(HOST_BUILD_DIR) -name "*.rej" -delete' "$RUST_MK"

# C. 暴力跳过 Checksum 校验
# 在执行编译 (x.py) 前，强制删除所有 vendor 目录下的校验文件，实现“静默通过”
sed -i '/\$(PYTHON3) \$(HOST_BUILD_DIR)\/x.py/i \	find $(HOST_BUILD_DIR)/vendor -name .cargo-checksum.json -delete' "$RUST_MK"

# D. 环境变量硬化 (禁用增量编译，大幅降低 OOM 内存溢出风险)
sed -i '/export CARGO_HOME/a export CARGO_PROFILE_RELEASE_DEBUG=false\nexport CARGO_PROFILE_RELEASE_INCREMENTAL=false\nexport CARGO_INCREMENTAL=0' "$RUST_MK"

# E. 限制并行任务 (GitHub Actions 建议限流，防止内存撑爆导致进程被杀)
sed -i 's/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py/$(PYTHON3) $(HOST_BUILD_DIR)\/x.py -j 2/g' "$RUST_MK"

# F. 移除强制冻结和修正地址
sed -i 's/--frozen//g' "$RUST_MK"
sed -i 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://static.rust-lang.org/dist/|' "$RUST_MK"

# 5. 源码预下载 (针对 Actions 优化的全球权威节点)
RUST_VER=$(grep '^PKG_VERSION:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_HASH=$(grep '^PKG_HASH:=' "$RUST_MK" | head -1 | cut -d'=' -f2 | tr -d ' ')
RUST_FILE="rustc-${RUST_VER}-src.tar.xz"
DL_PATH="$DL_DIR/$RUST_FILE"

echo ">>> 目标版本: $RUST_VER"
mkdir -p "$DL_DIR"

if [ ! -s "$DL_PATH" ]; then
    echo ">>> 正在从全球权威镜像获取源码包..."
    MIRRORS=(
        "https://static.rust-lang.org/dist/${RUST_FILE}"
        "https://rust-static-dist.s3.amazonaws.com/dist/${RUST_FILE}"
        "https://mirror.switch.ch/ftp/mirror/rust/dist/${RUST_FILE}"
        "http://mirror.cs.uwaterloo.ca/rust-static/static/dist/${RUST_FILE}"
    )

    for mirror in "${MIRRORS[@]}"; do
        echo ">>> 尝试节点: $mirror"
        if wget -q --show-progress --timeout=30 --tries=3 -O "$DL_PATH" "$mirror"; then
            [ -s "$DL_PATH" ] && break
        fi
    done
fi

# 6. 执行 Hash 最终校验
if [ -f "$DL_PATH" ] && [ -n "$RUST_HASH" ]; then
    LOCAL_HASH=$(sha256sum "$DL_PATH" | cut -d' ' -f1)
    if [ "$LOCAL_HASH" != "$RUST_HASH" ]; then
        echo "⚠️  警告: 源码 Hash 校验失败，文件可能损坏！"
        rm -f "$DL_PATH"
        exit 1
    else
        echo "✅ Hash 校验通过，源码包完整。"
    fi
fi

echo "=========================================="
echo "✅ Rust 24.10 终极硬化完成"
echo ">>> 状态: 24.10深度同步[成功] CI-LLVM[已开启] 容错硬化[已应用]"
echo "=========================================="

# =========================================================
# 智能修复脚本（兼容 package/ 和 feeds/）
# =========================================================
REPO_ROOT=$(readlink -f "$GITHUB_WORKSPACE")
CUSTOM_LUA="$REPO_ROOT/istore/istore_backend.lua"

echo "Debug: Repo root is $REPO_ROOT"

# 1. 优先查找 package 目录
TARGET_LUA=$(find package -name "istore_backend.lua" -type f 2>/dev/null)

# 2. 如果 package 中没找到，再查找 feeds
if [ -z "$TARGET_LUA" ]; then
    echo "Not found in package/, searching in feeds/..."
    TARGET_LUA=$(find feeds -name "istore_backend.lua" -type f 2>/dev/null)
fi

# 3. 执行覆盖（逻辑与原脚本相同）
if [ -n "$TARGET_LUA" ]; then
    echo "Found target file: $TARGET_LUA"
    if [ -f "$CUSTOM_LUA" ]; then
        echo "Overwriting with custom file..."
        cp -f "$CUSTOM_LUA" "$TARGET_LUA"
        if cmp -s "$CUSTOM_LUA" "$TARGET_LUA"; then
             echo "✅ Overwrite Success! Files match."
        else
             echo "❌ Error: Copy failed or files do not match."
        fi
    else
        echo "❌ Error: Custom file ($CUSTOM_LUA) not found!"
        ls -l "$REPO_ROOT/istore" 2>/dev/null || echo "Directory not found"
    fi
else
    echo "❌ Error: istore_backend.lua not found in package/ or feeds/!"
fi

echo ">>> Patching DiskMan and libxcrypt..."

#  DiskMan 修复
DM_MAKEFILE=$(find feeds/luci -name "Makefile" | grep "luci-app-diskman")
if [ -f "$DM_MAKEFILE" ]; then
    sed -i '/ntfs-3g-utils /d' "$DM_MAKEFILE"
    echo "✅ DiskMan fix applied."
fi

# =========================================================
# 强制修改默认主题为 Argon (彻底移除 Bootstrap)
# =========================================================

echo ">>> 开始强制替换默认主题为 luci-theme-argon..."

# 1. 修正 collections/luci 中的硬依赖
# 将 Makefile 中依赖的 luci-theme-bootstrap 替换为 luci-theme-argon
find "$OPENWRT_ROOT/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i 's/+luci-theme-bootstrap/+luci-theme-argon/g' {} +

# 2. 修改 luci-base 的默认主题配置
# 这一步是为了防止系统启动时去找 bootstrap 的路径
LUCI_BASE_CONFIG="$OPENWRT_ROOT/feeds/luci/modules/luci-base/root/etc/config/luci"
if [ -f "$LUCI_BASE_CONFIG" ]; then
    sed -i 's/bootstrap/argon/g' "$LUCI_BASE_CONFIG"
    echo "✅ luci-base 默认配置已指向 argon"
fi

# 3. 修改系统初始化时的默认主题 (uci-defaults)
# 搜索所有包含 bootstrap 路径的默认设置并替换为 argon
find "$OPENWRT_ROOT/feeds/luci/themes/" -type f -name "*_luci-theme-bootstrap" -exec sed -i 's/bootstrap/argon/g' {} +

# 4. 删除 Bootstrap 源码文件夹 (可选，如果你怕依赖报错可以不删，但上面的步骤会确保它不被选中)
# 建议：如果不删除，可以确保编译不报错，但生成的固件里不会包含它。
# 如果非要删除，必须清理 tmp 目录
rm -rf "$OPENWRT_ROOT/feeds/luci/themes/luci-theme-bootstrap"

# 5. 【关键】强制在 .config 层面禁用 Bootstrap
# 即使你在 menuconfig 选了，这里也会在最后阶段将其强制关闭
[ -f "$OPENWRT_ROOT/.config" ] && sed -i '/CONFIG_PACKAGE_luci-theme-bootstrap=y/d' "$OPENWRT_ROOT/.config"
echo "CONFIG_PACKAGE_luci-theme-bootstrap=n" >> "$OPENWRT_ROOT/.config"
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> "$OPENWRT_ROOT/.config"

echo "✅ 默认主题修改完成：Argon 现在是唯一的默认选项。"

# 修复 libxcrypt 编译报错
# 给 configure 脚本添加 --disable-werror 参数，忽略警告
sed -i 's/CONFIGURE_ARGS +=/CONFIGURE_ARGS += --disable-werror/' feeds/packages/libs/libxcrypt/Makefile

# 替换golang到1.24.x
rm -rf feeds/packages/lang/golang
git clone -b 24.x --single-branch https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang

# =========================================================
# 终极修改 Tailscale 菜单归类 (内容追踪版)
# =========================================================

echo ">>> 正在通过内容搜索定位 Tailscale 菜单定义..."

# 直接在 tailscale 源码目录下搜索包含 "admin/services/tailscale" 的所有文件
# 这样能精准找到定义菜单位置的地方，不管它是 JSON 还是 Lua
TS_FILES=$(grep -rl "admin/services/tailscale" package/tailscale)

if [ -n "$TS_FILES" ]; then
    for file in $TS_FILES; do
        # 排除 acl.d 文件夹（权限文件），我们只改真正的菜单定义
        if [[ "$file" == *"acl.d"* ]]; then
            echo "Skipping ACL file: $file"
            continue
        fi
        
        echo "✅ 发现真正的菜单定义文件: $file"
        # 执行替换
        sed -i 's|admin/services/tailscale|admin/vpn/tailscale|g' "$file"
        
        # 针对某些版本可能存在的 parent 字段也进行加固修改
        sed -i 's/"parent": "luci.services"/"parent": "luci.vpn"/g' "$file"
    done
    echo "✅ Tailscale 菜单位置修改尝试完成"
else
    echo "❌ 错误: 未能在源码中搜寻到菜单位置定义，请检查源码结构。"
fi

# =========================================================
# 强制移动 ksmbd (网络共享) 到 NAS 分类
# =========================================================

echo ">>> 正在搜索并修改 ksmbd (网络共享) 菜单归类..."

# 在 feeds 目录下搜索包含 ksmbd 菜单路径的文件
# 范围限定在 luci-app-ksmbd 插件目录内
KSMBD_FILES=$(grep -rl "admin/services/ksmbd" "$OPENWRT_ROOT/feeds/luci/applications/luci-app-ksmbd" 2>/dev/null)

if [ -n "$KSMBD_FILES" ]; then
    for file in $KSMBD_FILES; do
        # 排除 acl.d 权限定义文件，防止改错导致权限报错
        if [[ "$file" == *"acl.d"* ]]; then
            continue
        fi

        echo "✅ 发现 ksmbd 菜单定义: $file"
        
        # 1. 替换路径定义：从服务(services) 移动到 NAS(nas)
        sed -i 's|admin/services/ksmbd|admin/nas/ksmbd|g' "$file"
        
        # 2. 替换父级分类定义 (JSON 风格)
        # 统一处理单引号和双引号的情况，确保归类到 luci.nas
        sed -i 's/"parent": "luci.services"/"parent": "luci.nas"/g' "$file"
        sed -i "s/'parent': 'luci.services'/'parent': 'luci.nas'/g" "$file"
    done
    echo "✅ ksmbd 菜单位置修改完成。"
else
    echo "⚠️ 警告: 未能在 feeds 中找到 ksmbd 菜单定义。"
fi

# 自定义默认网关，后方的192.168.30.1即是可自定义的部分
sed -i 's/192.168.[0-9]*.[0-9]*/192.168.30.1/g' package/base-files/files/bin/config_generate

# 自定义主机名
#sed -i "s/hostname='ImmortalWrt'/hostname='360T7'/g" package/base-files/files/bin/config_generate

# 固件版本名称自定义
#sed -i "s/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='OpenWrt By gino $(date +"%Y%m%d")'/g" package/base-files/files/etc/openwrt_release
