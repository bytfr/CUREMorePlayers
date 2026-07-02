@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
title CURE 32P Patch Installer v2.0

REM ============================================================
REM Codename CURE 32P Client Patch Installer v2.0
REM - ASCII art (fixes Unicode encoding crash in old version)
REM - Auto-writes setinfo cure_patched 1 into config.cfg
REM   (autoexec.cfg is NOT executed by CURE, so we patch config.cfg)
REM ============================================================

set "PATCH_DLL=%~dp0client.dll"
set "BACKUP_NAME=client.dll.original"
set "GAME_SUBDIR=Steam\steamapps\common\Codename CURE\cure\bin"

echo +==========================================================+
echo ^|       Codename CURE 32P Client Patch Installer v2.0      ^|
echo +==========================================================+
echo ^|                                                          ^|
echo ^|  Patches client.dll + config.cfg for 32-player mode.     ^|
echo ^|  补丁客户端 + 配置文件, 突破5人限制                       ^|
echo ^|                                                          ^|
echo ^|  [1] Install patch   安装补丁 (recommended)              ^|
echo ^|  [2] Restore original 恢复原始文件                        ^|
echo ^|  [3] Detect game path  检测游戏路径                       ^|
echo ^|  [4] Exit             退出                                ^|
echo ^|                                                          ^|
echo +==========================================================+
echo.

if not exist "%PATCH_DLL%" (
    echo [ERROR] Patch file not found: %PATCH_DLL%
    echo [HINT] Make sure client.dll is in the same folder as this script.
    echo.
    pause
    exit /b 1
)

:menu
echo ============================================================
set /p "choice=Enter choice [1-4]: "

if "%choice%"=="1" goto install
if "%choice%"=="2" goto restore
if "%choice%"=="3" goto detect
if "%choice%"=="4" exit /b 0
echo [ERROR] Invalid choice.
goto menu

:detect
echo.
echo [*] Detecting game installation path...
set "GAME_PATH="

for /f "tokens=2*" %%a in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul') do (
    set "STEAM_PATH=%%b"
)

if defined STEAM_PATH (
    set "CHECK_PATH=!STEAM_PATH!\!GAME_SUBDIR!"
    if exist "!CHECK_PATH!\client.dll" (
        set "GAME_PATH=!CHECK_PATH!"
        echo [+] Found: !GAME_PATH!
        goto detected
    )
    for /f "tokens=2 delims=" %%i in ('findstr /i "path" "!STEAM_PATH!\steamapps\libraryfolders.vdf" 2^>nul') do (
        set "LIB_RAW=%%i"
        set "LIB_RAW=!LIB_RAW:"=!"
        set "LIB_RAW=!LIB_RAW:	=!"
        set "LIB_RAW=!LIB_RAW: =!"
        set "CHECK_PATH=!LIB_RAW!\Steam\steamapps\common\Codename CURE\cure\bin"
        if exist "!CHECK_PATH!\client.dll" (
            set "GAME_PATH=!CHECK_PATH!"
            echo [+] Found: !GAME_PATH!
            goto detected
        )
    )
)

for %%D in (
    "C:\Program Files (x86)\!GAME_SUBDIR!"
    "C:\Program Files\!GAME_SUBDIR!"
    "D:\Program Files (x86)\!GAME_SUBDIR!"
    "D:\Steam\!GAME_SUBDIR!"
    "E:\Steam\!GAME_SUBDIR!"
    "D:\Games\Steam\!GAME_SUBDIR!"
    "E:\Games\Steam\!GAME_SUBDIR!"
) do (
    set "CHECK_PATH=%%~D"
    if exist "!CHECK_PATH!\client.dll" (
        set "GAME_PATH=!CHECK_PATH!"
        echo [+] Found: !GAME_PATH!
        goto detected
    )
)

echo [!] Could not auto-detect game path.
echo.
set /p "GAME_PATH=Enter cure\bin folder path manually: "
if not exist "%GAME_PATH%\client.dll" (
    echo [ERROR] No client.dll found at that path.
    echo.
    goto menu
)

:detected
echo.
echo [+] Game path: %GAME_PATH%
for %%S in ("%GAME_PATH%\client.dll") do echo [+] client.dll size: %%S bytes
echo.
goto menu

:install
echo.
if not defined GAME_PATH (
    call :detect
    if not defined GAME_PATH goto menu
)

echo [*] Target: %GAME_PATH%
echo.

tasklist /fi "imagename eq cure.exe" 2>nul | find /i "cure.exe" >nul
if not errorlevel 1 (
    echo [ERROR] Game is running! Close CURE before patching.
    echo.
    pause
    goto menu
)

REM --- Backup original client.dll ---
set "BACKUP_PATH=%GAME_PATH%\%BACKUP_NAME%"
if not exist "%BACKUP_PATH%" (
    echo [*] Backing up original client.dll...
    copy "%GAME_PATH%\client.dll" "%BACKUP_PATH%" >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Backup failed! Check permissions.
        echo.
        pause
        goto menu
    )
    echo [+] Backup created: %BACKUP_NAME%
) else (
    echo [+] Backup already exists: %BACKUP_NAME%
)

REM --- Apply client.dll patch ---
echo [*] Applying client.dll patch...
copy /y "%PATCH_DLL%" "%GAME_PATH%\client.dll" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] client.dll patch failed!
    echo.
    pause
    goto menu
)
echo [+] client.dll patched.

REM --- Patch config.cfg with setinfo cure_patched 1 ---
REM config.cfg is at cure/cfg/config.cfg (parent of bin/ + cfg/)
set "CFG_DIR=%GAME_PATH%\..\cfg"
set "CFG_PATH=%CFG_DIR%\config.cfg"

echo [*] Patching config.cfg...

REM Check if cure_patched already exists in config.cfg
set "ALREADY_SET=0"
if exist "%CFG_PATH%" (
    findstr /i /c:"cure_patched" "%CFG_PATH%" >nul 2>&1
    if not errorlevel 1 (
        set "ALREADY_SET=1"
        echo [+] cure_patched already in config.cfg, skipping.
    )
)

if "!ALREADY_SET!"=="0" (
    REM Create cfg dir if missing
    if not exist "%CFG_DIR%" mkdir "%CFG_DIR%" 2>nul

    REM Append setinfo line (use >> to append, not overwrite)
    echo setinfo "cure_patched" "1">> "%CFG_PATH%"
    if errorlevel 1 (
        echo [WARNING] Could not write to config.cfg.
        echo [WARNING] You must manually type in game console:
        echo            setinfo cure_patched 1
    ) else (
        echo [+] config.cfg patched with: setinfo "cure_patched" "1"
    )
)

echo.
echo +==========================================================+
echo ^|                  PATCH INSTALLED!                        ^|
echo ^|                  补丁安装成功!                            ^|
echo +==========================================================+
echo ^|                                                          ^|
echo ^|  client.dll  - patched                                   ^|
echo ^|  config.cfg  - cure_patched = 1 (auto-set)               ^|
echo ^|  backup      - %BACKUP_NAME%              ^|
echo ^|                                                          ^|
echo ^|  You can now join 32-player servers.                     ^|
echo ^|  现在可以连接32人服务器了。                               ^|
echo ^|                                                          ^|
echo ^|  To restore: run this tool, select [2].                  ^|
echo ^|                                                          ^|
echo +==========================================================+
echo.
pause
goto menu

:restore
echo.
if not defined GAME_PATH (
    call :detect
    if not defined GAME_PATH goto menu
)

set "BACKUP_PATH=%GAME_PATH%\%BACKUP_NAME%"
if not exist "%BACKUP_PATH%" (
    echo [ERROR] Backup not found: %BACKUP_PATH%
    echo [HINT] Patch may not have been installed, or backup was deleted.
    echo.
    pause
    goto menu
)

echo [*] Restoring original client.dll...

tasklist /fi "imagename eq cure.exe" 2>nul | find /i "cure.exe" >nul
if not errorlevel 1 (
    echo [ERROR] Game is running! Close CURE first.
    echo.
    pause
    goto menu
)

copy /y "%BACKUP_PATH%" "%GAME_PATH%\client.dll" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Restore failed! Check permissions.
    echo.
    pause
    goto menu
)

echo [+] client.dll restored.

REM Remove cure_patched line from config.cfg
set "CFG_PATH=%GAME_PATH%\..\cfg\config.cfg"
if exist "%CFG_PATH%" (
    findstr /v /i /c:"cure_patched" "%CFG_PATH%" > "%CFG_PATH%.tmp" 2>nul
    if not errorlevel 1 (
        move /y "%CFG_PATH%.tmp" "%CFG_PATH%" >nul 2>&1
        echo [+] cure_patched removed from config.cfg.
    )
)

echo.
echo +==========================================================+
echo ^|                  ORIGINAL RESTORED                       ^|
echo ^|                  已恢复原始文件                           ^|
echo +==========================================================+
echo ^|                                                          ^|
echo ^|  client.dll restored to original.                        ^|
echo ^|  config.cfg cure_patched line removed.                   ^|
echo ^|                                                          ^|
echo ^|  You can now only connect to 5-player servers.           ^|
echo ^|                                                          ^|
echo +==========================================================+
echo.
pause
goto menu
