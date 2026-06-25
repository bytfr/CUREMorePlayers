#!/bin/bash
# ============================================================
# cure_unlock - Metamod 扩展编译脚本 (Linux)
# ============================================================
# 用法:
#   ./build.sh              # 默认 32 位 (Source 引擎)
#   ./build.sh 64           # 强制 64 位
#   ./build.sh clean        # 清理构建产物
# ============================================================

set -e

ARCH_BIT="${1:-32}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/cure_unlock.cpp"
OUT_DIR="${SCRIPT_DIR}/build"
OUT="${OUT_DIR}/cure_unlock"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[CURE-Unlock]${NC} $1"; }
warn()  { echo -e "${YELLOW}[CURE-Unlock]${NC} $1"; }
error() { echo -e "${RED}[CURE-Unlock]${NC} $1"; }

# 清理
if [ "$ARCH_BIT" = "clean" ]; then
    info "Cleaning..."
    rm -rf "${OUT_DIR}"
    info "Done."
    exit 0
fi

# 检查源码
if [ ! -f "${SRC}" ]; then
    error "Source not found: ${SRC}"
    exit 1
fi

# 检查编译器
if ! command -v g++ >/dev/null 2>&1; then
    error "g++ not found. Install: sudo apt install g++ gcc-multilib g++-multilib"
    exit 1
fi

# 选择架构
if [ "$ARCH_BIT" = "32" ]; then
    ARCH_FLAG="-m32"
    OUT="${OUT}.so"
    info "Building 32-bit (Source engine standard)"
elif [ "$ARCH_BIT" = "64" ]; then
    ARCH_FLAG="-m64"
    OUT="${OUT}_64.so"
    warn "Building 64-bit (most Source mods are 32-bit, verify before use)"
else
    error "Unknown arg: $ARCH_BIT (use 32, 64, or clean)"
    exit 1
fi

# 检查 32 位支持
if [ "$ARCH_BIT" = "32" ]; then
    if ! echo '#include <stdio.h>
int main(){return 0;}' | g++ -m32 -x c++ - -o /dev/null 2>/dev/null; then
        error "32-bit build support missing. Install:"
        error "  Debian/Ubuntu: sudo apt install gcc-multilib g++-multilib"
        error "  CentOS/RHEL:   sudo yum install glibc-devel.i686 libstdc++-devel.i686"
        exit 1
    fi
fi

mkdir -p "${OUT_DIR}"

info "Source: ${SRC}"
info "Output: ${OUT}"
info "Compiling..."

# 编译参数
# -shared:        生成共享库
# -fPIC:          位置无关代码
# -fvisibility=hidden: 默认隐藏符号 (只导出 CreateInterface)
# -std=c++11:     C++11 标准
# -O2:            优化
# -Wall:          警告
# -ldl:           链接 libdl (dlsym 等)
g++ ${ARCH_FLAG} \
    -shared -fPIC \
    -fvisibility=hidden \
    -std=c++11 \
    -O2 -Wall \
    -o "${OUT}" \
    "${SRC}" \
    -ldl

if [ $? -eq 0 ]; then
    info "Build OK"
    info ""
    info "Install to server:"
    info "  cp ${OUT} <server>/addons/metamod/bin/"
    info ""
    info "VDF config (already in this folder):"
    info "  cp cure_unlock.vdf <server>/addons/metamod/"
else
    error "Build FAILED"
    exit 1
fi
