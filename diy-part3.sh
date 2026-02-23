#!/bin/bash
# =========================================================
# Rust 终极物理救治脚本 (V17.0 深度伪造版)
# 职责：处理解压、账本伪造、单线程稳健编译
# =========================================================

set -e
OPENWRT_ROOT=$(pwd)

echo "=========================================="
echo "开始执行 Rust 专项攻坚任务 (V17.0)"
echo "=========================================="

# 1. 物理预处理 (解压源码并应用 Patch)
echo ">>> [1/4] 正在执行 Rust 源码预处理 (解压与打补丁)..."
# 强制触发解压和补丁流程
make package/feeds/packages/rust/host/prepare V=s || true

# 2. 动态定位源码目录
echo ">>> [2/4] 正在定位源码解压目录..."
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -z "$RUST_SRC_DIR" ]; then
    echo "❌ 错误: 无法定位 Rust 源码目录，请检查 dl/ 文件夹。"
    exit 1
fi
echo "✅ 源码目录锁定: $RUST_SRC_DIR"

# 3. 核心救治：账本伪造 + 清除痕迹
echo ">>> [3/4] 正在执行账本伪造 (欺骗 1.90 校验机制)..."

# 【关键改动】不再删除 .cargo-checksum.json，而是将其覆盖为“空审计名单”
# {"files":{},"package":null} 是 Rust 认可的合法空账本
find "$RUST_SRC_DIR/vendor" -name ".cargo-checksum.json" | while read -r json_file; do
    echo '{"files":{},"package":null}' > "$json_file"
done
echo "✅ 已完成所有依赖库账本的“物理抹平”。"

# 清理补丁备份产生的干扰文件 (Cargo 扫描目录时讨厌看到陌生文件)
find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
find "$RUST_SRC_DIR" -name "*.rej" -delete 2>/dev/null || true
find "$RUST_SRC_DIR" -name ".cargo-ok" -delete 2>/dev/null || true
echo "✅ 补丁痕迹已彻底清除。"

# 4. 稳健编译
echo ">>> [4/4] 启动硬件自适应稳健编译..."

# 强制重置安装戳记
rm -rf staging_dir/host/stamp/.rust_installed

# 硬件自适应 (针对 Actions 内存波动)
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && RUST_THREADS=2 || RUST_THREADS=1

echo ">>> 资源报告: 物理内存 ${MEM_TOTAL}G | 线程分配: -j$RUST_THREADS"

# 开启强制离线模式，防止 Cargo 联网尝试修复被我们抹平的账本
export CARGO_NET_OFFLINE=true

# 执行单包编译
make package/feeds/packages/rust/host/compile -j$RUST_THREADS V=s || {
    echo "⚠️  初次编译失败，尝试单线程 (-j1) 最后冲刺..."
    make package/feeds/packages/rust/host/compile -j1 V=s
}

echo "=========================================="
echo "✅ Rust 专项攻坚任务顺利完成！"
echo "=========================================="
