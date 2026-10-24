@echo off
setlocal EnableDelayedExpansion
title HR Mobile App Launcher
color 0A

echo.
echo  ==========================================
echo   HR Portal Mobile App - Auto Launcher
echo  ==========================================
echo.

:: ── Paths ────────────────────────────────────────────────────────────────────
set "ROOT=%~dp0"
:: Remove trailing backslash
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "MOBILE_APP=%ROOT%\mobile_app"
set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
set "EMULATOR_EXE=%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe"
set "AVD_NAME=Medium_Phone_API_36.0"

:: ── Step 1: Start Android Emulator ──────────────────────────────────────────
echo [1/4] Checking Android Emulator...
"%ADB%" devices 2>nul | find "emulator" >nul 2>&1
if %ERRORLEVEL% == 0 (
    echo       Emulator already running. Skipping.
) else (
    echo       Starting emulator ^(%AVD_NAME%^)...
    start "Emulator" /min "%EMULATOR_EXE%" -avd %AVD_NAME% -no-snapshot-load
    echo       Waiting for emulator to boot ^(30-60 seconds^)...
    timeout /t 8 /nobreak >nul

    :: Wait until adb detects the device
    :wait_device
    "%ADB%" devices 2>nul | find "emulator" >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        timeout /t 3 /nobreak >nul
        goto wait_device
    )

    :: Wait until boot is complete
    :wait_boot
    for /f "tokens=*" %%i in ('"%ADB%" shell getprop sys.boot_completed 2^>nul') do set BOOT=%%i
    if not "!BOOT!"=="1" (
        timeout /t 3 /nobreak >nul
        goto wait_boot
    )
    echo       Emulator fully booted!
)
echo.

:: ── Step 2: Start API Server ─────────────────────────────────────────────────
echo [2/4] Starting API Server on http://localhost:3001 ...
start "HR API Server" cmd /k "title HR API Server && color 0B && cd /d "%ROOT%" && echo. && echo   HR Portal - API Server && echo   URL: http://localhost:3001 && echo   Press Ctrl+C to stop. && echo. && pnpm --filter @workspace/api-server dev"
echo       API server starting in a new window...
echo.

:: ── Step 3: Wait for API to be ready ─────────────────────────────────────────
echo [3/4] Waiting for API to be ready...
timeout /t 6 /nobreak >nul
:wait_api
curl -s -o nul -w "%%{http_code}" http://localhost:3001/api/healthz 2>nul | find "200" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    timeout /t 2 /nobreak >nul
    goto wait_api
)
echo       API is ready!
echo.

:: ── Step 4: Run Flutter App ──────────────────────────────────────────────────
echo [4/4] Launching Flutter app on emulator...
start "HR Flutter App" cmd /k "title HR Flutter App && color 0D && cd /d "%MOBILE_APP%" && echo. && echo   HR Portal - Flutter Mobile App && echo   Launching on Android Emulator... && echo   Press R = hot reload  ^|  Shift+R = restart  ^|  Q = quit && echo. && flutter run"
echo       Flutter app launching in a new window...
echo.

echo  ==========================================
echo   All services started successfully!
echo  ==========================================
echo.
echo   API Server : http://localhost:3001
echo   Mobile App : Running on Android Emulator
echo.
echo   Windows opened:
echo     - HR API Server  (yellow)
echo     - HR Flutter App (purple)
echo.
echo  You can close this window. Press any key to close.
echo.
pause >nul
