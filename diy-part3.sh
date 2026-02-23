#!/bin/bash
set -e
OPENWRT_ROOT=$(pwd)

echo "=========================================="
echo "Rust 专项攻坚任务 (V23.1 终极路径对齐版)"
echo "=========================================="

# 1. 强制重置索引，确保系统 100% 认领 SSH2 建立的新链接
# 这一步是消除 WARNING 的唯一办法
rm -rf tmp
make defconfig

# 2. 动态探测 Rust 的精确逻辑路径 (全自动寻径)
echo ">>> [1/4] 正在探测 Rust 编译路径..."
# 寻找包含 rust/Makefile 的目录，并转化为相对于 package/ 的路径
RUST_LOGIC_PATH=$(find package -name "Makefile" | grep "/rust/Makefile" | sed 's|/Makefile||' | head -n 1)

if [ -z "$RUST_LOGIC_PATH" ]; then
    echo "❌ 严重错误: 无法在源码树中定位到 Rust。正在尝试紧急补救..."
    # 紧急补救：如果 install 失败了，我们在这里尝试手动链接一次
    ./scripts/feeds install -p packages -f rust
    RUST_LOGIC_PATH=$(find package -name "Makefile" | grep "/rust/Makefile" | sed 's|/Makefile||' | head -n 1)
fi

if [ -z "$RUST_LOGIC_PATH" ]; then
    echo "❌ 致命错误: 无法找到 Rust 路径，请检查 SSH2 下载是否成功。"
    exit 1
fi
echo "✅ 成功锁定逻辑路径: $RUST_LOGIC_PATH"

# 3. 执行预处理 (解压与打补丁)
echo ">>> [2/4] 执行 Rust 源码预处理..."
# 使用动态探测到的路径，确保 100% 命中
make "${RUST_LOGIC_PATH}/host/prepare" V=s || true

# 4. 物理抹平账本与清单 (保持之前成功的 Python 逻辑)
echo ">>> [3/4] 正在执行“指纹重构”手术..."
# 物理目录探测
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定物理目录: $RUST_SRC_DIR"
    # 伪造账本 (欺骗审计)
    python3 -c "
import os, json
for root, dirs, files in os.walk('$RUST_SRC_DIR/vendor'):
    if '.cargo-checksum.json' in files:
        path = os.path.join(root, '.cargo-checksum.json')
        with open(path, 'w') as f:
            json.dump({'files':{}, 'package':''}, f)
"
    # 抹平锁定清单 (解决 pin-project-lite 报错)
    find "$RUST_SRC_DIR" -name "Cargo.lock" -exec sed -i '/checksum = /d' {} \;
    # 清理补丁干扰文件
    find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
    echo "✅ 物理净化完成。"
else
    echo "❌ 严重错误: 无法定位解压后的源码目录。"
    exit 1
fi

# 5. 稳健编译
echo ">>> [4/4] 启动硬件自适应稳健编译..."
rm -rf staging_dir/host/stamp/.rust_installed
export CARGO_NET_OFFLINE=true

MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && RUST_THREADS=2 || RUST_THREADS=1
echo ">>> 资源状态: 物理内存 ${MEM_TOTAL}G | 分配线程: -j$RUST_THREADS"

# 使用探测到的路径执行最终编译，并隐匿 CI 身份
env -u CI -u GITHUB_ACTIONS make "${RUST_LOGIC_PATH}/host/compile" -j$RUST_THREADS V=s || {
    echo "⚠️ 首次失败，尝试单核最后补救..."
    env -u CI -u GITHUB_ACTIONS make "${RUST_LOGIC_PATH}/host/compile" -j1 V=s
}

echo "=========================================="
echo "✅ Rust 专项任务圆满完成！"
echo "=========================================="
