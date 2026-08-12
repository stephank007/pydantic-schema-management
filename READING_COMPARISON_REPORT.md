# How to Read `COMPARISON_REPORT.txt`

Guide to interpreting the output of `03_compare_schemas.py`
(`reproduced/COMPARISON_REPORT.txt`). Read this before spending time on the
report — most of its length is expected noise you can ignore.

---

## TL;DR — the 30-second version

1. **Scroll to the very bottom of the report.** The final line is your verdict:
   - `✓ All schemas pass structural comparison.` → clean, safe to hand off.
   - `✗ Structural differences found — review required before signing.` → at
     least one real delta needs attention.
2. Only **two** of the four sections matter: **MISSING FROM REPRODUCED** and
   **STRUCTURAL CHANGES**. The other two (**ADDED**, **EXPECTED ENRICHMENTS**)
   are expected Pydantic noise — document once, then ignore.
3. Cross-check every MISSING / STRUCTURAL item against the **known permanent
   diffs** (below). Anything already listed there = expected. Anything *not*
   listed = a genuine delta to fix in `models/` (then re-run `02` → `03`) or to
   get the firewall team to explicitly sign off.

---

## The four buckets

`03_compare_schemas.py` sorts every difference into four buckets. The verdict
is computed as `has_issues = (missing OR review)` — only these two fail the run.

| Bucket    | Report header                                  | Meaning                                                          | Action                    |
|-----------|------------------------------------------------|-----------------------------------------------------------------|---------------------------|
| `missing` | **MISSING FROM REPRODUCED — [REVIEW REQUIRED]**| In the signed bootstrap, *gone* from the Pydantic-derived output| ⚠️ **Must review**        |
| `review`  | **STRUCTURAL CHANGES — [REVIEW REQUIRED]**     | `type` / `pattern` / `required` / `enum` / `maxLength` … changed| ⚠️ **Must review**        |
| `added`   | **ADDED IN REPRODUCED — [EXPECTED]**           | Pydantic added it (e.g. `additionalProperties`, `type: object`) | ✅ Document, ignore        |
| `expected`| **EXPECTED ENRICHMENTS — [Document…]**         | titles, descriptions, `$ref → Optional`, ref rewrites, `$id`/`$comment` removed | ✅ Document, ignore |

The per-schema stats line, e.g.:

```
Missing: 6  |  Structural Δ: 0  |  Added: 6  |  Enrichments: 23
```

- `Structural Δ` = the `review` bucket. **This is the number that matters most.**
  `0` means nothing dangerous changed.
- `Added` + `Enrichments` = the expected-noise buckets. Usually large; ignore
  the volume.
- `Missing` = must be reconciled against the known permanent diffs.

---

## Known permanent diffs (expected — do NOT treat as problems)

These are structural deltas that appear on **every** run by design. The firewall
team accepts them once; they are not bugs.

1. **`unevaluatedProperties` → `additionalProperties`**
   Bootstrap uses draft-2020 `unevaluatedProperties`; Pydantic emits draft-2019
   `additionalProperties`. Shows up as `unevaluatedProperties` in **MISSING** and
   `additionalProperties` in **ADDED** — same fact, two buckets.

2. **Header moved from inline object → `$ref` into `$defs`**
   The envelope `Header` was inlined in bootstrap; Pydantic emits it as
   `"$ref": "#/$defs/Header"` plus a `$defs/Header` definition. The comparator
   does **not** follow `$ref`s, so it reports the inline
   `Header.properties` / `Header.required` / `Header.type` as **MISSING** even
   though they merely relocated. You'll see the matching
   `+ $root.properties.Header.$ref` and `+ $root.$defs.Header` in **ADDED**.

3. **`allOf` envelope inheritance flattened**
   `01_reverse_engineer.py` (`flatten_allof`) flattens `allOf` inheritance into
   explicit top-level properties. Absence of `allOf` is reported as expected.

> If a MISSING / STRUCTURAL line matches one of the three above → **expected,
> no action.** If it does not → **investigate.**

---

## Worked example — the envelope schema (from the last run)

```
Comparing: wms_envelope.schema.json
Missing: 6  |  Structural Δ: 0  |  Added: 6  |  Enrichments: 23
```

- **Structural Δ: 0** → nothing in the dangerous bucket. Good.
- **Added: 6 + Enrichments: 23** → all the long `~ … Optional (anyOf+null)`,
  `$comment removed`, `$id removed`, `external → local ref` lines. 100% expected
  Pydantic noise. This is the bulk of the report's length. Ignore it.
- **Missing: 6** → all six map onto the known permanent diffs:
  - `$root.unevaluatedProperties` (→ `additionalProperties`) — permanent diff #1
  - `$root.$defs.OpaqueDocHeader.unevaluatedProperties` — permanent diff #1
  - `$root.properties.Header.properties` — permanent diff #2 (Header → `$ref`)
  - `$root.properties.Header.required` — permanent diff #2
  - `$root.properties.Header.type` — permanent diff #2
  - `$root.properties.Header.unevaluatedProperties` — diffs #1 + #2

  **Verdict for envelope: all 6 "missing" are accounted for. Nothing new to sign off.**

---

## What actually needs your eyes

The report covers **three** schema pairs (see `COMPARE_PAIRS` in
`03_compare_schemas.py`):

1. `wms_envelope.schema.json`
2. `wms_business_types.schema.json`  ← **most likely to contain real deltas**
3. `ZWMS_INBOUND_DELIVERY_CREATE.schema.json`

**Focus on `business_types`.** There are 7 known model issues to fix in
`models/business_types_schema.py` (wrong `maxLength` values, missing types, lost
constraints). If those are still present, they surface under **STRUCTURAL
CHANGES** as lines like:

```
Δ $root.$defs.<Type>.maxLength: 'X' → 'Y'
Δ $root.$defs.<Type>.pattern:   '...' → '...'
```

— **not** under enrichments. Hunt the **STRUCTURAL CHANGES** section of the
`business_types` block for those. Each one is either:
- a genuine bug → fix in `models/business_types_schema.py`, then re-run
  `02_reproduce_schema.py` → `03_compare_schemas.py`, or
- an accepted permanent diff → document for the firewall team.

---

## Recurring gotcha — build host vs. runtime target

The pipeline is developed on macOS (Python 3.13) but runs on Windows (Python
3.10, Hebrew locale). Several failures came from that mismatch and are now
fixed, but keep the pattern in mind if new ones appear:

- **Encoding** — always read/write text with `encoding="utf-8"`. Windows
  defaults to the legacy codepage (cp1255 in a Hebrew locale) and chokes on
  non-ASCII bytes.
- **`enum.StrEnum`** — only exists on Python 3.11+. Codegen must target 3.10
  (`--target-python-version 3.10` in `01_reverse_engineer.py`); the generated
  `models/business_types_schema.py` carries a 3.10 `StrEnum` shim.
- **Offline wheels** — marker-guarded deps (`tomli` for `python_version < 3.11`,
  `colorama` for Windows) must be added explicitly; a macOS build host evaluates
  those markers as False and silently omits them.

---

## Workflow reminder

After editing `models/`:

```
python 02_reproduce_schema.py   # regenerate reproduced/ JSON schemas
python 03_compare_schemas.py    # regenerate COMPARISON_REPORT.txt
```

Then re-read the report bottom-up as described above.
