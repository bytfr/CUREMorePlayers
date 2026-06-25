# ============================================================
# cure_unlock - Metamod 扩展 Makefile (Linux)
# ============================================================
# 用法:
#   make            # 默认 32 位
#   make 64         # 64 位
#   make clean      # 清理
#   make install    # 编译并提示安装路径
# ============================================================

CXX      ?= g++
CXXFLAGS ?= -std=c++11 -O2 -Wall -fvisibility=hidden
LDFLAGS  ?= -ldl

SRC := cure_unlock.cpp
OUT_DIR := build
TARGET_32 := $(OUT_DIR)/cure_unlock.so
TARGET_64 := $(OUT_DIR)/cure_unlock_64.so

.PHONY: all 32 64 clean install help

all: 32

32: $(TARGET_32)

64: $(TARGET_64)

$(TARGET_32): $(SRC) | $(OUT_DIR)
	$(CXX) -m32 -shared -fPIC $(CXXFLAGS) -o $@ $< $(LDFLAGS)
	@echo "[CURE-Unlock] Built 32-bit: $@"

$(TARGET_64): $(SRC) | $(OUT_DIR)
	$(CXX) -m64 -shared -fPIC $(CXXFLAGS) -o $@ $< $(LDFLAGS)
	@echo "[CURE-Unlock] Built 64-bit: $@"

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

clean:
	rm -rf $(OUT_DIR)
	@echo "[CURE-Unlock] Cleaned."

install: 32
	@echo ""
	@echo "[CURE-Unlock] Build complete. Install steps:"
	@echo "  1) cp $(TARGET_32)         <server>/addons/metamod/bin/cure_unlock.so"
	@echo "  2) cp cure_unlock.vdf      <server>/addons/metamod/cure_unlock.vdf"
	@echo "  3) Restart server, check console for: [CURE-Unlock] ===== Loading ====="

help:
	@echo "Targets:"
	@echo "  make        - Build 32-bit (default, Source engine)"
	@echo "  make 64     - Build 64-bit"
	@echo "  make clean  - Remove build dir"
	@echo "  make install- Build 32-bit and show install steps"
	@echo ""
	@echo "Requirements (32-bit on 64-bit host):"
	@echo "  Debian/Ubuntu: sudo apt install g++ gcc-multilib g++-multilib"
	@echo "  CentOS/RHEL:   sudo yum install glibc-devel.i686 libstdc++-devel.i686"
