# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt   # installs pydantic + datamodel-code-generator
```

## Workflow — Three-Script Pipeline

This project reverse-engineers WMS JSON Schemas into Pydantic v2 models and compares them against signed originals for firewall team sign-off. Run scripts in order:

```bash
# Step 1 — One-time setup: preprocess schemas and generate Pydantic models
python 01_reverse_engineer.py

# Step 2 — Reproduce JSON schemas from the (enriched) Pydantic models
python 02_reproduce_schema.py

# Step 3 — Diff bootstrap vs reproduced schemas; generates COMPARISON_REPORT.txt
python 03_compare_schemas.py
```

## Architecture

### Directory roles

| Directory / File | Role |
|---|---|
| `bootstrap/` | **Source of truth** — original signed schemas from the firewall team. Never edit. |
| `schemas/` | **Generated** by `01_reverse_engineer.py` — preprocessed, self-contained copies used as codegen input. Gitignored / regenerated on demand. |
| `models/` | **Generated then enriched** — Pydantic v2 source files. `01_reverse_engineer.py` creates them; the dev team then manually adds `Field()` constraints and validators. |
| `reproduced/` | **Generated** by `02_reproduce_schema.py` — JSON schemas derived from the Pydantic models, to be sent to the firewall team for re-signing. |

### Schema preprocessing (`01_reverse_engineer.py`)

The bootstrap schemas use cross-file `$ref`s (e.g. `envelope.schema.json#/$defs/X`) and `allOf` inheritance. Before codegen can run, `prepare_schemas()`:
1. Rewrites all external envelope `$ref`s to local `#/$defs/...` references.
2. Injects all envelope `$defs` into each schema so they are self-contained.
3. Flattens `allOf` envelope inheritance into explicit top-level properties.

Codegen uses `datamodel-code-generator` targeting `pydantic_v2.BaseModel` with `--reuse-model` and `--field-constraints`.

### Schema comparison (`03_compare_schemas.py`)

Diffs are classified as:
- **`[EXPECTED]`** — Pydantic enrichment (`title`, `description`, `examples`). Document for firewall team.
- **`[REVIEW]`** — Structural changes (`type`, `pattern`, `required`, `properties`, etc.). Require explicit sign-off before firewall team re-signs.
- **`[MISSING]`** — Fields present in bootstrap but absent from reproduced. Always requires review.

### Adding a new WMS interface schema

1. Drop the new `.schema.json` into `bootstrap/`.
2. Add an entry to `EXPORT_TARGETS` in `02_reproduce_schema.py` with the output filename, module stem (snake_case of the filename), and root class name (or `None` for a combined `$defs` schema).
3. Re-run the full three-script pipeline.
