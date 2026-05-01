@echo off
REM ============================================================
REM build-windows.bat
REM ------------------------------------------------------------
REM One-shot Windows build pointed at the ngrok test tunnel.
REM Prefer build-windows.ps1 when PowerShell is allowed; this
REM .bat is a fallback for locked-down machines.
REM ============================================================

setlocal

set BASE_URL=https://uninterrupted-brent-lunulate.ngrok-free.dev/tinkerpro_support
set SOKETI_HOST=uninterrupted-brent-lunulate.ngrok-free.dev

cd /d "%~dp0"

echo.
echo ==^> flutter pub get
flutter pub get
if errorlevel 1 goto :fail

echo.
echo ==^> flutter build windows --release
flutter build windows --release ^
    --dart-define=TPS_BASE_URL=%BASE_URL% ^
    --dart-define=CHAT_SOKETI_HOST=%SOKETI_HOST% ^
    --dart-define=CHAT_SOKETI_PORT=443 ^
    --dart-define=CHAT_SOKETI_TLS=true ^
    --dart-define=CHAT_SOKETI_KEY=tinkerpro-chat-key
if errorlevel 1 goto :fail

echo.
echo ==^> Build complete
echo     exe:    %CD%\build\windows\x64\runner\Release\employee_app.exe
echo     bundle: %CD%\build\windows\x64\runner\Release\
echo.
echo Ship the WHOLE Release folder, not just the exe.
echo.
goto :eof

:fail
echo.
echo BUILD FAILED. Common causes:
echo   - Visual Studio 2022 missing 'Desktop development with C++' workload.
echo   - Flutter not on PATH (run flutter doctor).
echo   - Stale build cache (run: flutter clean ^&^& %~nx0).
exit /b 1
