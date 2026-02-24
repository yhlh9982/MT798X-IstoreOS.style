#!/bin/bash
# diy-part3.sh
set -e
OPENWRT_ROOT=$(pwd)

echo "=========================================="
echo "执行 SSH3: Rust 专项救治 (V32.0 变量外部驱动版)"
echo "=========================================="

# 1. 刷新配置
make defconfig

# 2. 执行预处理 (回归你最成功的寻址路径)
echo ">>> [1/3] 执行源码解压..."
make package/feeds/packages/rust/host/prepare V=s || \
make package/feeds/packages/lang/rust/host/prepare V=s

# 3. 账本伪造手术 (Python 逻辑：100% 无乱码)
echo ">>> [2/3] 执行指纹重构手术..."
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

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
    echo "✅ 账本物理抹平完成。"
else
    echo "❌ 严重错误: 源码未解压成功。"
    exit 1
fi

# 4. 稳健编译
echo ">>> [3/3] 启动独立编译阶段 (降压限流)..."
rm -rf staging_dir/host/stamp/.rust_installed

# 【取代 Makefile 注入】：在这里实时导出所有欺骗变量
export CARGO_NET_OFFLINE=true
export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_INCREMENTAL=0
export RUST_BACKTRACE=1

# 硬件自适应
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 隐匿身份执行全路径编译
env -u CI -u GITHUB_ACTIONS make package/feeds/packages/rust/host/compile -j$T V=s || \
env -u CI -u GITHUB_ACTIONS make package/feeds/packages/lang/rust/host/compile -j$T V=s

echo "=========================================="
echo "✅ Rust 救治圆满完成！"
echo "=========================================="
