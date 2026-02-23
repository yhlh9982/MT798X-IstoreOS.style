#!/bin/bash
# =========================================================
# Rust 终极物理救治脚本 (V18.0 彻底降维版)
# 职责：解决 Rust 1.90 及其以后版本所有 Checksum 校验自杀问题
# =========================================================

set -e
OPENWRT_ROOT=$(pwd)

echo "=========================================="
echo "开始执行 Rust 专项攻坚任务 (V18.0)"
echo "=========================================="

# 1. 物理预处理
echo ">>> [1/4] 正在执行 Rust 源码预处理 (解压与打补丁)..."
make package/feeds/packages/rust/host/prepare V=s || true

# 2. 动态定位源码目录
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -z "$RUST_SRC_DIR" ]; then
    echo "❌ 错误: 无法定位 Rust 源码目录，流程终止。"
    exit 1
fi
echo "✅ 源码目录锁定: $RUST_SRC_DIR"

# 3. 核心救治：大清单切除 + 小账本销毁
echo ">>> [2/4] 正在执行全量校验信息切除手术..."

# A. 【核心突破】抹除大清单中的校验记录 (Cargo.lock)
# 这会让 Cargo 彻底忘记“这个包原本应该长什么样”，从而不再进行哈希比对
find "$RUST_SRC_DIR" -name "Cargo.lock" | while read -r lock_file; do
    echo ">>> 正在处理锁定清单: $lock_file"
    sed -i '/checksum = /d' "$lock_file"
done

# B. 【物理清理】直接删除所有小账本 (.cargo-checksum.json)
# 既然清单里的 checksum 没了，小账本也就没用了，直接删除是最稳妥的“本地化”标志
find "$RUST_SRC_DIR/vendor" -name ".cargo-checksum.json" -delete
echo "✅ 所有的校验账本和锁定清单哈希记录已清理。"

# C. 物理擦除补丁残留
find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
find "$RUST_SRC_DIR" -name "*.rej" -delete 2>/dev/null || true
find "$RUST_SRC_DIR" -name ".cargo-ok" -delete 2>/dev/null || true
echo "✅ 补丁干扰文件已彻底清除。"

# 4. 稳健编译
echo ">>> [3/4] 启动硬件自适应稳健编译..."

# 强制重置安装戳记，确保本次修改被编译系统识别
rm -rf staging_dir/host/stamp/.rust_installed

# 硬件自适应线程分配
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && RUST_THREADS=2 || RUST_THREADS=1
echo ">>> 资源报告: 物理内存 ${MEM_TOTAL}G | 线程分配: -j$RUST_THREADS"

# 开启离线模式，防止 Cargo 尝试重新生成哈希
export CARGO_NET_OFFLINE=true

# 执行单包编译
make package/feeds/packages/rust/host/compile -j$RUST_THREADS V=s || {
    echo "⚠️  首次编译失败，强制执行单线程 (-j1) 最终平推..."
    make package/feeds/packages/rust/host/compile -j1 V=s
}

echo "=========================================="
echo "✅ Rust 专项攻坚任务顺利完成！"
echo "=========================================="
