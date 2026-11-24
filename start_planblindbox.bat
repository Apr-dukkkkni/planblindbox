@echo off
setlocal EnableExtensions

REM ============================================================
REM PlanBlindBox one-click launcher
REM Place this file in the PlanBlindBox project root.
REM Default: Microsoft Edge
REM Optional: start_planblindbox.bat chrome
REM ============================================================

set "ROOT=%~dp0"
set "BROWSER=edge"

if /I "%~1"=="chrome" set "BROWSER=chrome"
if /I not "%~1"=="" if /I not "%~1"=="edge" if /I not "%~1"=="chrome" (
    echo Usage: %~nx0 [edge^|chrome]
    pause
    exit /b 2
)

echo.
echo ==========================================
echo       PlanBlindBox - Startup Check
echo ==========================================
echo Project root: %ROOT%
echo Browser: %BROWSER%
echo.

if not exist "%ROOT%frontend\pubspec.yaml" (
    echo [ERROR] Cannot find frontend\pubspec.yaml
    echo Put this script in the PlanBlindBox project root.
    pause
    exit /b 1
)

if not exist "%ROOT%mod-server\pom.xml" (
    echo [ERROR] Cannot find mod-server\pom.xml
    pause
    exit /b 1
)

if not exist "%ROOT%opaque-service\package.json" (
    echo [ERROR] Cannot find opaque-service\package.json
    pause
    exit /b 1
)

where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Flutter was not found in PATH.
    pause
    exit /b 1
)

where mvn >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Maven (mvn) was not found in PATH.
    pause
    exit /b 1
)

where npm >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Node.js/npm was not found in PATH.
    pause
    exit /b 1
)

echo [1/3] Starting MOD Server...
start "PlanBlindBox - MOD Server" cmd /k "cd /d ""%ROOT%mod-server"" && mvn spring-boot:run"

echo [2/3] Starting OPAQUE Service...
start "PlanBlindBox - OPAQUE Service" cmd /k "cd /d ""%ROOT%opaque-service"" && npm start"

echo [3/3] Starting Flutter frontend on %BROWSER%...
start "PlanBlindBox - Flutter Frontend" cmd /k "cd /d ""%ROOT%frontend"" && flutter run -d %BROWSER% --web-port=3000 --dart-define=API_BASE_URL=http://127.0.0.1:8080 --dart-define=USER_ID=1"

echo.
echo All three startup commands have been launched in separate terminals.
echo Keep those terminal windows open while using PlanBlindBox.
echo Close each terminal window or press Ctrl+C in it to stop its service.
echo.
pause
endlocal
