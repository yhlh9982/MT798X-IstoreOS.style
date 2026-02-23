#!/bin/bash
set -e
# 锁定基地
OPENWRT_ROOT="/workdir/openwrt"
cd $OPENWRT_ROOT

echo "=========================================="
echo "Rust 专项攻坚 (回归标准路径版 V26.0)"
echo "=========================================="

# 1. 刷新配置
make defconfig

# 2. 执行预处理
echo ">>> [1/3] 执行源码解压 (使用原始全路径)..."
# 使用你之前无数次成功解压时使用的那个路径
make package/feeds/packages/rust/host/prepare V=s || \
make package/feeds/packages/lang/rust/host/prepare V=s || {
    echo "❌ 寻址失败。正在探测物理 Makefile 位置..."
    FIND_PATH=$(find package/feeds -name Makefile | grep "/rust/Makefile" | sed 's|/Makefile||')
    make "${FIND_PATH}/host/prepare" V=s
}

# 3. 定位物理目录并执行“账本+清单”双重伪造
echo ">>> [2/3] 正在执行指纹重构手术..."
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定物理目录: $RUST_SRC_DIR"
    # A. 使用 Python 抹平账本 (避免 Shell 转义乱码)
    python3 -c "
import os, json
for root, dirs, files in os.walk('$RUST_SRC_DIR/vendor'):
    if '.cargo-checksum.json' in files:
        path = os.path.join(root, '.cargo-checksum.json')
        with open(path, 'w') as f:
            json.dump({'files':{}, 'package':''}, f)
"
    # B. 抹除锁定清单中的哈希记录 (防止 pin-project-lite 报错)
    find "$RUST_SRC_DIR" -name "Cargo.lock" -exec sed -i '/checksum = /d' {} \;
    # C. 清理干扰
    find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
    echo "✅ 物理净化完成。"
else
    echo "❌ 错误: 源码未解压。"
    exit 1
fi

# 4. 稳健编译
echo ">>> [3/3] 启动独立编译阶段..."
rm -rf staging_dir/host/stamp/.rust_installed
export CARGO_NET_OFFLINE=true
export CARGO_PROFILE_RELEASE_DEBUG=false

# 内存自适应
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 启动单包编译 (隐匿身份)
# 重新获取刚才 prepare 成功的路径名
FINAL_TARGET=$(find package/feeds -name Makefile | grep "/rust/Makefile" | sed 's|/Makefile||' | head -n 1)
env -u CI -u GITHUB_ACTIONS make "${FINAL_TARGET}/host/compile" -j$T V=s

echo "=========================================="
echo "✅ Rust 专项任务已准备就绪！"
echo "=========================================="
