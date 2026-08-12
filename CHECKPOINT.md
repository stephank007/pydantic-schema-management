# Checkpoint — 2026-08-12 (end of transfer + triage session)

Supersedes the earlier mid-transfer checkpoint. Transfer is complete, the
target and the Mac now agree, and the outstanding model defects are fixed.

## Where things stand

| | |
|---|---|
| Branch | `main`, clean, pushed to `origin` |
| HEAD | `69cb96b` |
| Target | `C:\Users\o6365904\PycharmProjects\pydantic-schema\project` (PyCharm, py3.10, pydantic 2.13.4) |
| Mac | py3.13, pydantic 2.12.5 |
| Report | 24 `✗` + 2 `Δ`, all catalogued, **no model defects** |

Commits this session:

- `ecc5a53` — Windows/offline support + guard `01` against destroying `models/`
- `98ac847` — `package_offline`: stop shipping `run_01` as step 1
- `b596076` — first checkpoint
- `65e3808` — `package_offline`: stop duplicating `python_wheels` into `project/`
- `2b64fd3` — `02`: skip memberless enum bases (3.10 `StrEnum` shim leak)
- `4d0084b` — **models: fix `Field()` on union members + restore lost constraints**
- `69cb96b` — rewrite `READING_COMPARISON_REPORT.md` against the verified baseline

## Is `02`'s output trustworthy?

**Yes — it is the deliverable, and it is sound.** The three files in
`reproduced/` are faithful to bootstrap: property names match, constraints are
present, `02` emits zero warnings.

**But `02` alone is not self-validating.** It happily emitted `BOL_1`,
`BATCH_1`, `LOT_1`, `MILSTRIP_1`, `RECEIPT_1`, `SERIAL_1`, `SPED_1` for months
while printing `UnsupportedFieldAttributeWarning` on every run. What caught it
was `03` disagreeing with bootstrap. Treat a clean `02` as necessary, not
sufficient — the three-layer check (`02` → `03` → `validate_messages.py`) is
what makes it verifiable.

Practical rule: **`03`'s remaining findings are its own limitations; `03`
producing a *new* finding is a real signal.** Compare against the catalogue in
`READING_COMPARISON_REPORT.md`, not against zero.

## The 24 remaining findings — none are defects

| Section | Count | Cause |
|---|---|---|
| A | 6 `✗` | Envelope: `unevaluatedProperties`→`additionalProperties`, Header inlined→`$ref`. Accepted permanent diffs. |
| B | 10 `✗` | `maxLength: 0` empty-string sentinel — deliberate in bootstrap. **Never "fix" these.** |
| C | 2 `✗` + 2 `Δ` | `_reconcile_def_names()` pairs colliding names wrongly (`ISSUE_ST_LOC`/`ISSUE_STLOC`, `MATERIAL_TYPE`/`MATERIALTYPE`). |
| D | 6 `✗` | Optional arrays: `items`/`maxItems`/`type` are present inside `anyOf[0]`; the comparator only checks top level. |

Full evidence and verification commands in `READING_COMPARISON_REPORT.md`.

Section C is **not automatically fixable** — an attempt to pair by constraint
shape made the count worse (15→16). `MATERIALTYPE` and `MATERIALTYPE1` are both
a bare `{"type": "string"}` in the reproduced schema, since descriptions become
Python docstrings rather than schema fields.

## Scaling to ~20 more interface schemas

This is the next piece of work. The pipeline handles it, but **three registries
are hand-maintained and one script is hardcoded to a single interface**:

1. **`01_reverse_engineer.py:34`** — `INTERFACE_FILE` is a single hardcoded
   path. Preprocessing (`prepare_schemas`) handles exactly one interface schema.
   **This is the real blocker** — it needs to loop over
   `bootstrap/*.schema.json` minus the envelope and business-types files.
2. **`02_reproduce_schema.py:32`** — `EXPORT_TARGETS`, a list of
   `(out_filename, module_stem, root_class_name)`. One entry per schema.
3. **`03_compare_schemas.py:29`** — `COMPARE_PAIRS`, a list of
   `(bootstrap_path, reproduced_path)`. One entry per schema.

Adding 20 schemas by hand means 20 entries in each of (2) and (3), plus
rewriting (1). Recommended: derive all three from a single manifest, or by
convention from `bootstrap/` filenames.

**Per-schema cost after that:** each new interface needs its `$ref`s into
`business-types` and `envelope` to resolve, and its root class named. The
enrichment burden is small for interfaces — `business_types_schema.py` carries
227 `Field()` constraints and is the shared vocabulary; interface schemas mostly
`$ref` into it.

**Expect the same class of findings to multiply.** Sections B and D are
per-occurrence: every optional array costs ~3 `✗`, every empty-string sentinel
~2. With 20 more schemas the raw count could reach the low hundreds while still
containing zero defects. Two implications:

- Fixing `_is_optional_expansion()` to look inside `anyOf[0]` (section D) is
  worth doing **before** scaling — it is a single-site fix that scales linearly
  in savings.
- The catalogue-based reading in `READING_COMPARISON_REPORT.md` does not scale
  to hundreds of lines by eye. Consider a `--summary` flag on `03` that reports
  counts per cause-category rather than per-line.

## Traps (all have actually bitten this project)

- **`Field()` on a union member is silently ignored.**
  `Annotated[X, Field(...)] | None` is broken; `Annotated[X | None, Field(...)]`
  is correct. Treat `UnsupportedFieldAttributeWarning` as an error.
- **`01_reverse_engineer.py` deletes `models/`.** One-time bootstrap only.
  Guarded since `ecc5a53` (needs `--force`). Never run it to "start fresh".
- **`uniqueItems`** needs `json_schema_extra` *and* an `AfterValidator` —
  otherwise the schema claims a constraint the model does not enforce.
- **Never triage a report you did not just regenerate.** Reading a stale
  `reproduced/` produced a wrong conclusion twice in this session.
- **Windows/3.10 vs macOS/3.13**: pass `encoding="utf-8"` everywhere;
  `enum.StrEnum` is 3.11+ (shim in the models, and `02` skips memberless enum
  bases so it does not leak into `$defs`); offline wheels need `tomli` and
  `colorama` fetched explicitly.

## Cross-machine differences (expected, not bugs)

`Missing` and `Structural Δ` are **identical** on both machines: 6/15/3 and
0/2/0. `Added` and `Enrichments` differ (Mac 6/38/94 and 29/673/90; target
6/39/94 and 23/659/90) because pydantic 2.12.5 and 2.13.4 emit slightly
different metadata. Those are the document-and-ignore buckets.

`requirements.txt` is **unpinned** (`pydantic`, `datamodel-code-generator`,
`jsonschema`). A rebuild floated 7 of 29 wheels. Pin it before the next
package build if byte-identical reports matter.

## Workflow

```bash
python 02_reproduce_schema.py   # regenerate reproduced/*.schema.json
python 03_compare_schemas.py    # regenerate COMPARISON_REPORT.txt
python validate_messages.py     # confirm all three layers agree
```

Never run `01_reverse_engineer.py`.

## Housekeeping still open

- Root `COMPARISON_REPORT.txt` is **stale** (1331 lines, Missing: 316) and
  disagrees with `reproduced/COMPARISON_REPORT.txt`. Regenerate or delete.
- `python_wheels/` is gitignored (5.8M win_amd64); rebuild via
  `package_offline.sh`, it will not arrive through git.
- `READING_COMPARISON_REPORT.md` should be copied to the target — it is the
  file that explains the report to anyone opening it without this context.
