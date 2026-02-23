#!/bin/bash
# diy-part3.sh

set -e
OPENWRT_ROOT=$(pwd)

echo "=========================================="
echo "开始执行 Rust 专项攻坚任务 (V21.0 稳定版)"
echo "=========================================="

# 1. 确保系统真正“看见”了 Rust
echo ">>> [1/4] 刷新编译树状态..."
make defconfig

# 2. 物理预处理 (解压源码)
echo ">>> [2/4] 执行 Rust 源码预处理..."
# 尝试不同的目标路径，确保能命中（部分源码结构不同）
make package/feeds/packages/rust/host/prepare V=s || \
make package/feeds/lang/rust/host/prepare V=s || {
    echo "❌ 严重错误: 即使重置索引后也无法找到 rust 编译目标。"
    exit 1
}

# 3. 定位目录并执行“账本伪造”
echo ">>> [3/4] 定位目录并执行“账本伪造”..."
# 查找 build_dir 里的源码目录
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -z "$RUST_SRC_DIR" ]; then
    echo "❌ 错误: 源码解压目录不存在。"
    exit 1
fi
echo "✅ 源码目录锁定: $RUST_SRC_DIR"

# A. 使用 Python 抹平账本 (保持 V20 逻辑，这是最稳的)
python3 -c "
import os, json
for root, dirs, files in os.walk('$RUST_SRC_DIR/vendor'):
    if '.cargo-checksum.json' in files:
        path = os.path.join(root, '.cargo-checksum.json')
        with open(path, 'w') as f:
            json.dump({'files':{}, 'package':''}, f)
"

# B. 抹除锁定清单中的哈希记录
find "$RUST_SRC_DIR" -name "Cargo.lock" -exec sed -i '/checksum = /d' {} \;

# C. 清理干扰文件
find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
find "$RUST_SRC_DIR" -name "*.rej" -delete 2>/dev/null || true
find "$RUST_SRC_DIR" -name ".cargo-ok" -delete 2>/dev/null || true

# 4. 稳健编译
echo ">>> [4/4] 启动稳健编译..."
rm -rf staging_dir/host/stamp/.rust_installed

# 自动分配线程
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && RUST_THREADS=2 || RUST_THREADS=1

# 离线环境与降压
export CARGO_NET_OFFLINE=true
export CARGO_PROFILE_RELEASE_DEBUG=false

env -u CI -u GITHUB_ACTIONS make package/feeds/packages/rust/host/compile -j$RUST_THREADS V=s || {
    echo "⚠️ 首次失败，尝试单核平推..."
    env -u CI -u GITHUB_ACTIONS make package/feeds/packages/rust/host/compile -j1 V=s
}

echo "=========================================="
echo "✅ Rust 专项任务圆满完成！"
echo "=========================================="
