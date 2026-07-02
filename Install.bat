@echo off
setlocal enabledelayedexpansion
title CURE 32P Patch Installer v2.2

set "PATCH_DLL=%~dp0client.dll"
set "BACKUP_NAME=client.dll.original"
set "GAME_SUBDIR=Steam\steamapps\common\Codename CURE\cure\bin"

echo +==========================================================+
echo ^|       Codename CURE 32P Client Patch Installer v2.2      ^|
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
    echo [错误] 找不到补丁文件: %PATCH_DLL%
    echo [HINT] Make sure client.dll is in the same folder as this script.
    echo [提示] 确保 client.dll 与本脚本在同一目录
    echo.
    pause
    exit /b 1
)

:menu
echo.
echo ============================================================
echo  Select option / 请选择操作:
echo    [1] Install patch   安装补丁 (recommended)
echo    [2] Restore original 恢复原始文件
echo    [3] Detect game path  检测游戏路径
echo    [4] Exit             退出
echo ============================================================
set /p "choice=Enter choice [1-4] / 请输入选项 [1-4]: "

if "%choice%"=="1" goto install
if "%choice%"=="2" goto restore
if "%choice%"=="3" goto detect
if "%choice%"=="4" exit /b 0
echo [ERROR] Invalid choice / 无效选项
goto menu

:detect
echo.
echo [*] Detecting game installation path...
echo [*] 正在检测游戏安装路径...
set "GAME_PATH="

for /f "tokens=2*" %%a in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul') do (
    set "STEAM_PATH=%%b"
)

if defined STEAM_PATH (
    set "CHECK_PATH=!STEAM_PATH!\!GAME_SUBDIR!"
    if exist "!CHECK_PATH!\client.dll" (
        set "GAME_PATH=!CHECK_PATH!"
        echo [+] Found / 找到: !GAME_PATH!
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
            echo [+] Found / 找到: !GAME_PATH!
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
        echo [+] Found / 找到: !GAME_PATH!
        goto detected
    )
)

echo [!] Could not auto-detect game path.
echo [!] 未能自动检测到游戏路径
echo.
set /p "GAME_PATH=Enter cure\bin folder path / 请输入 cure\bin 目录路径: "
if not exist "%GAME_PATH%\client.dll" (
    echo [ERROR] No client.dll found at that path / 该路径下没有 client.dll
    echo.
    goto menu
)

:detected
echo.
echo [+] Game path / 游戏路径: %GAME_PATH%
for %%S in ("%GAME_PATH%\client.dll") do echo [+] client.dll size / 大小: %%S bytes
echo.
goto menu

:install
echo.
if not defined GAME_PATH (
    call :detect
    if not defined GAME_PATH goto menu
)

echo [*] Target / 目标: %GAME_PATH%
echo.

tasklist /fi "imagename eq cure.exe" 2>nul | find /i "cure.exe" >nul
if not errorlevel 1 (
    echo [ERROR] Game is running! Close CURE before patching.
    echo [错误] 游戏正在运行! 请先关闭游戏
    echo.
    pause
    goto menu
)

set "BACKUP_PATH=%GAME_PATH%\%BACKUP_NAME%"
if not exist "%BACKUP_PATH%" (
    echo [*] Backing up original client.dll...
    echo [*] 备份原始文件...
    copy "%GAME_PATH%\client.dll" "%BACKUP_PATH%" >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Backup failed! Check permissions.
        echo [错误] 备份失败! 请检查权限
        echo.
        pause
        goto menu
    )
    echo [+] Backup created / 备份已创建: %BACKUP_NAME%
) else (
    echo [+] Backup already exists / 备份已存在: %BACKUP_NAME%
)

echo [*] Applying client.dll patch...
echo [*] 应用 client.dll 补丁...
copy /y "%PATCH_DLL%" "%GAME_PATH%\client.dll" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] client.dll patch failed!
    echo [错误] client.dll 补丁失败!
    echo.
    pause
    goto menu
)
echo [+] client.dll patched / 已补丁.

set "CFG_DIR=%GAME_PATH%\..\cfg"
set "CFG_PATH=%CFG_DIR%\config.cfg"

echo [*] Patching config.cfg...
echo [*] 修改 config.cfg...

set "ALREADY_SET=0"
if exist "%CFG_PATH%" (
    findstr /i /c:"cure_patched" "%CFG_PATH%" >nul 2>&1
    if not errorlevel 1 (
        set "ALREADY_SET=1"
        echo [+] cure_patched already in config.cfg, skipping.
        echo [+] cure_patched 已存在, 跳过
    )
)

if "!ALREADY_SET!"=="0" (
    if not exist "%CFG_DIR%" mkdir "%CFG_DIR%" 2>nul
    echo setinfo "cure_patched" "1">> "%CFG_PATH%"
    if errorlevel 1 (
        echo [WARNING] Could not write to config.cfg.
        echo [WARNING] 无法写入 config.cfg, 请手动在控制台输入:
        echo            setinfo cure_patched 1
    ) else (
        echo [+] config.cfg patched / 已添加: setinfo "cure_patched" "1"
    )
)

echo.
echo +==========================================================+
echo ^|                  PATCH INSTALLED!                        ^|
echo ^|                  补丁安装成功!                            ^|
echo +==========================================================+
echo ^|                                                          ^|
echo ^|  client.dll  - patched / 已补丁                          ^|
echo ^|  config.cfg  - cure_patched = 1 / 已自动设置             ^|
echo ^|  backup      - %BACKUP_NAME%              ^|
echo ^|                                                          ^|
echo ^|  You can now join 32-player servers.                     ^|
echo ^|  现在可以连接32人服务器了。                               ^|
echo ^|                                                          ^|
echo ^|  To restore: run this tool, select [2].                  ^|
echo ^|  如需恢复: 重新运行本工具选择 [2].                       ^|
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
    echo [错误] 找不到备份文件: %BACKUP_PATH%
    echo [HINT] Patch may not have been installed, or backup was deleted.
    echo [提示] 可能尚未安装过补丁, 或备份已被删除
    echo.
    pause
    goto menu
)

echo [*] Restoring original client.dll...
echo [*] 恢复原始 client.dll...

tasklist /fi "imagename eq cure.exe" 2>nul | find /i "cure.exe" >nul
if not errorlevel 1 (
    echo [ERROR] Game is running! Close CURE first.
    echo [错误] 游戏正在运行! 请先关闭游戏
    echo.
    pause
    goto menu
)

copy /y "%BACKUP_PATH%" "%GAME_PATH%\client.dll" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Restore failed! Check permissions.
    echo [错误] 恢复失败! 请检查权限
    echo.
    pause
    goto menu
)

echo [+] client.dll restored / 已恢复.

set "CFG_PATH=%GAME_PATH%\..\cfg\config.cfg"
if exist "%CFG_PATH%" (
    findstr /v /i /c:"cure_patched" "%CFG_PATH%" > "%CFG_PATH%.tmp" 2>nul
    if not errorlevel 1 (
        move /y "%CFG_PATH%.tmp" "%CFG_PATH%" >nul 2>&1
        echo [+] cure_patched removed from config.cfg.
        echo [+] 已从 config.cfg 移除 cure_patched
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
echo ^|  现在只能连接5人服务器                                    ^|
echo ^|                                                          ^|
echo +==========================================================+
echo.
pause
goto menu