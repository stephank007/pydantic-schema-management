# How to Read `COMPARISON_REPORT.txt`

Guide to interpreting the output of `03_compare_schemas.py`
(`reproduced/COMPARISON_REPORT.txt`). Read this before spending time on the
report — most of its ~1000 lines are expected noise.

**Current baseline: 18 `✗` and 2 `Δ`, and every one of them is accounted for
below. No outstanding model defects.**

---

## TL;DR — the 30-second version

1. Only two sections matter: **MISSING FROM REPRODUCED** (`✗`) and
   **STRUCTURAL CHANGES** (`Δ`). **ADDED** and **EXPECTED ENRICHMENTS** are
   Pydantic noise — that is the bulk of the file.
2. Check the three per-schema stats lines against the expected baseline:

   | Schema | Missing | Structural Δ |
   |---|---|---|
   | `wms_envelope` | 6 | 0 |
   | `wms_business_types` | 12 | 2 |
   | `ZWMS_INBOUND_DELIVERY_CREATE` | 0 | 0 |

3. If the numbers match, **nothing needs action** — every finding is a known
   accepted diff or a comparator limitation, both catalogued below.
4. If a number is *higher*, something new appeared. Diff the `✗`/`Δ` lines
   against the catalogue below and investigate anything unlisted.

> The report always ends with `✗ Structural differences found — review required
> before signing.` **This is not a failure signal.** It fires whenever `missing`
> or `review` is non-empty, which includes all the accepted diffs. Judge by the
> catalogue, not by that line.

---

## The four buckets

`03_compare_schemas.py` sorts every difference into four buckets. The verdict is
`has_issues = (missing OR review)` — only these two can fail the run.

| Bucket | Report header | Meaning | Action |
|---|---|---|---|
| `missing` | **MISSING FROM REPRODUCED — [REVIEW REQUIRED]** | In signed bootstrap, absent from reproduced | ⚠️ Check against catalogue |
| `review` | **STRUCTURAL CHANGES — [REVIEW REQUIRED]** | `type` / `pattern` / `maxLength` / … changed | ⚠️ Check against catalogue |
| `added` | **ADDED IN REPRODUCED — [EXPECTED]** | Pydantic added it | ✅ Ignore |
| `expected` | **EXPECTED ENRICHMENTS — [Document…]** | titles, descriptions, `$ref → Optional`, ref rewrites | ✅ Ignore |

`Added` and `Enrichments` counts differ between machines (macOS/py3.13/pydantic
2.12.5 vs Windows/py3.10/pydantic 2.13.4) because those versions emit slightly
different metadata. **`Missing` and `Structural Δ` are identical across both.**
Only compare those two.

---

## Catalogue of the 24 accepted findings

### A. Envelope — 6 `✗` — accepted permanent diffs

```
✗ $root.unevaluatedProperties                        (was: false)
✗ $root.$defs.OpaqueDocHeader.unevaluatedProperties  (was: true)
✗ $root.properties.Header.properties
✗ $root.properties.Header.required
✗ $root.properties.Header.type                       (was: "object")
✗ $root.properties.Header.unevaluatedProperties      (was: false)
```

Two causes, both signed off once by the firewall team:

1. **`unevaluatedProperties` → `additionalProperties`.** Bootstrap uses
   draft-2020 `unevaluatedProperties`; Pydantic emits draft-2019
   `additionalProperties`. Same intent, different keyword. Appears in MISSING
   *and* in ADDED — one fact, two buckets.
2. **`Header` inlined → `$defs` + `$ref`.** Bootstrap inlines the Header object;
   Pydantic emits `"$ref": "#/$defs/Header"` plus a `$defs/Header`. The
   comparator does not follow `$ref`s, so it reports the inline members as
   missing even though they only relocated. The matching
   `+ $root.properties.Header.$ref` and `+ $root.$defs.Header` are in ADDED.

### B. The empty-string sentinel — 10 `✗` — correct by design

```
✗ …BatchSplit.properties.SHELF_LIFE_EXP_DATE.anyOf[0].maxLength   (was: 0)
✗ …BatchSplit.properties.SHELF_LIFE_EXP_DATE.anyOf[0].type        (was: "string")
✗ …DocItem.properties.TRANSIT_DOCKING_PLANT.anyOf[0].maxLength    (was: 0)
✗ …DocItem.properties.TRANSIT_DOCKING_PLANT.anyOf[0].type         (was: "string")
✗ …HuItem.properties.SERIAL_NUMBER.anyOf[0].maxLength             (was: 0)
✗ …HuItem.properties.SERIAL_NUMBER.anyOf[0].type                  (was: "string")
✗ …InspectionCharacteristic.properties.NUMERIC_VALUE.anyOf[0].maxLength (was: 0)
✗ …InspectionCharacteristic.properties.NUMERIC_VALUE.anyOf[0].type      (was: "string")
✗ …InspectionCharacteristic.properties.NUMERIC_VALUE.anyOf[1].pattern
✗ …InspectionCharacteristic.properties.NUMERIC_VALUE.anyOf[1].type      (was: "string")
```

`maxLength: 0` is **deliberate** in the bootstrap — the empty-string arm of an
`anyOf` meaning *"field present but blank"*:

```jsonc
"TRANSIT_DOCKING_PLANT": {
  "anyOf": [ {"type": "string", "maxLength": 0},      // blank
             {"$ref": ".../PlantCode"} ]              // or a real plant code
}
```

Codegen deduplicates that shared blank arm into a single
`SERIALNUMBER(RootModel[str])` with `max_length=0`, which
`SHELFLIFEEXPDATE`, `NUMERICVALUE` and `TRANSITDOCKINGPLANT` inherit. Only one
`max_length=0` exists in the whole models file.

> 🚫 **Never "fix" a `maxLength: 0`.** Removing it breaks the "present but
> blank" contract and will reject valid production messages.

### C. `_reconcile_def_names()` collisions — 2 `✗` + 2 `Δ` — comparator artifact

```
✗ $root.$defs.ISSUE_STLOC
✗ $root.$defs.MATERIAL_TYPE
Δ $root.$defs.SERIAL_NUMBER.maxLength:          '18' → '0'
Δ $root.$defs.TRANSIT_DOCKING_PLANT.maxLength:  '4'  → '0'
```

Codegen strips underscores from `$defs` names, so distinct bootstrap types
collide and get numeric suffixes:

| Bootstrap | Model class | Content |
|---|---|---|
| `ISSUE_ST_LOC` | `ISSUESTLOC` | maxLength 4, "אתר אחסון מנפק-שורה" |
| `ISSUE_STLOC` | `ISSUESTLOC1` | no maxLength, "אתר אחסון" |
| `MATERIAL_TYPE` | `MATERIALTYPE` | "סוג חומר מהקט\"מ" |
| `MATERIALTYPE` | `MATERIALTYPE1` | "סוג הפריט צהלי או ייצרן" |

`_reconcile_def_names()` in `03_compare_schemas.py` maps normalised names back
to bootstrap names, but its `norm_to_orig` dict lets the last colliding name win.
It then pairs the wrong defs, producing phantom "missing" and "changed" lines.

**All four types exist in the models with correct constraints and descriptions —
verified individually against bootstrap.** The same mispairing produces the two
`Δ` lines: real `SERIAL_NUMBER` (maxLength 18) and `TRANSIT_DOCKING_PLANT`
(maxLength 4) get compared against the shared blank-arm class from section B.

*Not fixed:* an attempt to pair by constraint shape made the count worse
(15 → 16). `MATERIALTYPE` and `MATERIALTYPE1` are both a bare
`{"type": "string"}` in the reproduced schema — descriptions become Python
docstrings, not schema fields — so they are genuinely indistinguishable to any
automated matcher.

### D. Optional arrays — **fixed, no longer reported**

Previously 6 `✗` (three each on `DocItem.SERIAL_NUMBERS` and
`InboundDocItem.SERIAL_NUMBERS`). Kept here because the shape recurs on every
optional array, and knowing why it *used* to be reported is useful when
onboarding a new schema.

An optional array nests its constraints one level down:

```jsonc
"SERIAL_NUMBERS": {
  "anyOf": [
    { "items": {"$ref": "#/$defs/SerialNumber"},
      "maxItems": 999,
      "type": "array" },          // ← constraints live here
    { "type": "null" }
  ],
  "default": null,
  "uniqueItems": true             // ← sibling, via json_schema_extra
}
```

`_is_optional_expansion()` compared bootstrap against `anyOf[0]` only, so
`uniqueItems` — emitted as a *sibling* of `anyOf` — had no counterpart and the
match failed, causing the three nested keys to be reported as missing.

It now folds those siblings into the non-null branch before comparing. Merging
rather than ignoring keeps the check honest: a constraint genuinely absent from
both places still fails. Verified — a dropped `uniqueItems` and a changed
`maxItems` are both still reported.

Verify any optional array with:

```bash
python3 -c "import json; d=json.load(open('reproduced/business-types.schema.json'));
print(json.dumps(d['\$defs']['DocItem']['properties']['SERIAL_NUMBERS'], indent=2))"
```

---

## If a count goes UP

Something new. Do this, in order:

1. **Regenerate before reasoning.** Run `02` then `03`. A stale `reproduced/`
   has caused wrong conclusions more than once — never triage a report you did
   not just generate.
2. **Diff the `✗`/`Δ` lines against the catalogue above.** Anything listed is
   accounted for; anything else is new.
3. **Read `02`'s console output for warnings.** `UnsupportedFieldAttributeWarning`
   means a `Field()` is being silently ignored — see the trap below.
4. **Check `models/` was not regenerated.** `grep -c 'Field(' models/business_types_schema.py`
   must be ≥ 200 (currently 227). A much lower number means `01_reverse_engineer.py`
   wiped the enrichment layer.

---

## Traps that have actually bitten this project

**`Field()` on a union member is silently ignored.**

```python
# BROKEN — Field() applies to one member of the union, pydantic ignores it
BOL_1: Annotated[business_types_schema.BOL, Field(alias='BOL')] | None = None

# CORRECT — union inside Annotated, Field() applies to the whole field
BOL_1: Annotated[business_types_schema.BOL | None, Field(alias='BOL')] = None
```

The broken form emitted `BOL_1`, `BATCH_1`, `LOT_1`, `MILSTRIP_1`, `RECEIPT_1`,
`SERIAL_1`, `SPED_1` into the schema instead of the signed names — seven wrong
property names in a file destined for the firewall team. Pydantic warned about
it on every run for months and the warning was read as noise. **Treat
`UnsupportedFieldAttributeWarning` as an error.**

**`01_reverse_engineer.py` deletes `models/`.** It is a one-time bootstrap step;
`models/` is generated *then hand-enriched* and is the source of truth. Guarded
since `ecc5a53` (requires `--force`), but never run it to "start fresh".

**`uniqueItems` has no Pydantic equivalent.** It needs
`json_schema_extra={"uniqueItems": True}` to appear in the schema *and* an
`AfterValidator` to actually be enforced. Declaring it without the validator
gives a schema that claims a constraint the model does not apply.

**Build host vs. runtime target.** Developed on macOS/py3.13, runs on
Windows/py3.10 in a Hebrew locale:
- Always pass `encoding="utf-8"` — Windows defaults to cp1255 and chokes on the
  Hebrew descriptions.
- `enum.StrEnum` is 3.11+; the models carry a 3.10 shim, and `02` skips
  memberless enum bases so that shim does not leak into `$defs` as a phantom
  369th type.
- Offline wheels: marker-guarded deps (`tomli`, `colorama`) must be fetched
  explicitly — a macOS build host evaluates those markers as False.

---

## Workflow

After editing `models/`:

```bash
python 02_reproduce_schema.py   # regenerate reproduced/*.schema.json
python 03_compare_schemas.py    # regenerate COMPARISON_REPORT.txt
python validate_messages.py     # confirm all three layers still agree
```

Never run `01_reverse_engineer.py`.

---

## Handing off to the firewall team

The deliverable is the three files in `reproduced/`, not this report. As of
`4d0084b` they are faithful to bootstrap: property names match, constraints are
present, and `02` emits no warnings.

Send with them:

- **Section A** — the 6 envelope diffs, already accepted; re-confirm only.
- **Sections B and C** — 12 `✗` plus 2 `Δ` that are by-design sentinels or
  comparator artifacts, not schema changes. Each is verifiable against
  `reproduced/` with the commands above.

Breakdown of the 18 `✗`: A=6, B=10, C=2. Plus the 2 `Δ` in section C.
`ZWMS_INBOUND_DELIVERY_CREATE` is now completely clean (0 `✗`, 0 `Δ`).

The report's trailing `✗ Structural differences found` line will still be
present. Explain it up front, or it will be read as a failed check.
