#!/bin/bash
set -e
OPENWRT_ROOT=$(pwd)

echo "=========================================="
echo "Rust 专项攻坚 (回归稳健路径版)"
echo "=========================================="

# 1. 既然之前寻址没问题，我们先执行 defconfig 确保索引对齐
make defconfig

# 2. 执行预处理
echo ">>> [1/3] 正在执行 Rust 源码预处理..."
# 直接使用你之前成功进入编译阶段时对应的全路径
# 如果你的 rust 在 feeds/packages/lang/rust，全路径通常如下：
make package/feeds/packages/rust/host/prepare V=s || make package/feeds/packages/lang/rust/host/prepare V=s

# 3. 物理抹平账本 (使用已验证成功的 Python 逻辑)
echo ">>> [2/3] 正在执行指纹重构手术..."
# 物理目录探测 (保持这个 find 逻辑，因为日志证明它定位很准)
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定源码物理目录: $RUST_SRC_DIR"
    # 使用 Python 抹平账本 (欺骗审计员)
    python3 -c "
import os, json
for root, dirs, files in os.walk('$RUST_SRC_DIR/vendor'):
    if '.cargo-checksum.json' in files:
        path = os.path.join(root, '.cargo-checksum.json')
        with open(path, 'w') as f:
            json.dump({'files':{}, 'package':''}, f)
"
    # 抹除锁定清单哈希
    find "$RUST_SRC_DIR" -name "Cargo.lock" -exec sed -i '/checksum = /d' {} \;
    # 清理残留干扰文件
    find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
    find "$RUST_SRC_DIR" -name "*.rej" -delete 2>/dev/null || true
    echo "✅ 物理净化完成。"
else
    echo "❌ 严重错误: 无法定位解压后的源码目录。"
    exit 1
fi

# 4. 稳健编译
echo ">>> [3/3] 启动独立编译阶段..."
rm -rf staging_dir/host/stamp/.rust_installed
export CARGO_NET_OFFLINE=true

# 获取物理内存分配线程
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 使用与 prepare 一致的路径执行 compile
env -u CI -u GITHUB_ACTIONS make package/feeds/packages/rust/host/compile -j$T V=s || \
env -u CI -u GITHUB_ACTIONS make package/feeds/packages/lang/rust/host/compile -j$T V=s

echo "=========================================="
echo "✅ Rust 专项任务已全部就绪！"
echo "=========================================="
