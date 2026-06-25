/*
 * cure_unlock.cpp - Codename CURE 人数上限破解 Metamod:Source 插件
 *
 * 基于 engine_srv.so 和 server_srv.so 逆向分析:
 *
 * 1. engine_srv.so (引擎):
 *    - sv 全局变量 vaddr = 0x331580 (.bss 段)
 *    - m_nMaxclients 偏移 = 0x14c
 *    - 限制字段偏移 = 0x1f0 (必须同时修改)
 *
 * 2. server_srv.so (游戏 DLL):
 *    - CServerGameClients::GetPlayerLimits @ vaddr 0x008e6ae0
 *    - 函数内有 3 条 mov [eax], 5 指令, 把 min/max/default 都设为 5
 *    - 补丁: 把立即数 5 改成目标值, 让引擎按目标人数初始化缓冲区
 *
 * 双重补丁策略:
 * - 补丁 server_srv.so 的 GetPlayerLimits (根治: 让引擎按 32 人初始化)
 * - 修改 engine_srv.so 的 sv.m_nMaxclients (保险: 防止其他路径绕过)
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/mman.h>
#include <link.h>

// ===== 最小化类型声明 =====

typedef void* (*CreateInterfaceFn)(const char *pName, int *pReturnCode);

#define INTERFACEVERSION_VENGINESERVER "VEngineServer023"
#define METAMOD_PLAPI_NAME            "ISmmPlugin"
#define METAMOD_PLAPI_VERSION         16

typedef int PluginId;

// IMetamodListener 声明 (必须先于 ISmmAPI)
class IMetamodListener
{
public:
    virtual void OnPluginLoad(PluginId id) {}
    virtual void OnPluginUnload(PluginId id) {}
    virtual void OnPluginPause(PluginId id) {}
    virtual void OnPluginUnpause(PluginId id) {}
    virtual void OnLevelInit(char const *pMapName, char const *pMapEntities,
                             char const *pOldLevel, char const *pLandmarkName,
                             bool loadGame, bool background) {}
    virtual void OnLevelShutdown() {}
    virtual void *OnEngineQuery(const char *iface, int *ret) { if (ret) *ret = 1; return NULL; }
    virtual void *OnPhysicsQuery(const char *iface, int *ret) { if (ret) *ret = 1; return NULL; }
    virtual void *OnFileSystemQuery(const char *iface, int *ret) { if (ret) *ret = 1; return NULL; }
    virtual void *OnGameDLLQuery(const char *iface, int *ret) { if (ret) *ret = 1; return NULL; }
    virtual void *OnMetamodQuery(const char *iface, int *ret) { if (ret) *ret = 1; return NULL; }
    virtual void OnVSPListening(void *iface) {}
    virtual void OnUnlinkConCommandBase(PluginId id, void *pCommand) {}
};

// ISmmAPI 声明 (vtable 布局必须匹配)
class ISmmAPI
{
public:
    virtual void LogMsg(void *pl, const char *msg, ...) = 0;                    // 0
    virtual CreateInterfaceFn GetEngineFactory(bool syn = true) = 0;            // 1
    virtual CreateInterfaceFn GetPhysicsFactory(bool syn = true) = 0;           // 2
    virtual CreateInterfaceFn GetFileSystemFactory(bool syn = true) = 0;        // 3
    virtual CreateInterfaceFn GetServerFactory(bool syn = true) = 0;            // 4
    virtual void *GetCGlobals() = 0;                                            // 5
    virtual bool RegisterConCommandBase(void *plugin, void *pCommand) = 0;     // 6
    virtual void UnregisterConCommandBase(void *plugin, void *pCommand) = 0;   // 7
    virtual void ConPrint(const char *str) = 0;                                // 8
    virtual void ConPrintf(const char *fmt, ...) = 0;                          // 9
    virtual void GetApiVersions(int &major, int &minor, int &plvers, int &plmin) = 0; // 10
    virtual void GetShVersions(int &shvers, int &shimpl) = 0;                  // 11
    virtual void AddListener(void *plugin, IMetamodListener *pListener) = 0;   // 12
};

// ISmmPlugin 完整声明
class ISmmPlugin
{
public:
    virtual int  GetApiVersion() { return METAMOD_PLAPI_VERSION; }
    virtual ~ISmmPlugin() {}
    virtual bool Load(PluginId id, ISmmAPI *ismm, char *error, size_t maxlength, bool late) = 0;
    virtual void AllPluginsLoaded() {}
    virtual bool QueryRunning(char *error, size_t maxlen) { return true; }
    virtual bool Unload(char *error, size_t maxlen) { return true; }
    virtual bool Pause(char *error, size_t maxlen) { return true; }
    virtual bool Unpause(char *error, size_t maxlen) { return true; }
    virtual const char *GetAuthor() = 0;
    virtual const char *GetName() = 0;
    virtual const char *GetDescription() = 0;
    virtual const char *GetURL() = 0;
    virtual const char *GetLicense() = 0;
    virtual const char *GetVersion() = 0;
    virtual const char *GetDate() = 0;
    virtual const char *GetLogTag() = 0;
};

// ===== 来自逆向分析的精确偏移量 =====

// engine_srv.so
#define SV_VADDR          0x331580U   // sv 全局变量 vaddr
#define SV_MAXCL_OFF      0x14c       // sv->m_nMaxclients 偏移
#define SV_LIMIT_OFF      0x1f0       // sv->限制字段偏移

// server_srv.so
#define GPL_VADDR         0x008e6ae0U // CServerGameClients::GetPlayerLimits vaddr
#define GPL_SIZE          0x40        // 函数大小 (扫描范围)

#define TARGET_MAXCLIENTS 32

// ===== 全局状态 =====

static ISmmAPI *g_ismm = NULL;
static void    *g_engine = NULL;
static uintptr_t g_engine_base = 0;
static uintptr_t g_server_base = 0;
static uintptr_t *g_sv = NULL;
static int      g_target = TARGET_MAXCLIENTS;
static bool     g_server_patched = false;

// ===== 通过 /proc/self/maps 查找 .so 基址 =====

static uintptr_t find_so_base(const char *so_name)
{
    FILE *fp = fopen("/proc/self/maps", "r");
    if (!fp) return 0;

    char line[512];
    uintptr_t base = 0;
    while (fgets(line, sizeof(line), fp))
    {
        if (strstr(line, so_name))
        {
            uintptr_t start;
            char perms[8];
            uintptr_t offset;
            if (sscanf(line, "%x-%*x %s %x", &start, perms, &offset) == 3)
            {
                if (offset == 0)
                {
                    base = start;
                    break;
                }
            }
        }
    }
    fclose(fp);
    return base;
}

// ===== 修改内存保护并写入 =====

static bool patch_byte(uintptr_t addr, uint8_t old_val, uint8_t new_val)
{
    // 获取当前页保护
    long pagesize = sysconf(_SC_PAGESIZE);
    uintptr_t page = addr & ~(pagesize - 1);
    
    if (mprotect((void *)page, pagesize, PROT_READ | PROT_WRITE | PROT_EXEC) != 0)
    {
        printf("[CURE-Unlock] mprotect failed for 0x%08x\n", (unsigned)addr);
        return false;
    }
    
    uint8_t *p = (uint8_t *)addr;
    if (*p != old_val)
    {
        printf("[CURE-Unlock] WARNING: expected 0x%02x at 0x%08x, got 0x%02x\n",
               old_val, (unsigned)addr, *p);
        // 继续写入
    }
    
    *p = new_val;
    
    // 恢复保护
    mprotect((void *)page, pagesize, PROT_READ | PROT_EXEC);
    
    return true;
}

// ===== 补丁 server_srv.so 的 GetPlayerLimits =====
// 函数内有 3 条 "C7 00 05 00 00 00" (mov [eax], 5) 指令
// 把立即数 5 (在指令偏移 +2 处) 改成目标值
static void patch_get_player_limits()
{
    if (g_server_patched) return;
    
    if (!g_server_base)
    {
        g_server_base = find_so_base("server_srv.so");
        if (!g_server_base)
        {
            printf("[CURE-Unlock] ERROR: server_srv.so base not found\n");
            return;
        }
        printf("[CURE-Unlock] server_srv.so base: 0x%08x\n", (unsigned)g_server_base);
    }
    
    uintptr_t gpl_addr = g_server_base + GPL_VADDR;
    printf("[CURE-Unlock] GetPlayerLimits @ 0x%08x, scanning for mov [eax],5...\n",
           (unsigned)gpl_addr);
    
    // 扫描函数内的 "C7 00 05 00 00 00" 模式 (mov dword [eax], 5)
    uint8_t *code = (uint8_t *)gpl_addr;
    int patch_count = 0;
    
    for (int i = 0; i < GPL_SIZE; i++)
    {
        // mov dword [eax], 5:  C7 00 05 00 00 00
        if (code[i] == 0xC7 && code[i+1] == 0x00 &&
            code[i+2] == 0x05 && code[i+3] == 0x00 &&
            code[i+4] == 0x00 && code[i+5] == 0x00)
        {
            uintptr_t patch_addr = gpl_addr + i + 2;  // 立即数的位置
            printf("[CURE-Unlock]   found mov [eax],5 at offset +%d (0x%08x)\n",
                   i, (unsigned)patch_addr);
            
            if (patch_byte(patch_addr, 0x05, (uint8_t)g_target))
            {
                patch_count++;
                printf("[CURE-Unlock]   patched to %d\n", g_target);
            }
        }
        // 也检查 mov [ecx], 5: C7 01 05 00 00 00
        else if (code[i] == 0xC7 && code[i+1] == 0x01 &&
                 code[i+2] == 0x05 && code[i+3] == 0x00 &&
                 code[i+4] == 0x00 && code[i+5] == 0x00)
        {
            uintptr_t patch_addr = gpl_addr + i + 2;
            printf("[CURE-Unlock]   found mov [ecx],5 at offset +%d (0x%08x)\n",
                   i, (unsigned)patch_addr);
            
            if (patch_byte(patch_addr, 0x05, (uint8_t)g_target))
            {
                patch_count++;
                printf("[CURE-Unlock]   patched to %d\n", g_target);
            }
        }
    }
    
    printf("[CURE-Unlock] GetPlayerLimits patched: %d instructions\n", patch_count);
    g_server_patched = (patch_count > 0);
}

// ===== 修改 engine_srv.so 的 sv.m_nMaxclients =====

static void apply_engine_sv_patch()
{
    if (!g_sv)
    {
        if (!g_engine_base)
        {
            g_engine_base = find_so_base("engine_srv.so");
            if (!g_engine_base)
            {
                printf("[CURE-Unlock] ERROR: engine_srv.so base not found\n");
                return;
            }
        }
        
        g_sv = (uintptr_t *)(g_engine_base + SV_VADDR);
        printf("[CURE-Unlock] sv ptr: 0x%08x\n", (unsigned)g_sv);
    }
    
    int *p_maxcl = (int *)((uint8_t *)g_sv + SV_MAXCL_OFF);
    int *p_limit = (int *)((uint8_t *)g_sv + SV_LIMIT_OFF);
    
    int old_maxcl = *p_maxcl;
    int old_limit = *p_limit;
    
    printf("[CURE-Unlock] current: m_nMaxclients=%d, limit_field=%d\n", old_maxcl, old_limit);
    
    if (old_limit != g_target)
    {
        *p_limit = g_target;
        printf("[CURE-Unlock] sv.limit_field: %d -> %d\n", old_limit, *p_limit);
    }
    
    if (old_maxcl != g_target)
    {
        *p_maxcl = g_target;
        printf("[CURE-Unlock] sv.m_nMaxclients: %d -> %d\n", old_maxcl, *p_maxcl);
    }
}

// ===== 主修改函数 =====

static void apply_all_patches()
{
    printf("[CURE-Unlock] apply_all_patches() target=%d\n", g_target);
    
    // 1. 补丁 server_srv.so 的 GetPlayerLimits (根治)
    patch_get_player_limits();
    
    // 2. 修改 engine_srv.so 的 sv 字段 (保险)
    apply_engine_sv_patch();
}

// ===== 插件实现 =====

class cure_unlock : public ISmmPlugin, public IMetamodListener
{
public:
    bool Load(PluginId id, ISmmAPI *ismm, char *error, size_t maxlength, bool late);
    void AllPluginsLoaded();

    void OnLevelInit(char const *pMapName, char const *pMapEntities,
                     char const *pOldLevel, char const *pLandmarkName,
                     bool loadGame, bool background);

    const char *GetAuthor()      { return "CURE-MorePlayers"; }
    const char *GetName()        { return "CURE Unlock"; }
    const char *GetDescription() { return "Break CURE 5-player hard limit"; }
    const char *GetURL()         { return ""; }
    const char *GetLicense()     { return "MIT"; }
    const char *GetVersion()     { return "1.0.0"; }
    const char *GetDate()        { return "2026-06-25"; }
    const char *GetLogTag()      { return "CURE"; }
};

static cure_unlock g_instance;

extern "C" __attribute__((visibility("default")))
void *CreateInterface(const char *pName, int *pReturnCode)
{
    if (pName && strcmp(pName, METAMOD_PLAPI_NAME) == 0)
    {
        if (pReturnCode) *pReturnCode = 0;
        return &g_instance;
    }
    if (pReturnCode) *pReturnCode = 1;
    return NULL;
}

bool cure_unlock::Load(PluginId id, ISmmAPI *ismm, char *error, size_t maxlength, bool late)
{
    printf("[CURE-Unlock] ===== Loading =====\n");

    g_ismm = ismm;

    CreateInterfaceFn engineFactory = ismm->GetEngineFactory();
    if (!engineFactory)
    {
        printf("[CURE-Unlock] ERROR: engineFactory not found\n");
        if (error && maxlength) snprintf(error, maxlength, "engineFactory not found");
        return false;
    }

    g_engine = engineFactory(INTERFACEVERSION_VENGINESERVER, NULL);
    if (!g_engine)
    {
        printf("[CURE-Unlock] ERROR: IVEngineServer not found\n");
        if (error && maxlength) snprintf(error, maxlength, "IVEngineServer not found");
        return false;
    }

    printf("[CURE-Unlock] IVEngineServer: %p\n", g_engine);

    ismm->AddListener(this, this);
    printf("[CURE-Unlock] Registered as IMetamodListener\n");

    printf("[CURE-Unlock] Target maxclients: %d\n", g_target);
    printf("[CURE-Unlock] ===== Load complete =====\n");
    return true;
}

void cure_unlock::AllPluginsLoaded()
{
    printf("[CURE-Unlock] AllPluginsLoaded - applying patches\n");
    apply_all_patches();
}

void cure_unlock::OnLevelInit(char const *pMapName, char const *pMapEntities,
                              char const *pOldLevel, char const *pLandmarkName,
                              bool loadGame, bool background)
{
    printf("[CURE-Unlock] OnLevelInit: %s - re-applying patches\n", pMapName ? pMapName : "?");
    // 每次地图加载时重新应用 (保险)
    apply_all_patches();
}
