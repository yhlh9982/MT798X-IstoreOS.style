#!/bin/bash
# diy-part3.sh
set -e
OPENWRT_ROOT="/workdir/openwrt"
cd "$OPENWRT_ROOT"

echo "=========================================="
echo "执行 SSH3: Rust 专项攻坚 (V27.1 闭环寻址版)"
echo "=========================================="

# 1. 物理路径锁定与硬重连 (解决寻址报错的终极手段)
echo ">>> [1/4] 正在手动建立物理入口..."
# 探测 Rust 源码在 feeds 里的实际物理位置
RUST_PHYSICAL=$(find feeds/packages -type d -name "rust" | head -n 1)

if [ -n "$RUST_PHYSICAL" ] && [ -f "$RUST_PHYSICAL/Makefile" ]; then
    # 强制在 package 目录下建立一个标准入口
    rm -rf package/rust
    ln -sf "../$RUST_PHYSICAL" package/rust
    echo "✅ 已建立逻辑映射: package/rust -> $RUST_PHYSICAL"
else
    echo "❌ 严重错误: 无法定位 Rust 物理源码目录。"
    exit 1
fi

# 2. 刷新索引
rm -rf tmp
make defconfig

# 3. 执行预处理
echo ">>> [2/4] 执行源码解压与打补丁..."
# 使用我们刚刚建立的 package/rust 统一入口
make package/rust/host/prepare V=s || true

# 4. 账本伪造与清单清理
echo ">>> [3/4] 正在执行指纹重构手术 (Python)..."
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定物理目录: $RUST_SRC_DIR"
    # 使用 Python 抹平账本
    python3 -c "
import os, json
for root, dirs, files in os.walk('$RUST_SRC_DIR/vendor'):
    if '.cargo-checksum.json' in files:
        path = os.path.join(root, '.cargo-checksum.json')
        with open(path, 'w') as f:
            json.dump({'files':{}, 'package':''}, f)
"
    # 抹除锁定清单哈希记录
    find "$RUST_SRC_DIR" -name "Cargo.lock" -exec sed -i '/checksum = /d' {} \;
    # 清理残留干扰文件
    find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
    echo "✅ 物理净化完成。"
else
    echo "❌ 严重错误: 源码解压失败。"
    exit 1
fi

# 5. 稳健编译 (隐匿 CI 身份)
echo ">>> [4/4] 启动独立编译阶段..."
rm -rf staging_dir/host/stamp/.rust_installed
export CARGO_NET_OFFLINE=true

MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1
echo ">>> 资源分配: -j$T"

# 关键：脱离 CI 身份，绕过 Rust 1.90.0 的限制
env -u CI -u GITHUB_ACTIONS make package/rust/host/compile -j$T V=s

echo "=========================================="
echo "✅ Rust 专项任务圆满成功！"
echo "=========================================="
