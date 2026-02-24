#!/bin/bash
# diy-part3.sh
set -e
OPENWRT_ROOT=$(pwd)

echo "=========================================="
echo "执行 SSH3: Rust 物理直编救治 (V39.0)"
echo "=========================================="

# 1. 寻找 Rust 源码的【真实物理路径】
# 不再指望 package/rust 那个不靠谱的软链接
RUST_PHYSICAL_PATH=$(find feeds/packages -type d -name "rust" | head -n 1)

if [ -z "$RUST_PHYSICAL_PATH" ] || [ ! -f "$RUST_PHYSICAL_PATH/Makefile" ]; then
    echo "❌ 严重错误: 无法在物理磁盘上找到 Rust 源码。"
    exit 1
fi
echo "✅ 锁定物理路径: $RUST_PHYSICAL_PATH"

# 2. 物理预处理 (Prepare)
echo ">>> [1/3] 正在强制启动源码解压..."
# 瞒天过海：绕过主索引，直接调用该目录的 Makefile 目标
make -C "$RUST_PHYSICAL_PATH" host/prepare V=s || true

# 3. 核心救治：账本伪造 (Python)
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)
if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定构建目录: $RUST_SRC_DIR"
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

# 4. 终极直编：通过物理目录强制启动 host-compile
echo ">>> [3/3] 正在执行瞒天过海直编..."
rm -rf staging_dir/host/stamp/.rust_installed

# 设置欺骗变量
export RUSTC_BOOTSTRAP=1
export CARGO_NET_OFFLINE=true
export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_INCREMENTAL=0

# 临时修改该目录下的 Makefile 开启 LLVM 下载 (不影响全局索引)
sed -i 's/download-ci-llvm:=.*/download-ci-llvm:=true/g' "$RUST_PHYSICAL_PATH/Makefile"
sed -i 's/download-ci-llvm=.*/download-ci-llvm=true/g' "$RUST_PHYSICAL_PATH/Makefile"
sed -i 's/--frozen//g' "$RUST_PHYSICAL_PATH/Makefile"

# 线程自适应
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 【核心：-C 参数直编】彻底剥离 CI 身份，强行触发
env -u CI -u GITHUB_ACTIONS -u RUNNER_OS make -C "$RUST_PHYSICAL_PATH" host/compile -j$T V=s

echo "=========================================="
echo "✅ Rust 专项任务圆满完成 (直编模式)！"
echo "=========================================="
