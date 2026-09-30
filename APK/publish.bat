@echo off
title CSE 62B - Publish APK
color 0A
cd /d "%~dp0"

echo ================================================
echo   CSE 62B - Build ^& Publish APK
echo ================================================
echo.

REM ── Read version from pubspec.yaml (e.g. "version: 1.1.37+48") ──
for /f "tokens=2 delims= " %%v in ('findstr /b /c:"version:" pubspec.yaml') do set FULLVER=%%v
for /f "tokens=1,2 delims=+" %%a in ("%FULLVER%") do (set VNAME=%%a& set VCODE=%%b)
echo Version: %VNAME%  (build code %VCODE%)
echo.

REM ── Release key lives in APK\.release-key (gitignored, never committed) ──
if not exist ".release-key" (
  echo [X] Missing APK\.release-key
  echo     Create it with your RELEASE_PUBLISH_KEY on a single line.
  echo.
  pause
  exit /b 1
)
set /p RELKEY=<.release-key

echo [1/3] flutter pub get ...
call flutter pub get
if errorlevel 1 ( echo pub get FAILED & pause & exit /b 1 )
echo.

echo [2/3] Building release APK (signed) ...
REM  arm64 + arm32 only. The default "fat" APK also carries x86_64 (emulator
REM  only) and lands around 71 MB, which the Worker rejects with 413 -- its
REM  /release-apk limit is 50 MB. This build is ~48 MB and runs on every phone.
call flutter build apk --release --target-platform android-arm,android-arm64
if errorlevel 1 ( echo build FAILED & pause & exit /b 1 )
echo.

echo [3/3] Uploading to app_updates ...
REM  Edit the features / fixes lists below for each release.
REM  Keep them plain ASCII with no < > & | ^ characters: cmd treats those as
REM  redirection/escape operators, which silently breaks the curl call.
curl -sS -X POST https://lucse62b-api.sy164425.workers.dev/release-apk ^
  -H "x-release-key: %RELKEY%" ^
  -H "x-version-name: %VNAME%" ^
  -H "x-version-code: %VCODE%" ^
  -H "x-release-features: [\"Groundwork for upcoming improvements; nothing changes on screen in this version\"]" ^
  -H "x-release-fixes: [\"The class routine and exam schedule load more consistently\", \"Notification categories are applied more reliably\"]" ^
  -H "Content-Type: application/vnd.android.package-archive" ^
  --data-binary @build/app/outputs/flutter-apk/app-release.apk
echo.
echo.
echo ================================================
echo   Finished. Check the response above:
echo   success = update is now live for all apps.
echo ================================================
echo.
pause
