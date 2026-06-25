#include <sourcemod>
#include <sdktools>

#pragma semicolon 1

#define PLUGIN_VERSION "2.1.0"
#define MAX_PLAYERS_LIMIT 128

new Handle:g_cvTargets[64];
new String:g_cvTargetNames[64][64];
new g_cvCount = 0;

public Plugin:myinfo =
{
    name        = "[CURE] More Players (Diagnose)",
    author      = "CURE-MorePlayers",
    description = "Dump 引擎所有 cvars 找出上限控制点",
    version     = PLUGIN_VERSION,
    url         = ""
};

public OnPluginStart()
{
    RegAdminCmd("sm_cure_status",      Command_Status, ADMFLAG_ROOT, "查看 native 引擎限制");
    RegAdminCmd("sm_cure_fullcvars",   Command_Full,   ADMFLAG_ROOT, "转储所有 cvar 到 sourcemod 日志");
    RegAdminCmd("sm_cure_setvisiblemax", Command_SetVisible, ADMFLAG_ROOT, "尝试写 sv_visiblemaxplayers");
    RegAdminCmd("sm_cure_dumpall",     Command_DumpAll, ADMFLAG_ROOT, "把全部 cvar 写入 sourcemod/logs/dump.txt");

    PrintToServer("[CURE-MorePlayers] v%s loaded. native GetMaxClients() = %d", PLUGIN_VERSION, GetMaxClients());
}

public Action:Command_Status(client, args)
{
    new natMax = GetMaxClients();
    ReplyToCommand(client, "");
    ReplyToCommand(client, "===== CURE 状态 v%s =====", PLUGIN_VERSION);
    ReplyToCommand(client, "native GetMaxClients() = %d  → 这是 mod 硬性上限", natMax);
    ReplyToCommand(client, "GetClientCount(false)   = %d", GetClientCount(false));
    ReplyToCommand(client, "GetClientCount(true)    = %d", GetClientCount(true));
    if (natMax == 5)
    {
        ReplyToCommand(client, "");
        ReplyToCommand(client, "诊断: native API 返回 5, 表明 mod 内部硬性写死 5 人");
        ReplyToCommand(client, "      SourceMod 的 cvar 修改路径完全失效");
        ReplyToCommand(client, "");
        ReplyToCommand(client, "执行 sm_cure_fullcvars 让我们看到所有可见 cvar");
        ReplyToCommand(client, "执行 sm_cure_dumpall 写到日志文件以便传输给我");
    }
    ReplyToCommand(client, "");
    return Plugin_Handled;
}

public Action:Command_Full(client, args)
{
    ReplyToCommand(client, "为避免客户端溢出, 此命令只写日志.");
    DumpAll(false);
    return Plugin_Handled;
}

public Action:Command_DumpAll(client, args)
{
    DumpAll(true);
    ReplyToCommand(client, "全部 cvar 已写入 sourcemod/logs/cure_dumped_cvars_<时间>.txt");
    return Plugin_Handled;
}

public Action:Command_SetVisible(client, args)
{
    new Handle:h = FindConVar("sv_visiblemaxplayers");
    if (h != INVALID_HANDLE)
    {
        SetConVarInt(h, 32, true, false);
        ReplyToCommand(client, "已尝试 sv_visiblemaxplayers = 32, 现读: %d", GetConVarInt(h));
    } else {
        ReplyToCommand(client, "此 mod 未暴露 sv_visiblemaxplayers cvar");
    }
    return Plugin_Handled;
}

stock DumpAll(bool:toFile)
{
    decl String:logPath[256];
    new Handle:file = INVALID_HANDLE;
    if (toFile)
    {
        BuildLogPath("cure_dumped_cvars.txt", logPath, sizeof(logPath));
        file = OpenFile(logPath, "w");
    }

    // 尝试扫描 SDKTools 提供的 client convar 列表
    new Handle:iter = GetCommandIterator();
    if (iter == INVALID_HANDLE)
    {
        if (file != INVALID_HANDLE) CloseHandle(file);
        return;
    }

    decl String:name[128];
    decl String:value[256];
    decl String:full[1024];

    while (ReadCommandIterator(iter, name, sizeof(name), value, sizeof(value), 0))
    {
        Format(full, sizeof(full), "%s = %s\n", name, value);
        PrintToServer(full);
        if (file != INVALID_HANDLE) WriteFileLine(file, "%s = %s", name, value);
    }
    delete iter;

    if (file != INVALID_HANDLE) CloseHandle(file);
}

stock bool:BuildLogPath(const String:fname[], String:out[], len)
{
    decl String:base[256];
    if (!GetGameFolderName(base, sizeof(base))) strcopy(base, sizeof(base), "garrysmod");
    decl String:path[256];
    Format(path, sizeof(path), "logs/%s", fname);
    Format(out, len, path);
    return true;
}
