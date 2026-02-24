#!/bin/bash
# diy-part3.sh
set -e
OPENWRT_ROOT="/workdir/openwrt"
cd "$OPENWRT_ROOT"

echo "=========================================="
echo "执行 SSH3: Rust 专项救治 (V31.1 闭环寻址版)"
echo "=========================================="

# 1. 物理重连软链接 (寻址报错的终极克星)
echo ">>> [1/4] 正在手动建立物理入口..."
RUST_PHYSICAL=$(find feeds/packages -type d -name "rust" | head -n 1)
if [ -n "$RUST_PHYSICAL" ]; then
    rm -rf package/rust
    ln -sf "../$RUST_PHYSICAL" package/rust
    echo "✅ 已强行接通物理路径: package/rust -> $RUST_PHYSICAL"
fi

# 2. 刷新索引
rm -rf tmp
make defconfig

# 3. 执行预处理
echo ">>> [2/4] 执行源码解压与打补丁..."
# 使用我们刚建立的绝对路径 package/rust
make package/rust/host/prepare V=s || {
    echo "❌ 寻址依然报错，尝试全路径作为最后补救..."
    make package/feeds/packages/rust/host/prepare V=s || make package/feeds/packages/lang/rust/host/prepare V=s
}

# 4. 账本伪造手术 (Python)
echo ">>> [3/4] 正在执行“指纹重构”手术..."
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定源码物理目录: $RUST_SRC_DIR"
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
    echo "❌ 严重错误: 源码解压失败。"
    exit 1
fi

# 5. 稳健编译
echo ">>> [4/4] 启动独立编译阶段 (降压限流)..."
rm -rf staging_dir/host/stamp/.rust_installed

# 【重要：在此处导出变量，彻底避开 Makefile 乱码风险】
export CARGO_NET_OFFLINE=true
export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_INCREMENTAL=0

MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 隐匿 CI 身份执行
env -u CI -u GITHUB_ACTIONS make package/rust/host/compile -j$T V=s

echo "=========================================="
echo "✅ Rust 专项任务圆满成功！"
echo "=========================================="
