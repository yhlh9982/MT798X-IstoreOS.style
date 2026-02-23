#!/bin/bash
set -e
OPENWRT_ROOT=$(pwd)

echo "=========================================="
echo "Rust 专项攻坚任务 (V23.0 逻辑寻址版)"
echo "=========================================="

# 1. 刷新配置，确保系统彻底认领 SSH2 建立的新链接
echo ">>> [1/4] 正在同步编译索引..."
make defconfig

# 2. 执行预处理
echo ">>> [2/4] 执行 Rust 源码预处理 (解压与打补丁)..."

# 【核心修正】：使用 package/rust/host/prepare 替代长路径
# 在 OpenWrt 中，直接用 package/包名 是最标准的做法，系统会自动处理 feeds 深度
make package/rust/host/prepare V=s || {
    echo "⚠️  默认寻址失败，尝试从物理位置强制定位..."
    # 备用方案：如果逻辑名失败，脚本自动寻找 Makefile 所在的文件夹名
    RUST_DIR_NAME=$(find package/feeds -name "Makefile" | grep "/rust/Makefile" | sed 's|package/||;s|/Makefile||' | head -n 1)
    make "package/${RUST_DIR_NAME}/host/prepare" V=s
}

# 3. 物理抹平账本 (保持成功的 Python 逻辑)
echo ">>> [3/4] 正在执行账本伪造手术..."
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定源码物理目录: $RUST_SRC_DIR"
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
    echo "❌ 严重错误: 无法定位解压后的源码目录。"
    exit 1
fi

# 4. 稳健编译
echo ">>> [4/4] 启动 Rust 独立编译..."
rm -rf staging_dir/host/stamp/.rust_installed
export CARGO_NET_OFFLINE=true

MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && RUST_THREADS=2 || RUST_THREADS=1

# 同样使用逻辑简写路径执行编译
env -u CI -u GITHUB_ACTIONS make package/rust/host/compile -j$RUST_THREADS V=s
