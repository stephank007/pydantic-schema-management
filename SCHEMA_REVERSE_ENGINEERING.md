# Multi-Schema Reverse Engineering — One-Time Setup Guide

## Context

This document covers the one-time process of reverse engineering an existing set of
JSON Schemas into Pydantic models, as the entry point into the proxy-first signed architecture.

**This process runs once at project setup. After completion, Pydantic models become
the source of truth and this document is archived.**

---

## Starting Structure

```
schemas/
  common_business_types.json     ← shared types, referenced by all interfaces
  interface_01.json              → $ref → common_business_types.json
  interface_02.json              → $ref → common_business_types.json
  ...
  interface_20.json              → $ref → common_business_types.json
```

---

## Target Pydantic Structure

```
models/
  __init__.py
  common.py          ← BusinessType, SharedEnum, all common types (generated once)
  interface_01.py    → from .common import ...
  interface_02.py    → from .common import ...
  ...
  interface_20.py    → from .common import ...
```

The common types are generated **once** and imported — never duplicated across interface files.
This mirrors the `$ref` relationship in the original JSON Schemas.

---

## Prerequisites

```bash
pip install datamodel-code-generator
```

---

## The One-Time Generation Command

```bash
datamodel-codegen \
  --input ./schemas/ \
  --input-file-type jsonschema \
  --output ./models/ \
  --reuse-model \
  --use-schema-description \
  --output-model-type pydantic_v2.BaseModel
```

### Key Flags Explained

| Flag | Purpose |
|---|---|
| `--input ./schemas/` | Points at the folder — processes all 21 files together, resolves `$ref` across files |
| `--reuse-model` | Critical: generates common types once in `common.py`, imports them in interface files — never duplicates |
| `--use-schema-description` | Carries any `description` fields from JSON Schema into Pydantic `Field(description=...)` |
| `--output-model-type pydantic_v2.BaseModel` | Targets Pydantic v2 syntax |

---

## After Generation — Review Process

Do **not** treat generated files as final. Run one deliberate review pass in this order:

### Step 1 — Review `common.py` First (Highest Priority)

Every type here is used by all 20 interfaces. Enrichment here multiplies across the system.

Check for and add:
- `Field()` constraints (`min_length`, `ge`, `le`, `pattern`, etc.)
- Validators (`@field_validator`) for business rules
- Meaningful descriptions on every field
- Correct `Optional` vs required designation
- Enums that should be `Literal` types or vice versa

Get team sign-off on `common.py` before touching the interface files.

### Step 2 — Review Each Interface File

Lighter pass. For each `interface_XX.py`:

- Confirm `$ref` resolved to an **import from `common.py`** — not inlined/duplicated
- Add any interface-specific validators
- Check optional fields are correctly designated
- Verify field names match your naming conventions

### Step 3 — What Won't Come Back from JSON Schema

These must be re-added manually based on team knowledge:

- Why a field is optional (business reason)
- Valid value ranges and what they mean
- Mutually exclusive field combinations
- Fields that are required together (co-dependent fields)
- Any business rule that was enforced by application code, not schema

---

## Recommended Rollout Order

Don't review all 20 interfaces at once:

```
1. Generate everything (one command)
2. Review and enrich common.py → team sign-off
3. Interface files in priority order:
   - Active development interfaces first
   - High-traffic production interfaces next
   - Lower-priority / legacy interfaces last
4. For each interface: write dual validation tests before marking done
```

---

## Preserving the Bootstrap Audit Trail

Commit the original JSON Schemas alongside the generated models:

```
project/
  bootstrap/
    original_schemas/
      common_business_types.json   ← original, as received / as was
      interface_01.json
      ...
      interface_20.json
    README.md                      ← date of reverse engineering, who approved, signing reference
  models/
    common.py
    interface_01.py
    ...
```

The `bootstrap/` folder is **read-only after setup** — it is the traceable record of
what the starting point was, who signed the original schemas, and when the migration occurred.

---

## Verifying the Output

After generation and review, verify the round-trip is clean:

```python
import json
from models.common import *
from models.interface_01 import Interface01Request

# Regenerate JSON Schema from the new Pydantic model
regenerated = Interface01Request.model_json_schema()

# Compare against original (should be structurally equivalent)
original = json.loads(open("bootstrap/original_schemas/interface_01.json").read())

# Any structural differences are intentional enrichments — document them
```

Differences between the original and regenerated schema are expected and acceptable —
they represent business knowledge re-added by the team. Document each difference in
the `bootstrap/README.md` so the firewall team understands what changed and why
before they sign the new Pydantic-derived schemas.

---

## Handoff to Normal Architecture Flow

Once all 20 interfaces are reviewed and tests pass, the architecture runs normally:

```
Pydantic models (source of truth, dev team owns)
        ↓
model.model_json_schema()  →  JSON Schema diff (CI/CD)
        ↓
Firewall team reviews → signs
        ↓
Production: dual validation (firewall + Pydantic)
```

This document is now archived. The Skill file governs all future development.

---

*One-time setup. Executed once. Pydantic takes over from here.*
