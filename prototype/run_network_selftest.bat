@echo off
cd /d "%~dp0"
echo ============================================================
echo PC WHY? - NETWORK SELF-TEST LAUNCHER
echo ============================================================
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0network_logic_selftest.ps1"
echo.
echo PowerShell process ended. Exit code: %ERRORLEVEL%
echo.
pause
cmd /k
