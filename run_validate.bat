@echo off
setlocal

echo.
echo  ==================================================
echo   Validate messages
echo   Bootstrap schema + Pydantic model + reproduced
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
"%PY_DIR%\python.exe" validate_messages.py
if %errorlevel% neq 0 (
  echo.
  echo [ERR] validate_messages.py failed
  pause & exit /b 1
)

echo.
echo [OK] Validation complete.
echo.
pause
endlocal
