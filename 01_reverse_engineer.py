"""
01_reverse_engineer.py
─────────────────────
One-time setup: reverse-engineer the WMS JSON Schemas into Pydantic v2 models.

Reads from : bootstrap/   (all three schemas: envelope, business-types, interface)
Writes to  : models/      (Pydantic v2 source files)
             schemas/     (preprocessed local copies used by codegen)

Strategy:
  The interface schema uses allOf + cross-file $ref (envelope.schema.json).
  We preprocess:
    1. Extract all $defs from the real envelope → inject into each schema
    2. Rewrite all cross-schema $refs to local #/$defs/... references
    3. Flatten allOf envelope inheritance into explicit top-level properties
       using the real Header structure from the envelope
  Then run codegen on fully self-contained schemas.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT       = Path(__file__).parent
BOOTSTRAP  = ROOT / "bootstrap"
SCHEMAS    = ROOT / "schemas"
MODELS_OUT = ROOT / "models"

ENVELOPE_FILE  = BOOTSTRAP / "wms_envelope.schema.json"
BT_FILE        = BOOTSTRAP / "wms_business_types.schema.json"
INTERFACE_FILE = BOOTSTRAP / "ZWMS_INBOUND_DELIVERY_CREATE.schema.json"

ENVELOPE_URL = "https://example.org/wms/envelope.schema.json"
BT_URL       = "https://example.org/wms/business-types.schema.json"


def load_envelope_defs() -> tuple[dict, dict]:
    """
    Load the real envelope schema.
    Returns (defs_dict, header_property_dict).
    """
    envelope = json.loads(ENVELOPE_FILE.read_text(encoding="utf-8"))
    defs     = envelope.get("$defs", {})
    header   = envelope.get("properties", {}).get("Header", {})
    return defs, header


def rewrite_refs(obj: object, envelope_def_names: set[str]) -> object:
    """
    Recursively rewrite external $refs:
      envelope.schema.json#/$defs/X   → #/$defs/X  (inlined locally)
      envelope.schema.json (bare)     → __ENVELOPE_BARE_REF__ (for removal)
      business-types.schema.json#/... → ./business-types.schema.json#/...
    """
    if isinstance(obj, dict):
        result = {}
        for k, v in obj.items():
            if k == "$ref" and isinstance(v, str):
                if v.startswith(f"{ENVELOPE_URL}#/$defs/"):
                    prim = v.split("#/$defs/")[-1]
                    v = f"#/$defs/{prim}"
                elif v in (ENVELOPE_URL, ENVELOPE_URL + "#"):
                    v = "__ENVELOPE_BARE_REF__"
                elif v.startswith(BT_URL):
                    v = v.replace(BT_URL, "./business-types.schema.json")
            result[k] = rewrite_refs(v, envelope_def_names)
        return result
    if isinstance(obj, list):
        return [rewrite_refs(i, envelope_def_names) for i in obj]
    return obj


def inject_envelope_defs(schema: dict, envelope_defs: dict) -> dict:
    """Add all envelope $defs into the schema's $defs (don't overwrite existing)."""
    defs = schema.setdefault("$defs", {})
    for name, defn in envelope_defs.items():
        defs.setdefault(name, defn)
    return schema


def inject_real_header(schema: dict, envelope_header: dict) -> dict:
    """
    Inject the real envelope Header definition as a top-level property.
    Uses the actual Header structure from the envelope, with $refs rewritten
    to local #/$defs/... already handled by rewrite_refs.
    """
    props    = schema.setdefault("properties", {})
    required = schema.setdefault("required", [])
    props.setdefault("Header", envelope_header)
    if "Header" not in required:
        required.append("Header")
    return schema


def flatten_allof(schema: dict) -> dict:
    """
    Flatten allOf into top-level properties.
    Removes bare envelope ref items. Merges remaining property blocks.
    """
    if "allOf" not in schema:
        return schema

    top_props    = schema.setdefault("properties", {})
    top_required = schema.setdefault("required", [])

    for item in schema.get("allOf", []):
        if item.get("$ref") == "__ENVELOPE_BARE_REF__":
            continue
        for prop_name, prop_def in item.get("properties", {}).items():
            if prop_name not in top_props:
                top_props[prop_name] = prop_def
            else:
                top_props[prop_name] = {**top_props[prop_name], **prop_def}
        for req in item.get("required", []):
            if req not in top_required:
                top_required.append(req)

    schema.pop("allOf")
    return schema


def strip_meta(schema: dict) -> dict:
    for k in ("$schema", "$id", "$comment"):
        schema.pop(k, None)
    return schema


def prepare_schemas():
    if SCHEMAS.exists():
        shutil.rmtree(SCHEMAS)
    SCHEMAS.mkdir()

    # Load real envelope defs and header
    envelope_defs, envelope_header = load_envelope_defs()
    envelope_def_names = set(envelope_defs.keys())

    print(f"  Envelope defs loaded: {sorted(envelope_def_names)}")

    # ── Business types ─────────────────────────────────────────────────────
    bt = json.loads(BT_FILE.read_text(encoding="utf-8"))
    bt = rewrite_refs(bt, envelope_def_names)
    bt = inject_envelope_defs(bt, envelope_defs)
    bt = strip_meta(bt)
    (SCHEMAS / "business-types.schema.json").write_text(
        json.dumps(bt, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("  ✓ business-types.schema.json → schemas/")

    # ── Interface schema ───────────────────────────────────────────────────
    iface = json.loads(INTERFACE_FILE.read_text(encoding="utf-8"))
    iface = rewrite_refs(iface, envelope_def_names)
    iface = inject_envelope_defs(iface, envelope_defs)

    # Rewrite $refs inside the injected envelope_header too
    envelope_header_local = rewrite_refs(envelope_header, envelope_def_names)
    iface = inject_real_header(iface, envelope_header_local)
    iface = flatten_allof(iface)
    iface = strip_meta(iface)
    (SCHEMAS / "ZWMS_INBOUND_DELIVERY_CREATE.schema.json").write_text(
        json.dumps(iface, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("  ✓ ZWMS_INBOUND_DELIVERY_CREATE.schema.json → schemas/")

    # ── Envelope itself (for reference / future schemas) ───────────────────
    env = json.loads(ENVELOPE_FILE.read_text(encoding="utf-8"))
    env = strip_meta(env)
    (SCHEMAS / "envelope.schema.json").write_text(
        json.dumps(env, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("  ✓ envelope.schema.json → schemas/  (reference copy)")


def guard_existing_models():
    """Refuse to re-bootstrap over a hand-enriched models/ directory.

    This script regenerates models/ from scratch. That directory is generated
    *then hand-enriched* and is the project's source of truth, so an accidental
    rerun silently destroys every added Field() constraint and validator.
    """
    if not MODELS_OUT.exists() or "--force" in sys.argv:
        return

    print(
        f"  ✗ Refusing to run: {MODELS_OUT.name}/ already exists.\n"
        "\n"
        "    This script is a ONE-TIME bootstrap step. It deletes and regenerates\n"
        f"    {MODELS_OUT.name}/ from scratch, destroying every hand-added Field()\n"
        "    constraint, validator and description — the enrichment layer that is\n"
        "    the project's source of truth.\n"
        "\n"
        "    To reproduce schemas from the existing models, run:\n"
        "        python 02_reproduce_schema.py\n"
        "        python 03_compare_schemas.py\n"
        "\n"
        f"    If you really do intend to discard {MODELS_OUT.name}/ and re-bootstrap,\n"
        "    re-run with --force.",
        file=sys.stderr,
    )
    sys.exit(1)


def run_codegen():
    if MODELS_OUT.exists():
        shutil.rmtree(MODELS_OUT)
    MODELS_OUT.mkdir()

    cmd = [
        sys.executable, "-m", "datamodel_code_generator",
        "--input",             str(SCHEMAS),
        "--input-file-type",   "jsonschema",
        "--output",            str(MODELS_OUT),
        "--output-model-type", "pydantic_v2.BaseModel",
        "--reuse-model",
        "--use-schema-description",
        "--use-field-description",
        "--field-constraints",
        "--use-annotated",
        "--target-python-version", "3.10",
    ]

    print("  Running datamodel-codegen …")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print("  ✗ codegen FAILED:")
        print(result.stderr)
        sys.exit(1)

    if result.stdout.strip():
        print(result.stdout)

    generated = sorted(MODELS_OUT.glob("*.py"))
    print(f"  Generated {len(generated)} file(s):")
    for f in generated:
        n_classes = f.read_text(encoding="utf-8").count("\nclass ")
        print(f"    {f.name}  ({n_classes} model classes)")


def write_init():
    modules = sorted(f.stem for f in MODELS_OUT.glob("*.py") if f.stem != "__init__")
    lines = [
        "# Auto-generated — do not edit by hand.",
        "# After setup: edit individual model files to enrich with validators / Field().",
        "",
    ]
    for mod in modules:
        lines.append(f"from .{mod} import *  # noqa: F401, F403")
    (MODELS_OUT / "__init__.py").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("  ✓ models/__init__.py")


def validate_envelope():
    """Sanity check — make sure the real envelope looks right before proceeding."""
    if not ENVELOPE_FILE.exists():
        print("  ✗ bootstrap/envelope.schema.json not found")
        sys.exit(1)
    env = json.loads(ENVELOPE_FILE.read_text(encoding="utf-8"))
    defs = env.get("$defs", {})
    required_defs = {"SapDate", "PlantCode", "InterfaceName", "MessageId",
                     "ConsigneeCode", "SapTime", "OpaqueDocHeader"}
    missing = required_defs - set(defs.keys())
    if missing:
        print(f"  ⚠  Envelope missing expected $defs: {missing}")
    header_fields = set(env.get("properties", {}).get("Header", {})
                           .get("properties", {}).keys())
    print(f"  Envelope Header fields: {sorted(header_fields)}")
    print(f"  Envelope $defs        : {sorted(defs.keys())}")


def main():
    sep = "=" * 62
    print(sep)
    print("  WMS Reverse Engineer — one-time project setup")
    print("  Using real envelope.schema.json")
    print(sep)

    guard_existing_models()

    print("\n[0/4] Validating real envelope schema …")
    validate_envelope()

    print("\n[1/4] Preprocessing schemas …")
    prepare_schemas()

    print("\n[2/4] Running datamodel-codegen …")
    run_codegen()

    print("\n[3/4] Writing models/__init__.py …")
    write_init()

    print(f"\n{sep}")
    print("  Done. Next steps:")
    print("  1. Review models/ — start with business_types_schema.py")
    print("     Key corrections needed vs stub:")
    print("       PlantCode : now ^[0-9]{4}$ (numeric only — was alphanumeric)")
    print("       Header    : now 6 real fields (ID, PLANT, DATE, TIME, CONSIGNEE)")
    print("       Added     : InterfaceName, MessageId, ConsigneeCode, SapTime")
    print("  2. Add Field() constraints and validators")
    print("  3. Run 02_reproduce_schema.py")
    print("  4. Run 03_compare_schemas.py — send report to firewall team")
    print(sep)


if __name__ == "__main__":
    main()
