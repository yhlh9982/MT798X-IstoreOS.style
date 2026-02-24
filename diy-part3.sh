#!/bin/bash
# diy-part3.sh
set -e
OPENWRT_ROOT="/workdir/openwrt"
cd "$OPENWRT_ROOT"

echo "=========================================="
echo "执行 SSH3: Rust 专项攻坚 (V29.1 哈希对齐版)"
echo "=========================================="

# 1. 建立硬链接入口 (防止 feeds 脚本抽风)
RUST_PHYSICAL=$(find feeds/packages -type d -name "rust" | head -n 1)
if [ -n "$RUST_PHYSICAL" ]; then
    rm -rf package/rust
    ln -sf "../$RUST_PHYSICAL" package/rust
fi

# 2. 刷新索引
rm -rf tmp
make defconfig

# 3. 执行预处理
echo ">>> [1/3] 执行源码解压..."
# 由于 SSH2 已经对齐了哈希，这次 make prepare 一定会成功下载并解压
make package/rust/host/prepare V=s || make package/feeds/packages/rust/host/prepare V=s

# 4. 账本伪装手术
echo ">>> [2/3] 执行指纹重构手术..."
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
echo ">>> [3/3] 启动独立编译阶段..."
rm -rf staging_dir/host/stamp/.rust_installed

# 这里导出所有必要的欺骗变量
export CARGO_NET_OFFLINE=true
export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_INCREMENTAL=0

MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
[ "$MEM_TOTAL" -gt 12 ] && T=2 || T=1

# 隐匿 CI 身份执行
env -u CI -u GITHUB_ACTIONS make package/rust/host/compile -j$T V=s
