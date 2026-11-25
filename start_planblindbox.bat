@echo off
setlocal EnableExtensions

REM ============================================================
REM PlanBlindBox one-click launcher
REM Put this file in the PlanBlindBox project root.
REM Default browser: Edge
REM Usage:
REM   start_planblindbox.bat
REM   start_planblindbox.bat edge
REM   start_planblindbox.bat chrome
REM ============================================================

set "ROOT=%~dp0"
set "BROWSER=edge"

REM Select browser without parenthesized IF blocks.
if "%~1"=="" goto browser_ok
if /I "%~1"=="edge" goto browser_ok
if /I "%~1"=="chrome" set "BROWSER=chrome"
if /I "%~1"=="chrome" goto browser_ok

echo Usage: %~nx0 [edge^|chrome]
exit /b 2

:browser_ok
echo.
echo ==========================================
echo       PlanBlindBox - Startup Check
echo ==========================================
echo Project root: %ROOT%
echo Browser: %BROWSER%
echo.

REM Verify project files.
if not exist "%ROOT%frontend\pubspec.yaml" goto missing_frontend
if not exist "%ROOT%mod-server\pom.xml" goto missing_mod_server
if not exist "%ROOT%opaque-service\package.json" goto missing_opaque

REM Verify command-line tools.
where flutter >nul 2>nul
if errorlevel 1 goto missing_flutter

where mvn >nul 2>nul
if errorlevel 1 goto missing_maven

where npm >nul 2>nul
if errorlevel 1 goto missing_npm

echo [1/3] Starting MOD Server...
start "PlanBlindBox - MOD Server" /D "%ROOT%mod-server" cmd.exe /k "mvn spring-boot:run"

echo [2/3] Starting OPAQUE Service...
start "PlanBlindBox - OPAQUE Service" /D "%ROOT%opaque-service" cmd.exe /k "npm start"

echo [3/3] Starting Flutter frontend on %BROWSER%...
start "PlanBlindBox - Flutter Frontend" /D "%ROOT%frontend" cmd.exe /k "flutter run -d %BROWSER% --web-port=3000 --dart-define=API_BASE_URL=http://127.0.0.1:8080 --dart-define=USER_ID=1"

echo.
echo Startup commands launched in three separate terminals.
echo Keep all three terminal windows open while using PlanBlindBox.
echo To stop a service, press Ctrl+C in its terminal.
echo.
pause
exit /b 0

:missing_frontend
echo [ERROR] Cannot find frontend\pubspec.yaml
echo Make sure this BAT file is in the PlanBlindBox project root.
pause
exit /b 1

:missing_mod_server
echo [ERROR] Cannot find mod-server\pom.xml
pause
exit /b 1

:missing_opaque
echo [ERROR] Cannot find opaque-service\package.json
pause
exit /b 1

:missing_flutter
echo [ERROR] Flutter was not found in PATH.
pause
exit /b 1

:missing_maven
echo [ERROR] Maven (mvn) was not found in PATH.
pause
exit /b 1

:missing_npm
echo [ERROR] Node.js/npm was not found in PATH.
pause
exit /b 1