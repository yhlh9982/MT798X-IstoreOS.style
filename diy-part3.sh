#!/bin/bash
# diy-part3.sh
set -e
OPENWRT_ROOT="/workdir/openwrt"
cd "$OPENWRT_ROOT"

# 1. 手动把工具链路径加入环境变量，防止 bootstrap 找不到 gcc
TOOLCHAIN_BIN=$(find "$OPENWRT_ROOT/staging_dir" -type d -name "bin" | grep "toolchain" | head -n 1)
export PATH="$TOOLCHAIN_BIN:$PATH"

# 2. 执行逻辑寻址与 prepare (保持 V31.0 逻辑)
RUST_LOGIC_PATH=$(find package -name "Makefile" | grep "/rust/Makefile" | sed 's|/Makefile||' | head -n 1)
make "${RUST_LOGIC_PATH}/host/prepare" V=s || true

# 3. 指纹重构 (Python)
RUST_SRC_DIR=$(find build_dir -type d -name "rustc-*-src" | head -n 1)
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

# 4. 稳健编译
rm -rf staging_dir/host/stamp/.rust_installed

# 实时注入欺骗变量
export CARGO_NET_OFFLINE=true
export CARGO_PROFILE_RELEASE_DEBUG=false
export CARGO_INCREMENTAL=0

# 隐匿 CI 身份启动编译
env -u CI -u GITHUB_ACTIONS make "${RUST_LOGIC_PATH}/host/compile" -j1 V=s
