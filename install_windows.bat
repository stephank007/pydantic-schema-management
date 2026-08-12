@echo off
setlocal EnableDelayedExpansion

echo.
echo  ==================================================
echo   Pydantic Schema Management -- Windows Installer
echo  ==================================================
echo.

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

set "PY_EXE=%ROOT%\runtimes\python-3.10.11-amd64.exe"
set "PY_DIR=%ROOT%\runtimes\python310"

REM ── 1. Install Python silently if needed ─────────────────────────────────────

if exist "%PY_DIR%\python.exe" (
  echo [OK] Python already installed
) else (
  echo [..] Installing Python 3.10 (silent, no internet)...
  if not exist "%PY_EXE%" (
    echo [ERR] Missing: %PY_EXE%
    pause & exit /b 1
  )
  "%PY_EXE%" /quiet InstallAllUsers=0 PrependPath=0 ^
    TargetDir="%PY_DIR%" Include_launcher=0 Include_test=0
  if not exist "%PY_DIR%\python.exe" (
    echo [ERR] Python install failed
    pause & exit /b 1
  )
  echo [OK] Python installed to %PY_DIR%
)

REM ── 2. Install Python dependencies from offline wheels ───────────────────────

echo [..] Installing Python dependencies (offline, from python_wheels)...
"%PY_DIR%\python.exe" -m pip install ^
  --no-index ^
  --find-links "%ROOT%\python_wheels" ^
  -r "%ROOT%\project\requirements.txt" ^
  --quiet
if %errorlevel% neq 0 (
  echo [ERR] pip install failed -- could not resolve all packages from python_wheels
  pause & exit /b 1
)
echo [OK] Python dependencies installed

echo.
echo  ==================================================
echo   Installation complete.
echo.
echo   Pipeline (run in order):
echo     run_01_reverse_engineer.bat   (one-time setup)
echo     run_02_reproduce.bat
echo     run_03_compare.bat
echo     run_validate.bat
echo  ==================================================
echo.
pause
endlocal
