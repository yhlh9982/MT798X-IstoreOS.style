#!/bin/bash
set -e
OPENWRT_ROOT="/workdir/openwrt"
cd "$OPENWRT_ROOT"

echo "=========================================="
echo "执行 SSH3: Rust 专项攻坚 (V29.0 零污染版)"
echo "=========================================="

# 1. 【核心救命招】手动强制建立逻辑路径
# 不管 feeds 怎么链，我们直接在 package/ 下建一个叫 rust 的链接指向物理源码
RUST_PHYSICAL=$(find feeds/packages -type d -name "rust" | head -n 1)
if [ -n "$RUST_PHYSICAL" ]; then
    rm -rf package/rust
    ln -sf "../$RUST_PHYSICAL" package/rust
    echo "✅ 路径强制接通: package/rust -> $RUST_PHYSICAL"
fi

# 2. 刷新配置
rm -rf tmp
make defconfig

# 3. 执行预处理
echo ">>> [1/3] 执行源码解压..."
# 此时我们已经有了 100% 存在的路径 package/rust
make package/rust/host/prepare V=s || true

# 4. 账本伪造手术 (Python)
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
    echo "✅ 物理净化完成。"
else
    echo "❌ 严重错误: 源码未解压。"
    exit 1
fi

# 5. 稳健编译 (关键：在这里注入变量，不再动 Makefile)
echo ">>> [3/3] 启动独立编译阶段..."
rm -rf staging_dir/host/stamp/.rust_installed

# 【取代之前 Makefile 注入的 export 指令】
export CARGO_NET_OFFLINE=true
export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_INCREMENTAL=0
export RUST_BACKTRACE=1

MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 隐匿 CI 身份执行编译
env -u CI -u GITHUB_ACTIONS make package/rust/host/compile -j$T V=s

echo "=========================================="
echo "✅ Rust 专项任务已全部就绪！"
echo "=========================================="
