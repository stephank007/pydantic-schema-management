# Transfer list → Windows target

Target: `C:\Users\o6365904\PycharmProjects\pydantic-schema\project\`
Source: `/Users/eithan/opt/dev/pydantic-schema-management/`
Baseline commit: `f2aaf18`

---

## Outstanding — not yet on the target

You already copied `02_reproduce_schema.py` and both `models/*.py` files, and
confirmed them (report showed 15/3). Since then, one code file changed.

### Required — 1 file

| File | Why |
|---|---|
| `03_compare_schemas.py` | The `_is_optional_expansion()` fix (`a31037a`). Without it the report shows 6 phantom `✗` on optional arrays and ZWMS never reaches 0/0. |

### Recommended — 2 files

| File | Why |
|---|---|
| `READING_COMPARISON_REPORT.md` | Explains the 18 remaining findings with a verification command for each. The file that lets anyone read the report without the original conversation. |
| `CHECKPOINT.md` | Full project state, baseline table, traps, onboarding procedure. |

**Do not copy `reproduced/*`** — those regenerate on the target from `02`.
Copying them across machines is how a stale report gets triaged by mistake.

---

## After copying

In PyCharm:

```
02_reproduce_schema.py
03_compare_schemas.py
```

Expected result:

| Schema | Missing | Structural Δ |
|---|---|---|
| `wms_envelope` | 6 | 0 |
| `wms_business_types` | 12 | 2 |
| `ZWMS_INBOUND_DELIVERY_CREATE` | **0** | **0** |

`02` must print **368 types** for business-types and emit **no warnings**.

The report still ends with `✗ Structural differences found`. That is expected —
it fires on the 6 accepted envelope diffs. Not a failure.

---

## Full file list — if rebuilding the target from scratch

Copy all of these into `project\`:

```
01_reverse_engineer.py
02_reproduce_schema.py
03_compare_schemas.py
validate_messages.py
requirements.txt
models/                      ← the payload: 227 Field() constraints
bootstrap/                   ← signed originals, never edited
CHECKPOINT.md
READING_COMPARISON_REPORT.md
CLAUDE.md
SCHEMA_REVERSE_ENGINEERING.md
SKILL.md
process_diagram.svg
```

Skip: `reproduced/`, `schemas/` (both regenerate), `__pycache__/`,
`python_wheels/` (already on the target; 5.8M of win_amd64 binaries).

Leave untouched at the bundle root: `runtimes/`, `python_wheels/`,
`install.bat`. No pip install needed — `pydantic` is 2.13.4 on both sides and
`02`/`03` import only `pydantic` plus stdlib.

---

## Rules

- **Never run `01_reverse_engineer.py`.** It deletes `models/`, which is
  hand-enriched and the source of truth. Guarded since `ecc5a53` (needs
  `--force`), but do not test the guard.
- **Never copy `reproduced/` between machines.** Regenerate with `02`.
- **Treat `UnsupportedFieldAttributeWarning` from `02` as an error.** It means
  a `Field()` is being silently ignored — that is how seven properties shipped
  as `BOL_1` instead of `BOL` for months.
- **A count going *up* is the signal.** Compare against the baseline table
  above, not against zero.

---

## Known cross-machine difference (not a bug)

`Missing` and `Structural Δ` are identical on both machines. `Added` and
`Enrichments` differ slightly — Mac runs pydantic 2.12.5 on py3.13, target runs
2.13.4 on py3.10, and the two emit different amounts of `title`/`description`
metadata. Those are the document-and-ignore buckets.

To make reports byte-identical, pin `requirements.txt` to `pydantic==2.13.4`.
Currently unpinned, which let 7 of 29 wheels float during the last package
rebuild.
