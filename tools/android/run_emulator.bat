@echo off
rem Starts the virtual phone (if it is not running), installs the newest debug APK and opens the game.
rem Double-click it. Add "build" to export a fresh APK first:  run_emulator.bat build
rem Paths: edit the lines below if they change.
set GODOT=C:\Users\MyPC\Desktop\Godot_v4.5.1-stable_win64_console.exe
set SDK=G:\AndroidSDK
set AVD=KingdomTiles_Phone
set APK=build\KingdomTiles_debug.apk

cd /d "%~dp0\..\.."
if not exist build mkdir build
if /i "%1"=="build" (
  echo Exporting %APK% ...
  "%GODOT%" --headless --path . --export-debug "Android" "%CD%\%APK%"
  if errorlevel 1 (
    echo Export failed.
    pause
    exit /b 1
  )
)
if not exist %APK% (
  echo %APK% not found: run "run_emulator.bat build" once.
  pause
  exit /b 1
)

"%SDK%\platform-tools\adb.exe" get-state >nul 2>&1
if errorlevel 1 (
  echo Starting the virtual phone %AVD% ...
  start "" "%SDK%\emulator\emulator.exe" -avd %AVD% -no-snapshot-save -no-boot-anim
) else (
  echo The virtual phone is already running.
)
"%SDK%\platform-tools\adb.exe" wait-for-device
:wait_boot
for /f "delims=" %%b in ('"%SDK%\platform-tools\adb.exe" shell getprop sys.boot_completed') do set BOOTED=%%b
if not "%BOOTED%"=="1" (
  timeout /t 2 /nobreak >nul
  goto wait_boot
)

echo Installing ...
"%SDK%\platform-tools\adb.exe" install -r %APK%
echo Opening the game ...
"%SDK%\platform-tools\adb.exe" shell monkey -p com.koyomikotori.kingdomtiles -c android.intent.category.LAUNCHER 1 >nul
echo Done.
