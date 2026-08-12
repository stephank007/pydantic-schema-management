# Checkpoint — 2026-08-12 (end of transfer + triage session)

Supersedes the earlier mid-transfer checkpoint. Transfer is complete, the
target and the Mac now agree, and the outstanding model defects are fixed.

## Where things stand

| | |
|---|---|
| Branch | `main`, clean, pushed to `origin` |
| HEAD | `a31037a` |
| Target | `C:\Users\o6365904\PycharmProjects\pydantic-schema\project` (PyCharm, py3.10, pydantic 2.13.4) |
| Mac | py3.13, pydantic 2.12.5 |
| Report | **18 `✗` + 2 `Δ`**, all catalogued, **no model defects** |

Per-schema baseline — this is what a correct run looks like:

| Schema | Missing | Structural Δ |
|---|---|---|
| `wms_envelope` | 6 | 0 |
| `wms_business_types` | 12 | 2 |
| `ZWMS_INBOUND_DELIVERY_CREATE` | **0** | **0** |

`ZWMS_INBOUND_DELIVERY_CREATE` reproducing at 0/0 is the reference standard:
**a newly onboarded interface schema should also land at 0/0.** Anything else
deserves investigation.

Commits this session:

- `ecc5a53` — Windows/offline support + guard `01` against destroying `models/`
- `98ac847` — `package_offline`: stop shipping `run_01` as step 1
- `b596076` — first checkpoint
- `65e3808` — `package_offline`: stop duplicating `python_wheels` into `project/`
- `2b64fd3` — `02`: skip memberless enum bases (3.10 `StrEnum` shim leak)
- `4d0084b` — **models: fix `Field()` on union members + restore lost constraints**
- `69cb96b` — rewrite `READING_COMPARISON_REPORT.md` against the verified baseline
- `4691211` — checkpoint after transfer
- `a31037a` — **`03`: fold `anyOf` siblings into the optional-expansion match**
  (24→18; ZWMS to 0/0)

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

## The 18 remaining findings — none are defects

| Section | Count | Cause |
|---|---|---|
| A | 6 `✗` | Envelope: `unevaluatedProperties`→`additionalProperties`, Header inlined→`$ref`. Accepted permanent diffs. |
| B | 10 `✗` | `maxLength: 0` empty-string sentinel — deliberate in bootstrap. **Never "fix" these.** |
| C | 2 `✗` + 2 `Δ` | `_reconcile_def_names()` pairs colliding names wrongly (`ISSUE_ST_LOC`/`ISSUE_STLOC`, `MATERIAL_TYPE`/`MATERIALTYPE`). |
| D | — | **Fixed in `a31037a`.** Was 6 `✗` on optional arrays. |

Full evidence and verification commands in `READING_COMPARISON_REPORT.md`.

Section C is **not automatically fixable** — an attempt to pair by constraint
shape made the count worse (15→16). `MATERIALTYPE` and `MATERIALTYPE1` are both
a bare `{"type": "string"}` in the reproduced schema, since descriptions become
Python docstrings rather than schema fields.

Section D was fixed by folding `anyOf`'s siblings into the non-null branch
before matching. Merging rather than ignoring the key keeps the check honest —
verified that a dropped `uniqueItems` and a changed `maxItems` are both still
reported.

## Onboarding the remaining ~20 interface schemas

**Decided approach (2026-08-12): one schema at a time, manually, no batch
automation.** The pace is deliberate — the team needs to be brought along, so
each schema is converted to Pydantic and reproduced individually. A Python/JSX
UI may come later; that is the right place for automation, not the scripts.

`02` and `03` iterate their whole registry on every run — **there is no
per-file invocation.** Onboarding a schema means adding a registry entry, then
running the pair once and checking that only the new schema's block changed.

Three places to register a new schema:

1. **`01_reverse_engineer.py:34`** — `INTERFACE_FILE`, a single hardcoded path.
   `prepare_schemas()` handles exactly one interface schema. Only relevant when
   bootstrapping a schema's models for the first time; **`01` must not be run
   against an existing `models/`** (it deletes it — guarded since `ecc5a53`).
2. **`02_reproduce_schema.py:32`** — `EXPORT_TARGETS`:
   `(out_filename, module_stem, root_class_name)`. Use `None` for the root
   class to export all classes as `$defs` instead.
3. **`03_compare_schemas.py:29`** — `COMPARE_PAIRS`:
   `(bootstrap_path, reproduced_path)`.

**Target for each new schema: 0 `✗`, 0 `Δ`** — the standard
`ZWMS_INBOUND_DELIVERY_CREATE` now meets. Findings in an *existing* schema's
block after adding a new one mean the shared vocabulary was perturbed; that is
the signal worth chasing.

**Per-schema cost:** each interface needs its `$ref`s into `business-types` and
`envelope` to resolve, and its root class named. Enrichment burden is low —
`business_types_schema.py` carries 227 `Field()` constraints and is the shared
vocabulary; interface schemas mostly `$ref` into it.

**Watch for growth in section B.** The empty-string sentinel is per-occurrence
(~2 `✗` each) and is not fixable — it is correct behaviour. If the count climbs
into the hundreds, add a `--summary` flag to `03` reporting counts per
cause-category rather than per line, rather than trying to eliminate them.

Section D was the other per-occurrence category (~3 `✗` per optional array) and
was fixed in `a31037a` before onboarding began, so it will not accumulate.

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
