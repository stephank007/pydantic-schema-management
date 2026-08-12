#!/usr/bin/env bash
# ==============================================================================
#  package_offline.sh
#
#  Offline package builder — Windows target
#  Run from project root on macOS/Linux
#
#  Produces (flat directory tree, no zip):
#    ~/Downloads/pydantic_schema_windows/
#
#  The package contains everything an air-gapped Windows machine needs:
#    runtimes/python-3.10.11-amd64.exe   — Python installer
#    python_wheels/                      — complete, pre-resolved wheel set
#    project/                            — this project's source
#    install.bat / install.ps1           — offline installer
#    run_01..03 / run_validate .bat      — one script per pipeline step
# ==============================================================================

set -Eeuo pipefail

# ───────────────────────────────────────────────────────────────────────────────
# Configuration
# ───────────────────────────────────────────────────────────────────────────────

PYTHON_VERSION="3.10.11"
PIP_PY_VERSION="3.10"          # resolver target for pip download

PYTHON_WIN_EXE="python-${PYTHON_VERSION}-amd64.exe"
PYTHON_BASE="https://www.python.org/ftp/python/${PYTHON_VERSION}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BUILD="${ROOT}/_build"
CACHE="${BUILD}/_cache"

DOWNLOADS="${HOME}/Downloads"
WIN="${DOWNLOADS}/pydantic_schema_windows"

# ───────────────────────────────────────────────────────────────────────────────
# Colours
# ───────────────────────────────────────────────────────────────────────────────

C='\033[0;36m'
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
N='\033[0m'

step()  { echo -e "\n${C}▸ $*${N}"; }
ok()    { echo -e "  ${G}✓${N}  $*"; }
warn()  { echo -e "  ${Y}!${N}  $*"; }
die()   { echo -e "  ${R}✗${N}  $*" >&2; exit 1; }

on_error() {
  local line="$1"
  echo ""
  die "Script failed at line ${line}"
}

trap 'on_error $LINENO' ERR

# ───────────────────────────────────────────────────────────────────────────────
# Helper: download with cache
# ───────────────────────────────────────────────────────────────────────────────

fetch() {
  local url="$1"
  local dest="$2"

  local name
  name="$(basename "$url")"

  local cached="${CACHE}/${name}"

  mkdir -p "$(dirname "$dest")"

  if [[ -f "$cached" ]]; then
    echo "  cached  ${name}"
  else
    echo "  downloading  ${name}"

    curl \
      --fail \
      --location \
      --progress-bar \
      "$url" \
      --output "$cached" \
      || die "Download failed: $url"
  fi

  cp "$cached" "$dest"
}

# ───────────────────────────────────────────────────────────────────────────────
# Banner
# ───────────────────────────────────────────────────────────────────────────────

echo ""
echo "  ┌─────────────────────────────────────────────────┐"
echo "  │   Pydantic Schema Mgmt — Offline Win Package    │"
printf "  │   Python %-10s                             │\n" "${PYTHON_VERSION}"
echo "  └─────────────────────────────────────────────────┘"
echo ""
echo "  Output: ${WIN}"
echo ""

# ───────────────────────────────────────────────────────────────────────────────
# Pre-flight
# ───────────────────────────────────────────────────────────────────────────────

step "Pre-flight checks"

for cmd in curl python3 rsync; do
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd not found."
done

for f in requirements.txt 01_reverse_engineer.py 02_reproduce_schema.py 03_compare_schemas.py; do
  [[ -f "${ROOT}/${f}" ]] || die "${f} not found."
done

[[ -d "${ROOT}/bootstrap" ]] || die "bootstrap/ not found."

for f in install_windows.bat install_windows.ps1 \
         run_01_reverse_engineer.bat run_02_reproduce.bat \
         run_03_compare.bat run_validate.bat; do
  [[ -f "${ROOT}/${f}" ]] || die "${f} not found (must exist in project root)."
done

ok "All pre-flight checks passed"

# ───────────────────────────────────────────────────────────────────────────────
# Prepare output directories
# ───────────────────────────────────────────────────────────────────────────────

step "Preparing output directories"

rm -rf "${WIN}"

mkdir -p \
  "${CACHE}" \
  "${WIN}/runtimes" \
  "${WIN}/python_wheels" \
  "${WIN}/project"

ok "Output directory ready → ${WIN}"

# ───────────────────────────────────────────────────────────────────────────────
# 1 / 4  Python Windows installer
# ───────────────────────────────────────────────────────────────────────────────

step "1 / 4  Python Windows installer"

fetch \
  "${PYTHON_BASE}/${PYTHON_WIN_EXE}" \
  "${WIN}/runtimes/${PYTHON_WIN_EXE}"

ok "Windows Python installer ready"

# ───────────────────────────────────────────────────────────────────────────────
# 2 / 4  Python wheels — complete, resolver-driven set
#
# pip resolves the FULL dependency tree for win_amd64 / cp310 here, so the
# wheel set is complete by construction. Any failure is fatal: an incomplete
# set means pip install cannot resolve on the air-gapped Windows machine.
# ───────────────────────────────────────────────────────────────────────────────

step "2 / 4  Python wheels (win_amd64, cp310)"

echo "  Resolving full dependency tree for Windows..."

python3 -m pip download \
  --only-binary=:all: \
  --platform win_amd64 \
  --implementation cp \
  --python-version "${PIP_PY_VERSION}" \
  -r "${ROOT}/requirements.txt" \
  -d "${WIN}/python_wheels" \
  --quiet \
  || die "Wheel resolution failed — the offline set would be incomplete. Aborting."

# ---------------------------------------------------------------------------
# Marker-guarded supplement.
#
# `pip download --platform/--python-version` only sets wheel COMPATIBILITY
# TAGS; it does NOT change how environment markers are evaluated — those are
# evaluated against the HOST running pip (this macOS/Linux box, Python 3.11+).
# So any dependency guarded by a marker that is False on the host but True on
# the Windows/3.10 target is silently skipped above. Two known cases:
#   - tomli    : datamodel-code-generator dep, marker `python_version < 3.11`
#                (True on the 3.10 target, False on this 3.11+ host).
#   - colorama : click's Windows dep, marker `platform_system == "Windows"`
#                (True on the Windows target, False on this non-Windows host).
# Without this step the Windows/3.10 install fails with e.g.
#   "No matching distribution found for tomli<3,>=2.2.1; python_version < 3.11"
#
# We fetch these explicitly with --no-deps so the target has them regardless of
# how the host evaluates the marker.
# ---------------------------------------------------------------------------
MARKER_GUARDED_DEPS=(
  "tomli>=2.2.1,<3"
  "colorama"
)

for dep in "${MARKER_GUARDED_DEPS[@]}"; do
  python3 -m pip download \
    --only-binary=:all: \
    --platform win_amd64 \
    --implementation cp \
    --python-version "${PIP_PY_VERSION}" \
    --no-deps \
    "${dep}" \
    -d "${WIN}/python_wheels" \
    --quiet \
    || die "Failed to fetch marker-guarded dependency: ${dep}"
done

# Post-check 1: no sdists — everything must be a wheel
SDIST_COUNT=$(find "${WIN}/python_wheels" -type f ! -name '*.whl' | wc -l | tr -d ' ')
[[ "$SDIST_COUNT" -eq 0 ]] \
  || die "${SDIST_COUNT} non-wheel file(s) in python_wheels/ — sdists cannot install offline."

# Post-check 2: every top-level requirement has a wheel
for pkg in pydantic datamodel_code_generator jsonschema; do
  ls "${WIN}/python_wheels/${pkg}"-*.whl >/dev/null 2>&1 \
    || die "No wheel found for required package: ${pkg}"
done

# Post-check 3: known binary dependency is the correct platform build
ls "${WIN}/python_wheels/"pydantic_core-*cp310*win_amd64.whl >/dev/null 2>&1 \
  || die "pydantic_core cp310/win_amd64 wheel missing."

# Post-check 3b: marker-guarded deps are present. The --no-index resolvability
# check below runs under THIS host's interpreter (3.11+), which evaluates the
# `python_version < 3.11` markers as False and therefore will NOT catch a
# missing tomli. Assert their wheels exist explicitly.
ls "${WIN}/python_wheels/"tomli-*.whl >/dev/null 2>&1 \
  || die "tomli wheel missing — Python 3.10 target requires it (see MARKER_GUARDED_DEPS)."
ls "${WIN}/python_wheels/"colorama-*.whl >/dev/null 2>&1 \
  || die "colorama wheel missing — Windows target requires it (click dep; see MARKER_GUARDED_DEPS)."

# Post-check 4: prove the tree resolves from the bundle ALONE (no index).
# This is the same resolution pip install will perform on the Windows box.
echo "  Verifying offline resolvability (--no-index)..."

RESOLVE_CHECK="${BUILD}/_resolve_check"
rm -rf "${RESOLVE_CHECK}"
mkdir -p "${RESOLVE_CHECK}"

python3 -m pip download \
  --no-index \
  --find-links "${WIN}/python_wheels" \
  --only-binary=:all: \
  --platform win_amd64 \
  --implementation cp \
  --python-version "${PIP_PY_VERSION}" \
  -r "${ROOT}/requirements.txt" \
  -d "${RESOLVE_CHECK}" \
  --quiet \
  || die "Offline resolution check FAILED — wheel set is incomplete."

rm -rf "${RESOLVE_CHECK}"

WHEEL_COUNT=$(find "${WIN}/python_wheels" -name '*.whl' | wc -l | tr -d ' ')
ok "Wheel set complete and verified offline-resolvable (${WHEEL_COUNT} wheels)"

# ───────────────────────────────────────────────────────────────────────────────
# 3 / 4  Project source
# ───────────────────────────────────────────────────────────────────────────────

step "3 / 4  Project source"

EXCLUDES=(
  --exclude='.git/'
  --exclude='.venv/'
  --exclude='venv/'
  --exclude='__pycache__/'
  --exclude='*.pyc'
  --exclude='*.pyo'
  --exclude='_build/'
  --exclude='.DS_Store'
  --exclude='schemas/'
  --exclude='reproduced/'
  --exclude='COMPARISON_REPORT.txt'
  --exclude='package_offline.sh'
  --exclude='install_windows.bat'
  --exclude='install_windows.ps1'
  --exclude='run_01_reverse_engineer.bat'
  --exclude='run_02_reproduce.bat'
  --exclude='run_03_compare.bat'
  --exclude='run_validate.bat'
)

rsync -a "${EXCLUDES[@]}" "${ROOT}/" "${WIN}/project/"

FILE_COUNT=$(find "${WIN}/project" -type f | wc -l | tr -d ' ')
ok "Project source copied (${FILE_COUNT} files)"

# ───────────────────────────────────────────────────────────────────────────────
# 4 / 4  Scripts + README
# ───────────────────────────────────────────────────────────────────────────────

step "4 / 4  Installer scripts and README"

cp "${ROOT}/install_windows.bat"          "${WIN}/install.bat"
cp "${ROOT}/install_windows.ps1"          "${WIN}/install.ps1"
cp "${ROOT}/run_01_reverse_engineer.bat"  "${WIN}/run_01_reverse_engineer.bat"
cp "${ROOT}/run_02_reproduce.bat"         "${WIN}/run_02_reproduce.bat"
cp "${ROOT}/run_03_compare.bat"           "${WIN}/run_03_compare.bat"
cp "${ROOT}/run_validate.bat"             "${WIN}/run_validate.bat"

cat > "${WIN}/README.txt" <<'EOF'
Pydantic Schema Management — Windows (offline)
===============================================

Fully offline package. No internet access required on this machine.

Install
-------
1. Run install.bat   (or install.ps1 in PowerShell)
   - Installs Python 3.10 locally under runtimes\python310
   - Installs all Python dependencies from the bundled python_wheels\

Pipeline
--------
Run the steps in order:

  run_01_reverse_engineer.bat   ONE-TIME setup: preprocess schemas,
                                generate Pydantic models
  run_02_reproduce.bat          Reproduce JSON schemas from Pydantic models
  run_03_compare.bat            Diff bootstrap vs reproduced schemas
                                → project\COMPARISON_REPORT.txt
  run_validate.bat              Validate sample messages against all layers

Recurring workflow after editing models\:  run_02 → run_03.
EOF

ok "Scripts and README added"

# ───────────────────────────────────────────────────────────────────────────────
# Final summary
# ───────────────────────────────────────────────────────────────────────────────

WSIZE=$(du -sh "${WIN}" | cut -f1)

echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │   Build Complete                                        │"
echo "  │                                                         │"
printf "  │   Windows  ~/Downloads/pydantic_schema_windows  %-6s │\n" "${WSIZE}"
echo "  │                                                         │"
echo "  │   Copy the folder to the target machine and run         │"
echo "  │   install.bat, then the run_*.bat scripts in order.     │"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""

ok "Offline package created successfully"
