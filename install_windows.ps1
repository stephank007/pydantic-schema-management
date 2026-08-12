#Requires -Version 5.1
<#
.SYNOPSIS
  Pydantic Schema Management — Windows offline installer (PowerShell version)
#>

$ErrorActionPreference = 'Stop'
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path

function Step($msg) { Write-Host "`n[..] $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "[OK] $msg"   -ForegroundColor Green }
function Err($msg)  { Write-Host "[ERR] $msg"  -ForegroundColor Red; Read-Host "Press Enter to exit"; exit 1 }

Write-Host ""
Write-Host "  ==================================================" -ForegroundColor Cyan
Write-Host "   Pydantic Schema Management -- Windows Installer"   -ForegroundColor Cyan
Write-Host "  ==================================================" -ForegroundColor Cyan
Write-Host ""

$PyExe   = Join-Path $ROOT "runtimes\python-3.10.11-amd64.exe"
$PyDir   = Join-Path $ROOT "runtimes\python310"
$Wheels  = Join-Path $ROOT "python_wheels"
$ReqsTxt = Join-Path $ROOT "project\requirements.txt"

# ── 1. Install Python ─────────────────────────────────────────────────────────

Step "Installing Python 3.10"

if (Test-Path "$PyDir\python.exe") {
    OK "Python already installed"
} else {
    if (-not (Test-Path $PyExe)) { Err "Missing: $PyExe" }
    $argList = "/quiet InstallAllUsers=0 PrependPath=0 TargetDir=`"$PyDir`" Include_launcher=0 Include_test=0"
    Start-Process -FilePath $PyExe -ArgumentList $argList -Wait -NoNewWindow
    if (-not (Test-Path "$PyDir\python.exe")) { Err "Python install failed" }
    OK "Python installed → $PyDir"
}

# ── 2. Python dependencies ────────────────────────────────────────────────────

Step "Installing Python dependencies (offline)"

if (-not (Test-Path $ReqsTxt)) { Err "Missing: $ReqsTxt" }
if (-not (Test-Path $Wheels))  { Err "Missing wheels directory: $Wheels" }

& "$PyDir\python.exe" -m pip install `
    --no-index `
    --find-links $Wheels `
    -r $ReqsTxt `
    --quiet

if ($LASTEXITCODE -ne 0) { Err "pip install failed -- could not resolve all packages from python_wheels" }
OK "Python dependencies installed"

# ── Done ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ==================================================" -ForegroundColor Green
Write-Host "   Installation complete."                            -ForegroundColor Green
Write-Host ""
Write-Host "   Pipeline (run in order):"                          -ForegroundColor Green
Write-Host "     run_01_reverse_engineer.bat   (one-time setup)"  -ForegroundColor Green
Write-Host "     run_02_reproduce.bat"                            -ForegroundColor Green
Write-Host "     run_03_compare.bat"                              -ForegroundColor Green
Write-Host "     run_validate.bat"                                -ForegroundColor Green
Write-Host "  ==================================================" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to exit"
