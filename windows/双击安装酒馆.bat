@echo off
rem Easy SillyTavern: double-click this file to install SillyTavern.
rem If Windows says "Windows protected your PC": click "More info", then "Run anyway".
rem Keep this file ASCII-only above the chcp line; cmd reads it in the system code page.
setlocal
if not exist "%~dp0easy-st.ps1" goto missing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0easy-st.ps1" install
exit /b %errorlevel%

:missing
chcp 65001 >nul
echo.
echo   找不到 easy-st.ps1。请先把下载的压缩包整个解压出来，再双击「双击安装酒馆」。
echo   easy-st.ps1 is missing. Extract the whole ZIP first, then run this file again.
echo.
pause
exit /b 1