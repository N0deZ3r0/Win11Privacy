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

echo [1/6] Opredelenie sistemy...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -Detect      > "%~dp0result-detect.json"   2>&1

echo [2/6] Proverka nastroek...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -Audit       > "%~dp0result-audit.json"    2>&1

echo [3/6] Status rentgena telemetrii...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -XrayStatus  > "%~dp0result-xray.json"     2>&1

echo [4/6] Dosye: dostup k kamere/mikrofonu/geolokacii...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -Spy         > "%~dp0result-spy.json"      2>&1

echo [5/6] Dosye: cifrovoy sled na diske...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -Footprint   > "%~dp0result-footprint.json" 2>&1

echo [6/6] Testovyy progon primeneniya (nichego ne menyaet)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ENG%" -DryRun -NoBackup -NoRestorePoint -Modules telemetry,ads,copilot,ai,location,widgets,cleanup,startup > "%~dp0result-dryrun.txt" 2>&1

echo.
echo Gotovo. Ryadom sozdany 6 faylov s rezultatami:
echo   result-detect.json
echo   result-audit.json
echo   result-xray.json
echo   result-spy.json
echo   result-footprint.json
echo   result-dryrun.txt
echo.
echo Skazhite ob etom v chate - ya ih prochitayu.
echo.
pause
