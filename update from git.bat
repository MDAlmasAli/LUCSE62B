@echo off
title CSE 62B Website - Auto Update
color 0A

echo ================================================
echo   CSE 62B Website - Updating from GitHub...
echo ================================================
echo.

cd /d "%~dp0"

echo [1/4] Cleaning up any stuck git lock...
if exist ".git\index.lock" del /f /q ".git\index.lock"
echo.

echo [2/4] Fetching latest from GitHub...
git fetch origin main
if errorlevel 1 goto :failed
echo.

echo [3/4] Applying update (keeps your local edits and commits)...
git pull --rebase --autostash origin main
if errorlevel 1 goto :conflict
echo.

echo [4/4] Update successful!
echo.
echo ================================================
echo   All changes downloaded - your work is kept!
echo ================================================
echo.
pause
exit /b 0

:conflict
echo.
echo ================================================
echo   Update stopped: your changes clash with the
echo   new update and need manual fixing.
echo.
echo   Nothing is lost. To undo and try later, run:
echo       git rebase --abort
echo ================================================
echo.
pause
exit /b 1

:failed
echo.
echo ================================================
echo   Update FAILED. Check your internet or git.
echo ================================================
echo.
pause
exit /b 1
