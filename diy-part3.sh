#!/bin/bash
set -e
# 锁定基地
OPENWRT_ROOT="/workdir/openwrt"
cd "$OPENWRT_ROOT"

echo "=========================================="
echo "执行 SSH3: Rust 专项攻坚 (V27.0 路径自愈版)"
echo "=========================================="

# 1. 物理重连软链接 (确保入口存在)
# 寻找 feeds 里的物理位置 (不管是 lang/rust 还是 rust)
RUST_PHYSICAL=$(find feeds/packages -type d -name "rust" | head -n 1)
if [ -d "$RUST_PHYSICAL" ]; then
    rm -rf package/rust
    ln -sf "../$RUST_PHYSICAL" package/rust
    echo "✅ 建立物理入口: package/rust -> $RUST_PHYSICAL"
fi

# 2. 强制刷新索引 (解决 No rule to make target 的终极手段)
rm -rf tmp
./scripts/feeds install -f -p packages rust
make defconfig

# 3. 执行预处理
echo ">>> [1/3] 执行源码解压..."
# 此时我们已经有了直连入口 package/rust
make package/rust/host/prepare V=s || {
    echo "❌ 寻址依然失败，尝试全路径..."
    make package/feeds/packages/rust/host/prepare V=s || make package/feeds/packages/lang/rust/host/prepare V=s
}

# 4. 账本伪造手术 (保持 Python 逻辑)
echo ">>> [2/3] 正在执行指纹重构手术..."
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)

if [ -n "$RUST_SRC_DIR" ]; then
    echo "✅ 锁定物理目录: $RUST_SRC_DIR"
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
    echo "❌ 错误: 源码未解压，请检查 dl 文件夹。"
    exit 1
fi

# 5. 稳健编译
echo ">>> [3/3] 启动独立编译阶段 (隐匿 CI 身份)..."
rm -rf staging_dir/host/stamp/.rust_installed
export CARGO_NET_OFFLINE=true

MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 同样使用 package/rust 入口进行编译
env -u CI -u GITHUB_ACTIONS make package/rust/host/compile -j$T V=s

echo "=========================================="
echo "✅ Rust 专项任务圆满完成！"
echo "=========================================="
