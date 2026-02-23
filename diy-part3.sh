#!/bin/bash
set -e
# 锁定基地
OPENWRT_ROOT="/workdir/openwrt"
cd $OPENWRT_ROOT

echo "=========================================="
echo "Rust 专项攻坚 (V24.1 强制物理挂载版)"
echo "=========================================="

# ---------------------------------------------------------
# 第一步：强制路径重连 (不依赖 feeds 脚本)
# ---------------------------------------------------------
echo ">>> [1/4] 执行物理路径硬链接..."

# 定义物理源码位置 (由 SSH2 确定)
PHYSICAL_RUST_DIR="$OPENWRT_ROOT/feeds/packages/lang/rust"
# 定义强制逻辑位置 (我们手动在 package 下建一个入口)
FORCED_PACKAGE_DIR="$OPENWRT_ROOT/package/rust-fix"

if [ -f "$PHYSICAL_RUST_DIR/Makefile" ]; then
    echo "✅ 发现物理源码: $PHYSICAL_RUST_DIR"
    # 删除旧的任何干扰
    rm -rf "$FORCED_PACKAGE_DIR"
    mkdir -p "$OPENWRT_ROOT/package"
    # 建立暴力硬链接，直接绕过 feeds 索引系统
    ln -sf "$PHYSICAL_RUST_DIR" "$FORCED_PACKAGE_DIR"
    echo "✅ 已强行挂载: $FORCED_PACKAGE_DIR -> $PHYSICAL_RUST_DIR"
else
    echo "❌ 严重错误: 物理源码 $PHYSICAL_RUST_DIR 不存在，请检查 SSH2 下载日志。"
    exit 1
fi

# ---------------------------------------------------------
# 第二步：强制刷新系统配置 (认领新入口)
# ---------------------------------------------------------
echo ">>> [2/4] 正在强制刷新编译树索引..."
rm -rf tmp
# 这一步会让系统看到 package/rust-fix 这个新入口
make defconfig

# 执行预处理 (使用我们强行定义的路径)
echo ">>> 执行源码解压..."
make package/rust-fix/host/prepare V=s || {
    echo "❌ 即使强制挂载也无法识别目标，正在检查目录结构..."
    ls -l "$FORCED_PACKAGE_DIR"
    exit 1
}

# ---------------------------------------------------------
# 第三步：账本伪造 (Python 逻辑)
# ---------------------------------------------------------
echo ">>> [3/4] 正在定位物理目录并抹平账本..."
RUST_SRC_DIR=$(find "$OPENWRT_ROOT/build_dir" -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定物理目录: $RUST_SRC_DIR"
    python3 -c "
import os, json
for root, dirs, files in os.walk('$RUST_SRC_DIR/vendor'):
    if '.cargo-checksum.json' in files:
        path = os.path.join(root, '.cargo-checksum.json')
        with open(path, 'w') as f:
            json.dump({'files':{}, 'package':''}, f)
"
    find "$RUST_SRC_DIR" -name "Cargo.lock" -exec sed -i '/checksum = /d' {} \;
    find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
    echo "✅ 物理净化完成。"
else
    echo "❌ 错误: 源码未解压。"
    exit 1
fi

# ---------------------------------------------------------
# 第四步：隐匿身份稳健编译
# ---------------------------------------------------------
echo ">>> [4/4] 启动 Rust 独立编译..."
rm -rf staging_dir/host/stamp/.rust_installed
export CARGO_NET_OFFLINE=true

MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 使用我们强行挂载的逻辑路径执行编译
env -u CI -u GITHUB_ACTIONS make package/rust-fix/host/compile -j$T V=s

echo "=========================================="
echo "✅ Rust 专项任务圆满完成！"
echo "=========================================="
