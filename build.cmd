@echo off
setlocal
cd /d "%~dp0"
title Win11Privacy - sborka

rem Kompilyator .NET Framework uzhe est v lyuboy Windows - stavit nichego ne nuzhno
set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
if not exist "%CSC%" (
  echo OSHIBKA: ne nayden csc.exe ^(.NET Framework 4^).
  pause
  exit /b 1
)

echo Sborka Win11Privacy.exe ...
"%CSC%" /nologo /target:winexe /optimize+ /out:Win11Privacy.exe ^
  /reference:System.dll ^
  /reference:System.Core.dll ^
  /reference:System.Drawing.dll ^
  /reference:System.Windows.Forms.dll ^
  /win32res:app.res ^
  /resource:Win11-Privacy-Engine.ps1,engine.ps1 ^
  /resource:app.ico,app.ico ^
  /resource:app.png,app.png ^
  MainForm.cs Ui.cs Ui2.cs Ui3.cs Ui4.cs Json.cs

if errorlevel 1 (
  echo.
  echo SBORKA NE UDALAS - smotrite oshibki vyshe.
  pause
  exit /b 1
)

echo.
echo Gotovo: Win11Privacy.exe
echo.
pause
