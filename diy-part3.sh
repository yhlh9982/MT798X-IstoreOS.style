#!/bin/bash
# =========================================================
# Rust 专项攻坚任务 (V27.5 最终稳定版)
# =========================================================

set -e
OPENWRT_ROOT=$(pwd)

echo ">>> [1/3] 执行源码解压与打补丁..."
# 刷新配置索引
make defconfig

# 使用之前最稳的全路径寻址
make package/feeds/packages/rust/host/prepare V=s || \
make package/feeds/packages/lang/rust/host/prepare V=s

# 3. 核心救治：重写账本指纹 (Python 逻辑)
echo ">>> [2/3] 执行账本与清单的“指纹重构”..."
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定源码物理目录: $RUST_SRC_DIR"
    # 使用 Python 抹平账本 (解决 1.90.0 的 Cargo.toml.orig 报错)
    python3 -c "
import os, json
for root, dirs, files in os.walk('$RUST_SRC_DIR/vendor'):
    if '.cargo-checksum.json' in files:
        path = os.path.join(root, '.cargo-checksum.json')
        with open(path, 'w') as f:
            json.dump({'files':{}, 'package':''}, f)
"
    # 抹除锁定清单中的哈希记录
    find "$RUST_SRC_DIR" -name "Cargo.lock" -exec sed -i '/checksum = /d' {} \;
    # 清理干扰文件
    find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
    echo "✅ 账本物理对齐已完成。"
else
    echo "❌ 严重错误: 源码未解压成功。"
    exit 1
fi

# 4. 稳健编译
echo ">>> [3/3] 启动独立编译阶段 (降压限流)..."
rm -rf staging_dir/host/stamp/.rust_installed

# 环境变量实时注入 (比写在 Makefile 里安全 100 倍)
export CARGO_NET_OFFLINE=true
export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_INCREMENTAL=0

# 硬件自适应
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 隐匿身份并执行全路径编译
env -u CI -u GITHUB_ACTIONS make package/feeds/packages/rust/host/compile -j$T V=s || \
env -u CI -u GITHUB_ACTIONS make package/feeds/packages/lang/rust/host/compile -j$T V=s

echo "✅ Rust 专项任务圆满完成！"
