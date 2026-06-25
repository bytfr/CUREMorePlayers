# cure_unlock - Codename CURE 人数上限破解

基于 l4dtoolz 原理的 Metamod C++ 扩展，通过修改引擎内存中的 `sv.m_nMaxclients`
突破 CURE mod 硬编码的 5 人上限。

## 工作原理

1. 实现 `IServerPluginCallbacks` 接口，由 metamod 通过 VDF 加载
2. `Load()` 阶段获取 `IVEngineServer` 接口，扫描其 vtable 找到引擎 `sv` 全局指针
3. `ServerActivate()` 阶段在 `sv` 结构中定位 `m_nMaxclients` 字段并改写为 32

与 SourceMod 插件不同，本扩展直接操作引擎内存，可绕过 mod 二进制层面的硬编码限制。

## 文件结构

```
cure_unlock/
├── cure_unlock.cpp   # 扩展源码 (自包含, 无外部 SDK 依赖)
├── build.sh          # Linux 编译脚本
├── Makefile          # Linux Makefile (make / make 64 / make clean)
├── cure_unlock.vdf   # metamod 加载配置
└── README.md         # 本文件
```

## 编译 (Linux)

源码自包含，不需要 metamod SDK 或 Source SDK 头文件。

### 安装编译依赖

```bash
# Debian / Ubuntu
sudo apt update
sudo apt install g++ gcc-multilib g++-multilib

# CentOS / RHEL
sudo yum install gcc-c++ glibc-devel.i686 libstdc++-devel.i686
```

### 编译

```bash
cd cure_unlock
chmod +x build.sh
./build.sh              # 默认 32 位 (Source 引擎标准)
# 或
make                    # 等效
```

输出: `build/cure_unlock.so`

> CURE 基于 Source SDK 2013，是 32 位程序，必须编译为 32 位。

## 安装到服务器

假设服务器游戏目录为 `<cure>` (包含 `bin/`、`cure/`、`addons/` 等):

### 1. 复制扩展二进制

```bash
cp build/cure_unlock.so <cure>/addons/metamod/bin/cure_unlock.so
```

### 2. 复制 VDF 配置

```bash
cp cure_unlock.vdf <cure>/addons/metamod/cure_unlock.vdf
```

VDF 中的 `"file" "bin/cure_unlock"` 是相对 `addons/metamod/` 目录的路径，
metamod 会自动追加平台后缀 (`.so` / `.dll`)，最终加载
`addons/metamod/bin/cure_unlock.so`。

### 3. 确认启动参数

服务器启动参数仍需保留 `-maxplayers 32`:

```bash
./srcds_run -game cure -maxplayers 32 +map ...
```

> `-maxplayers` 决定引擎分配的 edict/socket 数量上限，扩展只是把 mod
> 内部 `sv.m_nMaxclients` 从 5 改写为 32，不会扩大引擎底层资源池。

### 4. 重启服务器并验证

启动后控制台应出现:

```
[CURE-Unlock] ===== Loading =====
[CURE-Unlock] IVEngineServer vtable: 0x...
[CURE-Unlock] sv ptr: FOUND
[CURE-Unlock] Target maxclients: 32
[CURE-Unlock] ===== Load complete =====
[CURE-Unlock] ServerActivate: clientMax=5, target=32
[CURE-Unlock] sv.m_nMaxclients: 5 -> 32 (idx=0x41)
```

地图加载完成后用 `meta list` 应能看到 `cure_unlock` 已加载。

## 排错

### `meta list` 看不到扩展
- 确认 `cure_unlock.vdf` 在 `addons/metamod/` 下
- 确认 `cure_unlock.so` 在 `addons/metamod/bin/` 下
- 确认 `.so` 是 32 位: `file cure_unlock.so` 应包含 `ELF 32-bit`

### `[CURE-Unlock] sv ptr: NOT FOUND`
- vtable 偏移与 l4dtoolz 不同，扩展会在 `ServerActivate` 重试
- 若仍失败，控制台会 dump `sv[0..0xFF]`，把日志发回以调整偏移

### `[CURE-Unlock] maxcl offset not found`
- `sv` 结构中找不到值为 5 的字段
- 控制台会 dump `sv[0..0xFF]` 的整数值，据此调整 `find_maxcl_offset`

### 服务器启动崩溃
- 立即移除 `cure_unlock.vdf` 并重启
- 把崩溃前的控制台日志发回分析
- 可能是 vtable 偏移不对，需要针对 CURE 二进制调整 `SV_IDX_L4D2`

## 偏移调整

源码顶部三个关键偏移来自 l4dtoolz (L4D2)，CURE 可能不同:

```cpp
#define SV_IDX_L4D2     0x80   // IVEngineServer vtable 中获取 sv 的方法索引
#define MAXCL_IDX_L4D2  0x41   // sv 结构中 m_nMaxclients 的偏移 (int 单位)
#define GP_MAXCL_OFF    0x14   // CGlobalVars.maxClients 偏移
```

`find_sv_ptr` 已尝试多个候选索引 (0x7E~0x85)，`find_maxcl_offset` 会
在 `sv` 结构中自动扫描值为 `clientMax` (5) 的字段，多数情况下无需手动调整。

## 与 SourceMod 插件的关系

之前的 `cure_moreplayers.smx` 只能诊断不能破解，因为 SourceMod 的
`GetMaxClients()` 直接读取 mod 内部状态，cvar 修改路径完全无效。
本扩展在更底层 (引擎内存) 操作，是突破硬编码限制的唯一可行方案。
