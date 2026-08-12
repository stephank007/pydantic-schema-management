@echo off
setlocal

echo.
echo  ==================================================
echo   Step 1 -- Reverse engineer (one-time setup)
echo   Preprocess schemas + generate Pydantic models
echo  ==================================================
echo.

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "PY_DIR=%ROOT%\runtimes\python310"

if not exist "%PY_DIR%\python.exe" (
  echo [ERR] Python not found. Run install.bat first.
  pause & exit /b 1
)

cd /d "%ROOT%\project"
"%PY_DIR%\python.exe" 01_reverse_engineer.py
if %errorlevel% neq 0 (
  echo.
  echo [ERR] 01_reverse_engineer.py failed
  pause & exit /b 1
)

echo.
echo [OK] Done. Generated: project\schemas\ and project\models\
echo      Next step: run_02_reproduce.bat
echo.
pause
endlocal
