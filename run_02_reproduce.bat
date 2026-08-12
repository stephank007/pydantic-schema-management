@echo off
setlocal

echo.
echo  ==================================================
echo   Step 2 -- Reproduce JSON schemas
echo   From the (enriched) Pydantic models
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
"%PY_DIR%\python.exe" 02_reproduce_schema.py
if %errorlevel% neq 0 (
  echo.
  echo [ERR] 02_reproduce_schema.py failed
  pause & exit /b 1
)

echo.
echo [OK] Done. Generated: project\reproduced\
echo      Next step: run_03_compare.bat
echo.
pause
endlocal
