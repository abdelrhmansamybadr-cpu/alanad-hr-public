@echo off
echo ====================================
echo   HR Portal - Local Development
echo ====================================
echo.
echo Starting API Server on http://localhost:3001
echo Starting HR Portal  on http://localhost:5173
echo.
echo Press Ctrl+C in each window to stop.
echo.

start "HR Portal - API Server" cmd /k "cd /d %~dp0artifacts\api-server && pnpm dev"
timeout /t 3 /nobreak > nul
start "HR Portal - Frontend" cmd /k "cd /d %~dp0artifacts\hr-portal && pnpm dev"

echo Both services are starting...
echo Open http://localhost:5173 in your browser.
