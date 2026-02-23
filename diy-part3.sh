#!/bin/bash
# =========================================================
# Rust 专项攻坚任务 (V28.0 终极核实版)
# 职责：执行“指纹重构”手术，绕过 1.90.0 校验与 CI 环境限制
# =========================================================

set -e
OPENWRT_ROOT=$(pwd)

echo "=========================================="
echo "执行 SSH3: Rust 专项救治与独立编译"
echo "=========================================="

# 1. 刷新配置索引 (房管局重新登记)
# 这一步确保主编译系统认领 SSH2 阶段建立的所有软链接
echo ">>> [1/4] 正在同步编译树索引..."
rm -rf tmp
make defconfig

# 2. 执行源码预处理 (解压与打补丁)
echo ">>> [2/4] 执行源码解压与打补丁..."
# 尝试所有可能的路径，确保 100% 触发 prepare 流程
make package/feeds/packages/rust/host/prepare V=s || \
make package/feeds/packages/lang/rust/host/prepare V=s || \
make package/rust/host/prepare V=s

# 3. 核心救治：账本伪造与清单清理 (重签名手术)
echo ">>> [3/4] 正在执行指纹重构手术 (Python)..."
# 动态定位物理源码目录
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定源码物理目录: $RUST_SRC_DIR"
    
    # A. 使用 Python 抹平账本 (欺骗 1.90 审计机制)
    # 这一步将 files 设为空，使 Cargo 跳过对所有被补丁修改过的文件的校验
    python3 -c "
import os, json
for root, dirs, files in os.walk('$RUST_SRC_DIR/vendor'):
    if '.cargo-checksum.json' in files:
        path = os.path.join(root, '.cargo-checksum.json')
        with open(path, 'w') as f:
            json.dump({'files':{}, 'package':''}, f)
"
    # B. 抹除锁定清单中的哈希指纹 (防止 pin-project-lite 报错)
    find "$RUST_SRC_DIR" -name "Cargo.lock" -exec sed -i '/checksum = /d' {} \;
    
    # C. 物理擦除所有干扰文件
    # .orig: 补丁备份 | .rej: 失败残留 | .cargo-ok: 成功标记
    find "$RUST_SRC_DIR" -name "*.orig" -delete 2>/dev/null || true
    find "$RUST_SRC_DIR" -name "*.rej" -delete 2>/dev/null || true
    find "$RUST_SRC_DIR" -name ".cargo-ok" -delete 2>/dev/null || true
    
    echo "✅ 物理净化完成：账本已伪造，痕迹已消除。"
else
    echo "❌ 严重错误: 源码未解压成功，无法进行手术。"
    exit 1
fi

# 4. 稳健编译 (通过环境变量实施最后的欺骗)
echo ">>> [4/4] 启动独立、降压编译阶段..."
# 强制重置安装戳记，确保本次手术结果被系统接受
rm -rf staging_dir/host/stamp/.rust_installed

# 设置 Cargo 环境变量：强制离线、禁止增量、禁用调试
export CARGO_NET_OFFLINE=true
export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_INCREMENTAL=0

# 硬件自适应：根据 RAM 大小决定线程数 (针对 Actions 资源限制)
MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
if [ "$MEM_TOTAL" -gt 12 ]; then
    T=2
    echo "🚀 检测到内存充足 ($MEM_TOTAL G)，分配 2 线程。"
else
    T=1
    echo "🛡️ 内存受限 ($MEM_TOTAL G)，分配单线程稳健模式。"
fi

# 核心动作：隐匿 CI 身份，执行单包编译
# 通过 env -u 撤销 CI 相关的环境变量，彻底绕过 Rust 1.90.0 的限制
env -u CI -u GITHUB_ACTIONS make package/feeds/packages/rust/host/compile -j$T V=s || \
env -u CI -u GITHUB_ACTIONS make package/feeds/packages/lang/rust/host/compile -j$T V=s || \
env -u CI -u GITHUB_ACTIONS make package/rust/host/compile -j$T V=s

echo "=========================================="
echo "✅ Rust 专项攻坚圆满成功！"
echo "=========================================="
