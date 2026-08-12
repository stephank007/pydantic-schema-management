@echo off
setlocal

echo.
echo  ==================================================
echo   Step 3 -- Compare schemas
echo   Diff bootstrap vs reproduced
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
"%PY_DIR%\python.exe" 03_compare_schemas.py
if %errorlevel% neq 0 (
  echo.
  echo [ERR] 03_compare_schemas.py failed
  pause & exit /b 1
)

echo.
echo [OK] Done. Report: %ROOT%\project\COMPARISON_REPORT.txt
echo.
pause
endlocal
