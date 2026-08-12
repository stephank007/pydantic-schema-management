# Checkpoint — 2026-08-12

State captured while the offline package transfer to the isolated Windows environment was
underway. Written so work can resume cold.

## Where things stand

| | |
|---|---|
| Branch | `main`, clean, pushed to `origin` |
| HEAD | `98ac847` |
| Bundle | `~/Downloads/pydantic_schema_windows/` — 40M, rebuilt 2026-08-12 |
| Transfer | In progress at time of writing; target report not yet seen |

Commits this session:

- `ecc5a53` — Windows/offline support + guard `01` against destroying `models/`
- `98ac847` — `package_offline`: stop shipping `run_01` as step 1 of the pipeline

Only uncommitted file is `.claude/settings.local.json` (local tool permissions, intentionally
not tracked).

## What was fixed

**1. `01_reverse_engineer.py` destroys `models/`.**
It calls `shutil.rmtree(MODELS_OUT)` and regenerates from `bootstrap/`. But `models/` is
generated *then hand-enriched* (~225 `Field()` constraints) and is the project's source of
truth per CLAUDE.md. `guard_existing_models()` now runs at the top of `main()` and exits 1 if
`models/` exists, unless `--force` is passed. Verified: aborts before touching any file, and
fires on direct `python` invocation (not just via the `.bat` wrapper).

**2. The bundle told operators to run that script first.**
`package_offline.sh` rsyncs the *enriched* `models/` into `project/`, then its generated
README said to run `run_01_reverse_engineer.bat` as step 1 — destroying what the bundle had
just delivered. This was a packaging defect, not operator error. Now: `run_01` is parked in
`_rebootstrap/` instead of the bundle root, the README starts at step 2, and a preflight
assertion refuses to build a bundle whose `business_types_schema.py` has fewer than 200
`Field()` constraints.

**3. Windows/Python 3.10 compatibility.**
StrEnum backport shim in `models/business_types_schema.py` (`enum.StrEnum` is 3.11+);
`--target-python-version 3.10`; `read_text(encoding="utf-8")` so codegen does not die on the
Hebrew descriptions under Windows cp1255.

## What is still open

Running `02` → `03` locally against a **fully-enriched, never-wiped** `models/` yields
**~36 `✗` and 2 `Δ`**. The wipe does not explain these — they are genuine gaps in the
enrichment layer and were present on Windows for the same reason.

Confirmed real:

- `DocItem.SERIAL_NUMBERS` / `InboundDocItem.SERIAL_NUMBERS` — bootstrap has
  `uniqueItems: true`, `maxItems: 999`, `items.$ref`; the model carries only
  `Field(max_length=999)`. A Pydantic `list` cannot express uniqueness — needs a `set` or an
  `AfterValidator`.
- `DocItem.CUSTOM_FIELDS` — bootstrap has `additionalProperties: {type: string,
  maxLength: 255}` and `maxProperties: 20`; a bare `dict[str, str]` loses both.
- `ISSUE_ST_LOC` / `MATERIAL_TYPE` — in bootstrap with Hebrew descriptions; models have only
  `ISSUESTLOC1` (:1958) / `MATERIALTYPE1` (:2008). Check codegen-renamed identity before
  adding anything.

Not defects, do not "fix":

- **`maxLength: 0`** is deliberate in bootstrap — the empty-string arm of an `anyOf` sentinel
  meaning "field present but blank" — for `TRANSIT_DOCKING_PLANT`, `NUMERIC_VALUE`,
  `SHELF_LIFE_EXP_DATE`, `HuItem.SERIAL_NUMBER`. Codegen dedupes it into one shared
  `SERIALNUMBER(RootModel[str])` that the others inherit.
- The 2 `Δ` lines (`SERIAL_NUMBER` 18→0, `TRANSIT_DOCKING_PLANT` 4→0) are
  `_reconcile_def_names()` in `03_compare_schemas.py` collapsing distinct bootstrap defs onto
  that shared class via underscore normalisation. Comparator artifact.
- The 6 envelope `✗` lines (`unevaluatedProperties`, Header inlined → `$defs`) are permanent
  accepted diffs.
- The trailing `✗ Structural differences found` fires even on the accepted diffs. Not a
  failure signal on its own.

## Resuming

On the target (PyCharm, running `.py` directly — the `.bat` files are only launchers and are
not needed):

```
python 02_reproduce_schema.py
python 03_compare_schemas.py
```

Never run `01`. Read only `✗` and `Δ` lines in `reproduced/COMPARISON_REPORT.txt`.

**Expected shape: ~36 `✗`, 2 `Δ`.** That means the transfer worked and what remains is model
work. A materially different result — especially ~29 with different content — means
`models/` was regenerated; restore it and re-run `02`.

## Caveats

- **Pydantic version skew.** The ~36/2 figure came from a local run on pydantic **2.12.5**;
  the target runs **2.13.4**. That local run emitted 7 extra
  `Body.properties.{BATCH,BOL,LOT,MILSTRIP,RECEIPT,SERIAL,SPED}` lines absent from the Windows
  report. **The target's own report is authoritative.** Match pydantic versions before
  comparing reports across machines.
- **`requirements.txt` is unpinned** (`pydantic`, `datamodel-code-generator`, `jsonschema`).
  The 2026-08-12 rebuild floated 7 of 29 wheels to newer versions. `pydantic` /
  `pydantic_core` happened to be unchanged, so schema generation was unaffected — by luck, not
  design. Worth pinning.
- **Root `COMPARISON_REPORT.txt` is stale** (1331 lines, Missing: 316) and disagrees with
  `reproduced/COMPARISON_REPORT.txt`. Regenerate or delete it; triaging it would chase ~300
  phantom findings.
- **`python_wheels/` is gitignored** (5.8M of win_amd64 binaries). Rebuild with
  `package_offline.sh`; it will not arrive via git.

## Transfer recap

Copy `~/Downloads/pydantic_schema_windows/project/` over the target's `project/`. Leave the
target's `python_wheels/`, `runtimes/`, and `install.bat` alone — no pip install needed,
since `pydantic` is identical at 2.13.4 and `02`/`03` import only `pydantic` and stdlib.
