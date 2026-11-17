@echo off
setlocal
cd /d "%~dp0"
title LinkSwift + AB Download Manager setup

echo.
echo  ==================================================
echo    LinkSwift + AB Download Manager   one-click setup
echo  ==================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 goto failed

echo.
echo  Starting the browser guide ...
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0tools\guide-server.ps1" -OpenBrowser
timeout /t 2 >nul

echo.
echo  Guide page: http://127.0.0.1:18080/
echo  If your browser did not open, type the address above manually.
echo  Finish the two clicks there, then you are done.
echo.
echo  Press any key to close THIS window (the guide keeps running).
pause >nul
goto :eof

:failed
echo.
echo  [X] Setup did not finish. Read the red lines above.
echo      Most common fix: run once as a normal user, or open
echo      installer\ABDownloadManager_1.11.4_windows_x64.exe by hand.
echo.
pause
