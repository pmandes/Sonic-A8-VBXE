@echo off
rem Sonic A8 VBXE - build script
rem
rem   tools\build.cmd [xex|cart|atr|release]        (default: release)
rem
rem   xex      build\sonic-a8-vbxe.xex                  XEX for SIO devices (1088K + VBXE)
rem   cart     build\sonic-atarimax.car, sonic-atarimax75.car, sonic-atarimax.bin, sonic-sic512.car
rem   atr      build\sonic-a8-vbxe.atr (MyDOS DD), sonic-ed1.atr .. sonic-ed3.atr (DOS 2.5 ED, stock 1050)
rem   release  all of the above, copied to dist\ and packed into dist\sonic-a8-vbxe-v%VERSION%.zip
rem
rem Requirements: Python 3 with the packages from requirements.txt (python on PATH, or set PYTHON=<path to python.exe>)
rem and your own Sega Master System ROM of Sonic The Hedgehog in assets\rom\sms\ (see README.md).
rem MADS, zx02, dir2atr and xBIOS are included in tools\bin.
setlocal
set VERSION=1.0
set ROOT=%~dp0..
set MADS=%ROOT%\tools\bin\mads.exe
set PY=python
if not "%PYTHON%"=="" set PY=%PYTHON%
set INC=-i:"%ROOT%\src\asm" -i:"%ROOT%\build\assets\ghz1" -i:"%ROOT%\build\assets" -i:"%ROOT%\build\assets\music" -i:"%ROOT%\build\assets\ekrany" -i:"%ROOT%\src\data"

set TARGET=%1
if "%TARGET%"=="" set TARGET=release
if /i not "%TARGET%"=="xex" if /i not "%TARGET%"=="cart" if /i not "%TARGET%"=="atr" if /i not "%TARGET%"=="release" (
  echo Unknown target: %TARGET%  ^(use: xex, cart, atr, release^)
  exit /b 2
)
if not exist "%MADS%" (
  echo ERROR: MADS not found: %MADS%
  exit /b 1
)
"%PY%" "%ROOT%\tools\check_rom.py"
if errorlevel 1 exit /b 1
if not exist "%ROOT%\build" mkdir "%ROOT%\build"

call :assets
if errorlevel 1 exit /b 1
if /i "%TARGET%"=="release" goto release
call :%TARGET%
if errorlevel 1 exit /b 1
exit /b 0

:release
call :xex
if errorlevel 1 exit /b 1
call :cart
if errorlevel 1 exit /b 1
call :atr
if errorlevel 1 exit /b 1
call :dist
if errorlevel 1 exit /b 1
exit /b 0

:assets
rem Game data extracted from the SMS ROM into build\assets: levels and acts, special stages, screens, music and sound effects
for %%L in (ghz1 ghz2 ghz3 bri1 bri2 bri3 jun1 jun2 jun3 lab1 lab2 lab3 sbz1 sbz2 sbz3 sbz2a sbz2b sky1 sky2 sky3 sp1 sp2 sp3 sp5 sp6 sp7 sp4 sp8) do (
  "%PY%" "%ROOT%\tools\extract_sms.py" --level %%L
  if errorlevel 1 exit /b 1
)
"%PY%" "%ROOT%\tools\pack_special.py"
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\extract_ekrany.py"
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\extract_koniec.py"
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\m3_trace.py" --inc "%ROOT%\build\assets\m3_trace.inc"
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\pack_music.py"
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\pack_sfx.py"
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\manifest.py"
if errorlevel 1 exit /b 1
exit /b 0

:xex
"%MADS%" "%ROOT%\src\asm\game.asm" -d:RELEASE=1 -o:"%ROOT%\build\sonic-a8-vbxe.xex" -l:"%ROOT%\build\sonic-a8-vbxe.lst" -t:"%ROOT%\build\sonic-a8-vbxe.lab" %INC%
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\sprawdz_xex.py" "%ROOT%\build\sonic-a8-vbxe.xex"
if errorlevel 1 exit /b 1
echo OK: build\sonic-a8-vbxe.xex
exit /b 0

:cart
call :cart1 am 0
if errorlevel 1 exit /b 1
call :cart1 sic 1
if errorlevel 1 exit /b 1
exit /b 0

:cart1
rem %1 = am / sic (file names), %2 = CART_TYPE (0 = AtariMax 1 MB, 1 = SIC! 512 KB)
"%MADS%" "%ROOT%\src\asm\game.asm" -d:RELEASE=1 -d:MEDIA=1 -d:CART_TYPE=%2 -o:"%ROOT%\build\sonic-cart-%1.xex" -l:"%ROOT%\build\sonic-cart-%1.lst" -t:"%ROOT%\build\sonic-cart-%1.lab" %INC%
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\sprawdz_xex.py" "%ROOT%\build\sonic-cart-%1.xex"
if errorlevel 1 exit /b 1
"%MADS%" "%ROOT%\src\asm\boot\cartboot.asm" -d:RELEASE=1 -d:MEDIA=1 -d:CART_TYPE=%2 -o:"%ROOT%\build\cartboot-%1.xex" -l:"%ROOT%\build\cartboot-%1.lst" -t:"%ROOT%\build\cartboot-%1.lab" -i:"%ROOT%\src\asm"
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\pack_cart.py" --typ %1
if errorlevel 1 exit /b 1
echo OK: cart %1
exit /b 0

:atr
"%MADS%" "%ROOT%\src\asm\game.asm" -d:RELEASE=1 -d:MEDIA=3 -o:"%ROOT%\build\sonic-atr.xex" -l:"%ROOT%\build\sonic-atr.lst" -t:"%ROOT%\build\sonic-atr.lab" %INC%
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\sprawdz_xex.py" "%ROOT%\build\sonic-atr.xex"
if errorlevel 1 exit /b 1
"%PY%" "%ROOT%\tools\pack_atr.py"
if errorlevel 1 exit /b 1
echo OK: atr
exit /b 0

:dist
set PKG=sonic-a8-vbxe-v%VERSION%
set STAGE=%ROOT%\build\release\%PKG%
if exist "%ROOT%\build\release" rmdir /s /q "%ROOT%\build\release"
mkdir "%STAGE%"
if not exist "%ROOT%\dist" mkdir "%ROOT%\dist"
for %%F in (sonic-a8-vbxe.xex sonic-atarimax.car sonic-atarimax75.car sonic-atarimax.bin sonic-sic512.car sonic-a8-vbxe.atr sonic-ed1.atr sonic-ed2.atr sonic-ed3.atr) do (
  copy /y "%ROOT%\build\%%F" "%ROOT%\dist\%%F" >nul
  if errorlevel 1 exit /b 1
  copy /y "%ROOT%\build\%%F" "%STAGE%\%%F" >nul
  if errorlevel 1 exit /b 1
)
copy /y "%ROOT%\dist\README.TXT" "%STAGE%\README.TXT" >nul
if errorlevel 1 exit /b 1
if exist "%ROOT%\dist\%PKG%.zip" del "%ROOT%\dist\%PKG%.zip"
powershell -NoProfile -Command "Compress-Archive -Path '%STAGE%' -DestinationPath '%ROOT%\dist\%PKG%.zip'"
if errorlevel 1 exit /b 1
echo OK: dist\%PKG%.zip
exit /b 0
