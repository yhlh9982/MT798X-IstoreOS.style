#!/bin/bash
set -e
# 锁定基地
OPENWRT_ROOT="/workdir/openwrt"
cd $OPENWRT_ROOT

echo "=========================================="
echo "Rust 专项攻坚 (V26.1 路径自愈版)"
echo "=========================================="

# 1. 刷新配置，让系统认领修复后的 Makefile
make defconfig

# 2. 动态探测 Rust 的精确编译路径
echo ">>> [1/3] 正在全盘扫描 Rust 逻辑路径..."
# 这行命令会找到诸如 package/feeds/packages/lang/rust 的真实路径
RUST_LOGIC_PATH=$(find package -name "Makefile" | grep "/rust/Makefile" | sed 's|/Makefile||' | head -n 1)

if [ -z "$RUST_LOGIC_PATH" ]; then
    echo "❌ 严重错误: 无法定位 Rust 编译路径。尝试紧急软链接..."
    ln -sf feeds/packages/lang/rust package/rust-manual
    RUST_LOGIC_PATH="package/rust-manual"
fi
echo "✅ 最终编译目标: $RUST_LOGIC_PATH"

# 3. 执行预处理
echo ">>> [2/3] 执行源码解压与打补丁..."
make "${RUST_LOGIC_PATH}/host/prepare" V=s || true

# 4. 账本伪造手术 (Python)
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)
if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定源码目录: $RUST_SRC_DIR"
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
    echo "❌ 错误: 源码未解压，请检查 dl 文件夹。"
    exit 1
fi

# 5. 稳健编译
echo ">>> [3/3] 启动独立编译..."
rm -rf staging_dir/host/stamp/.rust_installed
export CARGO_NET_OFFLINE=true
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

env -u CI -u GITHUB_ACTIONS make "${RUST_LOGIC_PATH}/host/compile" -j$T V=s
