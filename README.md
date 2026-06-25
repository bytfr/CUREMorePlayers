# Codename CURE — Player Limit Investigation & Fix Proposal

## Summary

The 5-player limit in Codename CURE is enforced by **two separate hard-coded checks**, one on the server and one on the client. Neither is exposed via a ConVar, so server operators cannot raise it through configuration. This document identifies both check sites and proposes minimal changes to make the limit configurable.

---

## Background

We are running a dedicated server (`srcds_linux`) for Codename CURE and need to support more than 5 players. We attempted the following without success:

| Approach | Result |
|---|---|
| `-maxplayers 32` launch parameter | Engine reports `maxplayers set to 5` — overridden by the mod |
| `sv_visiblemaxplayers` ConVar | Not registered by the mod |
| SourceMod plugin modifying ConVars at runtime | `GetMaxClients()` native still returns 5 |
| `cvarlist *max*` | Returns zero results — no max-related ConVars exist |

`GetMaxClients()` (the SourceMod native, which reads the engine's internal state) confirms the limit is enforced inside the mod binaries, not the engine.

---

## Investigation Method

We analysed the Linux server binary `cure/bin/server_srv.so` and the Windows client binary `cure/bin/client.dll` using `objdump`, `nm`, `strings`, and Capstone disassembly.

### Server binary (`server_srv.so`, Linux, 32-bit)

The function `CServerGameClients::GetPlayerLimits` is the source of the server-side limit. It writes the constant `5` into all three output parameters (`min`, `max`, `default`).

**File offset:** `0x008e6ae0`
**Disassembly:**

```asm
push    ebp
mov     ebp, esp
mov     eax, [ebp + 0x14]    ; arg: *defaultPlayers
mov     dword [eax], 5        ; <-- hard-coded 5 (default)
mov     eax, [ebp + 0x0C]    ; arg: *minPlayers
mov     dword [eax], 5        ; <-- hard-coded 5 (min)
mov     eax, [ebp + 0x10]    ; arg: *maxPlayers
mov     dword [eax], 5        ; <-- hard-coded 5 (max)
pop     ebp
ret
```

The three `mov dword [eax], 5` instructions (`C7 00 05 00 00 00`) are at file offsets `0x008e6ae8`, `0x008e6af1`, `0x008e6afa`.

The engine calls `GetPlayerLimits()` during `CGameServer::SetupMaxPlayers()`, which then:
1. Reads the `max` value returned here.
2. Allocates edict pool, network string tables, and client buffers accordingly.
3. Prints `maxplayers set to <N>`.

Because this returns 5, the engine only ever allocates 5-player-sized buffers, and `sv.m_nMaxclients` is clamped to 5.

### Client binary (`client.dll`, Windows, 32-bit)

Even after patching the server to return 32, clients crash on connect with:

```
Engine Error
UpdatePlayerName with bogus slot 7
```

This error is raised by **two hard-coded assertions** in `client.dll`. Both compare the player slot index against 5 and trigger an `assert`-style fatal error if the slot exceeds 5.

**Check site 1 — player name table iteration**
- Function start: `VA = 0x100cc170`
- Check: `VA = 0x100cc1b3`
- Disassembly:

```asm
lea     eax, [edi - 1]        ; edi = 1-based slot index
cmp     eax, 5                ; <-- hard-coded 5
ja      assert_fail_1         ; branch to "UpdatePlayerName with bogus slot %d"
```

- Bytes at `0x100cc1b3`: `83 F8 05` (`cmp eax, 5`)

**Check site 2 — single player name update**
- Function start: `VA = 0x100cc780`
- Check: `VA = 0x100cc79d`
- Disassembly:

```asm
lea     eax, [edi - 1]        ; edi = 1-based slot index
cmp     eax, 5                ; <-- hard-coded 5
ja      assert_fail_2         ; branch to "UpdatePlayerName with bogus slot %d"
```

- Bytes at `0x100cc79d`: `83 F8 05` (`cmp eax, 5`)

The error string `UpdatePlayerName with bogus slot %d\n` is located at `VA = 0x103c786c` and is referenced from both sites above.

---

## Why a Server-Only Fix Is Not Enough

We confirmed this by binary-patching `server_srv.so` so that `GetPlayerLimits` writes 32 instead of 5. The server then boots correctly, `GetMaxClients()` returns 32, and `maxplayers set to 32` is printed. However, the moment a client connects, the client crashes with `UpdatePlayerName with bogus slot 7` because the server sends player-name updates for slots beyond 5, and the client's assertions reject them.

Therefore **both binaries must be changed** for a working >5-player server.

---

## Proposed Fix

The cleanest fix is to make the limit a ConVar on the server, and to remove (or raise) the hard-coded assertions on the client. Below are concrete suggestions.

### 1. Server: make the limit configurable

In `CServerGameClients::GetPlayerLimits`, instead of writing the literal `5`, read a ConVar (e.g. `cure_maxplayers`) and return its value for `min`, `max`, and `default`.

**Suggested source change (server side):**

```cpp
// In your server game clients class implementation:
static ConVar cure_maxplayers("cure_maxplayers", "5", FCVAR_REPLICATED,
    "Maximum number of players. CURE default is 5.", true, 1, true, 32);

void CServerGameClients::GetPlayerLimits(int& minplayers, int& maxplayers, int& defaultplayers) const
{
    int n = cure_maxplayers.GetInt();
    minplayers     = n;
    maxplayers     = n;
    defaultplayers = n;
}
```

This lets server operators set `cure_maxplayers 32` in `server.cfg` or via the launch line, and the engine will allocate buffers for that many players.

If exposing a ConVar is not desirable, even just changing the literal `5` to `MAX_PLAYERS` and defining `MAX_PLAYERS` from a compile-time option would help.

### 2. Client: remove the slot assertions

The two `cmp eax, 5` checks in `client.dll` (at `VA = 0x100cc1b3` and `VA = 0x100cc79d`) should either:

- **(Preferred)** Be removed entirely — let the client trust the server's player count. The engine's own `MAX_CLIENTS` / `ABSOLUTE_PLAYER_LIMIT` constants already bound the slot index safely.
- **(Alternative)** Be raised to a higher constant (e.g. `ABSOLUTE_PLAYER_LIMIT`, which is 128 in Source SDK 2013), so the client no longer assumes 5.

**Suggested source change (client side):**

Replace the hard-coded `5` with the SDK constant that already governs array bounds:

```cpp
// Before
if (slot - 1 >= 5) { /* bogus slot error */ }

// After
if (slot - 1 >= ABSOLUTE_PLAYER_LIMIT) { /* bogus slot error */ }
```

or simply remove the assertion if the surrounding code already bounds-checks against the engine's max clients.

---

## Verification Steps

After applying both changes:

1. Start a dedicated server with `cure_maxplayers 32` (or the new constant).
2. Server console should print `maxplayers set to 32`.
3. `GetMaxClients()` SourceMod native returns 32.
4. 6+ clients connect without crashing.
5. Player names for slots 5–31 appear correctly in the scoreboard.

---

## Files Referenced

| Binary | Platform | Path | Key offset / VA |
|---|---|---|---|
| `server_srv.so` | Linux 32-bit | `cure/bin/server_srv.so` | `GetPlayerLimits` @ file offset `0x008e6ae0` |
| `client.dll` | Windows 32-bit | `cure/bin/client.dll` | Check 1 @ `VA 0x100cc1b3`, Check 2 @ `VA 0x100cc79d` |

If the developer can recompile from source, no binary patching is needed — the source changes above are minimal (a few lines each side) and would officially enable larger co-op sessions.

---

## Contact

If any of the offset values differ across versions, we can re-derive them. We have the tooling ready to analyse whichever build the developer points us at.
