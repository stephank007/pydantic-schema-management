"""
validate_messages.py
────────────────────
Validate WMS messages against three layers:

  1. Bootstrap JSON Schema  — original signed schema (via preprocessed self-contained copy)
  2. Pydantic model         — source of truth going forward
  3. Reproduced JSON Schema — Pydantic-derived schema sent to firewall team

Usage:
    python validate_messages.py

Note: Header model incompleteness (Track 1 fix pending) is suppressed so that
      DOC_HEADER / payload errors are clearly visible.
"""

import json
import sys
from pathlib import Path

import jsonschema
from jsonschema import Draft202012Validator
from pydantic import ValidationError

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

# ── Schemas ────────────────────────────────────────────────────────────────────
# Use the preprocessed (self-contained) schema for bootstrap-equivalent validation;
# the original bootstrap uses external $refs that require a network resolver.
BOOTSTRAP_SCHEMA  = ROOT / "schemas"    / "ZWMS_INBOUND_DELIVERY_CREATE.schema.json"
REPRODUCED_SCHEMA = ROOT / "reproduced" / "ZWMS_INBOUND_DELIVERY_CREATE.schema.json"

# ── Messages ───────────────────────────────────────────────────────────────────
GOOD_MESSAGE = {
    "Header": {
        "INTERFACE_NAME": "ZWMS_INBOUND_DELIVERY_CREATE",
        "ID": "0000002243643980",
        "PLANT": "6300",
        "DATE": "20240918",
        "TIME": "080000",
        "CONSIGNEE": "ATAL",
    },
    "DOC_HEADER": {
        "REC_DOC": "4500012345",
        "WMS_ORD_TP": "101",
        "SUP_PRTNR": "0000001001",
        "RECEIVING_PLANT": "6300",
        "DELIVERY_DATE": "20240918",
        "DOC_ITEM": [
            {
                "MATERIAL": "319657933",
                "QUANTITY": "30.000",
                "RECEIVING_STORAGE_LOCATION": "3000",
                "BATCH": "B24-A",
                "DELIVERY_DATE": "20240918",
            }
        ],
    },
}

BAD_MESSAGE = {
    "Header": {
        "INTERFACE_NAME": "ZWMS_INBOUND_DELIVERY_CREATE",
        "ID": "0000002243643980",
        "PLANT": "6300",
        "DATE": "20240918",
        "TIME": "080000",
        "CONSIGNEE": "ATAL",
    },
    "DOC_HEADER": {
        "REC_DOC": "4500012345",
        "WMS_ORD_TP": "101",
        "SUP_PRTNR": "0000001001",
        "RECEIVING_PLANT": "6300",
        "DELIVERY_DATE": "20240918",
        "DOC_ITEM": [
            {
                "MATERIAL": "319657933",
                "QUANTITY": "30",          # ← invalid: SapQuantity requires ^[0-9]+\.[0-9]{3}$
                "RECEIVING_STORAGE_LOCATION": "3000",
                "BATCH": "B24-A",
                "DELIVERY_DATE": "20240918",
            }
        ],
    },
}


# ── Validation helpers ─────────────────────────────────────────────────────────

def _load_schema(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _build_registry(schema_dir: Path):
    """
    Build a jsonschema Registry from all *.schema.json files in a directory.
    Maps both the filename (e.g. './business-types.schema.json') and the
    file:// URI so relative $refs resolve correctly.
    """
    from referencing import Registry
    from referencing.jsonschema import DRAFT202012
    resources = []
    for f in schema_dir.glob("*.schema.json"):
        schema = _load_schema(f)
        resource = DRAFT202012.create_resource(schema)
        uri = f"file://{f.resolve()}"
        resources.append((uri, resource))
        resources.append((f"./{f.name}", resource))
        resources.append((f.name, resource))
    return Registry().with_resources(resources)


def _is_header_extra_error(error) -> bool:
    """Suppress known Header incompleteness errors (Track 1 fix pending)."""
    path = list(error.absolute_path)
    return (
        len(path) >= 1 and path[0] == "Header"
        and ("Unevaluated properties" in error.message
             or "Additional properties" in error.message)
    )


def _flatten_errors(validator_errors) -> list:
    """
    Flatten jsonschema errors, drilling into anyOf/oneOf branches to surface
    the most specific sub-errors rather than the top-level 'not valid under any'
    message.
    """
    result = []
    for error in validator_errors:
        if error.validator in ("anyOf", "oneOf") and error.context:
            # Pick the branch with the fewest errors (closest match)
            best = min(error.context, key=lambda e: len(list(e.context)) + 1)
            result.extend(_flatten_errors([best]))
        else:
            result.append(error)
    return result


def validate_jsonschema(message: dict, schema_path: Path) -> tuple[bool, list[str]]:
    schema    = _load_schema(schema_path)
    registry  = _build_registry(schema_path.parent)
    validator = Draft202012Validator(schema, registry=registry)
    raw       = list(validator.iter_errors(message))
    errors    = sorted(_flatten_errors(raw), key=lambda e: list(e.absolute_path))
    errors    = [e for e in errors if not _is_header_extra_error(e)]
    if not errors:
        return True, []
    return False, [
        f"  {'→'.join(str(p) for p in e.absolute_path) or '$root'}: {e.message}"
        for e in errors
    ]


def validate_pydantic(message: dict) -> tuple[bool, list[str]]:
    from models.ZWMS_INBOUND_DELIVERY_CREATE_schema import WmsinterfaceZwmsInboundDeliveryCreate
    try:
        WmsinterfaceZwmsInboundDeliveryCreate.model_validate(message)
        return True, []
    except ValidationError as e:
        errors = []
        for err in e.errors():
            loc = " → ".join(str(p) for p in err["loc"])
            # Suppress known Header incompleteness (Track 1 fix pending)
            if err["loc"][0] == "Header" and err["type"] == "extra_forbidden":
                continue
            errors.append(f"  {loc}: {err['msg']}")
        return len(errors) == 0, errors


# ── Reporter ───────────────────────────────────────────────────────────────────

def report(label: str, message: dict) -> None:
    sep = "═" * 62
    print(f"\n{sep}")
    print(f"  {label}")
    print(sep)

    layers = [
        ("Bootstrap JSON Schema (preprocessed)", lambda: validate_jsonschema(message, BOOTSTRAP_SCHEMA)),
        ("Pydantic model",                        lambda: validate_pydantic(message)),
        ("Reproduced JSON Schema",                lambda: validate_jsonschema(message, REPRODUCED_SCHEMA)),
    ]

    for name, validate_fn in layers:
        passed, errors = validate_fn()
        icon = "✓ PASS" if passed else "✗ FAIL"
        print(f"\n  [{icon}]  {name}")
        for err in errors:
            print(err)


# ── Main ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    report("GOOD MESSAGE", GOOD_MESSAGE)
    report("BAD MESSAGE  (QUANTITY: '30' — missing decimal places)", BAD_MESSAGE)
    print()
