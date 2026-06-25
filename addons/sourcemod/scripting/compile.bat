@echo off
chcp 65001 >nul 2>&1
setlocal

REM ===== Codename CURE More Players 编译脚本 =====

set "SPCOMP="
set "SCRIPT_DIR=%~dp0"

REM 1. 优先使用环境变量 SPCOMP_PATH
if defined SPCOMP_PATH (
    if exist "%SPCOMP_PATH%" (
        set "SPCOMP=%SPCOMP_PATH%"
        goto :found
    )
)

REM 2. 在常见位置查找 spcomp.exe
for %%P in (
    "%SCRIPT_DIR%spcomp.exe"
    "%SCRIPT_DIR%..\..\..\..\sourcemod\scripting\spcomp.exe"
    "C:\Program Files (x86)\Steam\steamapps\sourcemod\scripting\spcomp.exe"
    "C:\Program Files\Steam\steamapps\sourcemod\scripting\spcomp.exe"
) do (
    if exist "%%~P" (
        set "SPCOMP=%%~P"
        goto :found
    )
)

REM 3. 交互式输入
echo [CURE-MorePlayers] 未自动找到 spcomp.exe 编译器
echo [CURE-MorePlayers] 请输入 spcomp.exe 的完整路径 (可直接拖入文件):
set /p "SPCOMP=> "

if "%SPCOMP%"=="" (
    echo [错误] 未输入路径
    pause
    exit /b 1
)

if not exist "%SPCOMP%" (
    echo [错误] 文件不存在: %SPCOMP%
    pause
    exit /b 1
)

:found
echo [CURE-MorePlayers] 编译器: %SPCOMP%
echo [CURE-MorePlayers] 正在编译...

REM 获取 spcomp 所在目录 (include 通常在同级的 include\ 子目录)
for %%F in ("%SPCOMP%") do set "SPCOMP_DIR=%%~dpF"

REM 编译: -i 指定 include 路径, -o 指定输出路径
"%SPCOMP%" -i"%SPCOMP_DIR%include" -o"%SCRIPT_DIR%..\plugins\cure_moreplayers.smx" "%SCRIPT_DIR%cure_moreplayers.sp"

if %ERRORLEVEL% equ 0 (
    echo.
    echo [CURE-MorePlayers] 编译成功!
    echo [CURE-MorePlayers] 输出文件: %SCRIPT_DIR%..\plugins\cure_moreplayers.smx
    echo.
    echo [CURE-MorePlayers] 安装方法:
    echo   将 cure_moreplayers.smx 复制到服务器目录:
    echo   addons\sourcemod\plugins\
) else (
    echo.
    echo [CURE-MorePlayers] 编译失败! 错误代码: %ERRORLEVEL%
    echo [CURE-MorePlayers] 请确保 include 文件路径正确
)

echo.
pause
