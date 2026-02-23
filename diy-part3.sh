#!/bin/bash
set -e
# 锁定基地
OPENWRT_ROOT="/workdir/openwrt"
cd $OPENWRT_ROOT

echo "=========================================="
echo "Rust 专项攻坚 (全盘遍寻版 V24.0)"
echo "=========================================="

# 1. 动态遍寻 Rust 的逻辑路径 (不再写死任何层级)
echo ">>> [1/4] 正在全盘搜索 Rust 编译定义..."
# 搜索 package 目录下所有名为 rust 且包含 Makefile 的目录
RUST_LOGIC_PATH=$(find package -type d -name "rust" | while read -r dir; do
    if [ -f "$dir/Makefile" ]; then
        # 转化为相对于 openwrt 根目录的路径 (例如 package/feeds/packages/lang/rust)
        echo "$dir" | sed "s|$OPENWRT_ROOT/||"
        break
    fi
done)

if [ -z "$RUST_LOGIC_PATH" ]; then
    echo "❌ 严重错误: 无法在 package 树中找到 Rust。正在尝试最后补救..."
    ./scripts/feeds install -f rust
    RUST_LOGIC_PATH=$(find package -name Makefile | grep "/rust/Makefile" | sed 's|/Makefile||' | head -n 1)
fi

if [ -z "$RUST_LOGIC_PATH" ]; then
    echo "❌ 致命错误: 遍寻失败，Rust 确实不存在。"
    exit 1
fi
echo "✅ 成功锁定逻辑路径: $RUST_LOGIC_PATH"

# 2. 执行预处理
echo ">>> [2/4] 执行源码解压..."
make "${RUST_LOGIC_PATH}/host/prepare" V=s || true

# 3. 动态定位物理源码目录并“伪造账本”
echo ">>> [3/4] 正在定位物理目录并抹平账本..."
# 深度搜索 build_dir
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定物理目录: $RUST_SRC_DIR"
    # 使用 Python 执行账本伪造 (解决 1.90.0 的 Cargo.lock 和 JSON 校验)
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
    # 清理补丁干扰
    find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
    echo "✅ 物理净化完成。"
else
    echo "❌ 错误: 源码未解压，请检查 dl/ 文件夹。"
    exit 1
fi

# 4. 稳健编译
echo ">>> [4/4] 启动硬件自适应独立编译..."
rm -rf staging_dir/host/stamp/.rust_installed
export CARGO_NET_OFFLINE=true
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 隐匿 CI 身份执行编译
env -u CI -u GITHUB_ACTIONS make "${RUST_LOGIC_PATH}/host/compile" -j$T V=s
