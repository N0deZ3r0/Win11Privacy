@echo off
setlocal
cd /d "%~dp0"
title Win11Privacy - engine self-test (read only)

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo ================================================================
echo   Win11Privacy - proverka dvizhka. TOLKO CHTENIE.
echo   Nichego v sisteme ne menyaetsya.
echo ================================================================
echo.

set ENG=%~dp0Win11-Privacy-Engine.ps1
if not exist "%ENG%" (
  echo OSHIBKA: ne nayden Win11-Privacy-Engine.ps1 ryadom s etim faylom.
  pause
  exit /b 1
)

rem rezultaty - v otdelnoy papke ryadom, a ne prostynyoy v korne
set OUT=%~dp0check-results
if not exist "%OUT%" mkdir "%OUT%"

echo [1/7] Opredelenie sistemy...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -Detect      > "%OUT%\result-detect.json"   2>&1

echo [2/7] Proverka nastroek...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -Audit       > "%OUT%\result-audit.json"    2>&1

echo [3/7] Status rentgena telemetrii...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -XrayStatus  > "%OUT%\result-xray.json"     2>&1

echo [4/7] Dosye: dostup k kamere/mikrofonu/geolokacii...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -Spy         > "%OUT%\result-spy.json"      2>&1

echo [5/7] Dosye: cifrovoy sled na diske...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -Footprint   > "%OUT%\result-footprint.json" 2>&1

echo [6/7] Testovyy progon primeneniya (nichego ne menyaet)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -DryRun -NoBackup -NoRestorePoint -Modules telemetry,ads,copilot,ai,location,widgets,cleanup,startup > "%OUT%\result-dryrun.txt" 2>&1

echo [7/7] Avtozagruzka: chto startuet vmeste s Windows...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -ListStartup > "%OUT%\result-startup.json" 2>&1

echo.
echo Gotovo. V papke check-results sozdany 7 faylov s rezultatami:
echo   result-detect.json
echo   result-audit.json
echo   result-xray.json
echo   result-spy.json
echo   result-footprint.json
echo   result-startup.json
echo   result-dryrun.txt
echo.
echo Skazhite ob etom v chate - ya ih prochitayu.
echo.
pause
