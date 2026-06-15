"""Key Export — Transform consolidated Terraform output JSON into an Excel key sheet.

Public interface:
    generate_key_excel(terraform_outputs: dict, output_path: str) -> Path

CLI:
    python -m src.auth.key_export --input consolidated.json --output keys.xlsx

No Azure SDK imports — pure data transformation.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import openpyxl

COLUMNS = [
    "Team",
    "Subscription ID",
    "Resource Group",
    "Region",
    "Foundry Endpoint",
    "API Key (Key1)",
    "API Key (Key2)",
    "Model Deployments",
]


def generate_key_excel(terraform_outputs: dict, output_path: str) -> Path:
    """Transform consolidated Terraform output into an Excel key sheet.

    Args:
        terraform_outputs: Dict keyed by team name.  Each value must contain
            ``subscription_id``, ``resource_group``, and ``regions`` (a map of
            region name → {endpoint, key1, key2, model_deployments}).
        output_path: File path for the resulting ``.xlsx`` file.
            If the file already exists, new rows are **appended**.

    Returns:
        Path to the created/updated Excel file.
    """
    path = Path(output_path)

    if path.exists():
        wb = openpyxl.load_workbook(path)
        ws = wb.active
    else:
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.append(COLUMNS)

    for team_name in sorted(terraform_outputs):
        team = terraform_outputs[team_name]
        subscription_id = team["subscription_id"]
        resource_group = team["resource_group"]

        for region_name in sorted(team.get("regions", {})):
            region = team["regions"][region_name]
            ws.append([
                team_name,
                subscription_id,
                resource_group,
                region_name,
                region["endpoint"],
                region["key1"],
                region["key2"],
                ", ".join(region.get("model_deployments", [])),
            ])

    wb.save(path)
    return path


def _parse_terraform_json(raw: dict) -> dict:
    """Normalise raw ``terraform output -json`` into the shape expected by
    :func:`generate_key_excel`.

    Supports two input layouts:

    1. **Single-team** — top-level keys are ``team_name`` and ``team_info``
       (each wrapped in ``{"value": ...}`` by Terraform).
    2. **Multi-team consolidated** — top-level keys are team names, each
       containing ``team_name`` + ``team_info`` sub-keys.
    """
    # Single-team format
    if "team_name" in raw and "team_info" in raw:
        name = raw["team_name"]
        info = raw["team_info"]
        name = name["value"] if isinstance(name, dict) and "value" in name else name
        info = info["value"] if isinstance(info, dict) and "value" in info else info
        return {name: info}

    # Multi-team / already-clean format
    result: dict = {}
    for key, val in raw.items():
        if not isinstance(val, dict):
            continue
        if "team_name" in val and "team_info" in val:
            n = val["team_name"]
            i = val["team_info"]
            n = n["value"] if isinstance(n, dict) and "value" in n else n
            i = i["value"] if isinstance(i, dict) and "value" in i else i
            result[n] = i
        else:
            result[key] = val
    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export Terraform outputs to an Excel key sheet",
    )
    parser.add_argument(
        "--input",
        type=str,
        default=None,
        help="Path to terraform output JSON file (reads stdin if omitted)",
    )
    parser.add_argument(
        "--output",
        type=str,
        required=True,
        help="Path to output Excel file (.xlsx)",
    )
    args = parser.parse_args()

    if args.input:
        with open(args.input) as fh:
            raw = json.load(fh)
    else:
        raw = json.load(sys.stdin)

    terraform_outputs = _parse_terraform_json(raw)
    result = generate_key_excel(terraform_outputs, args.output)
    print(f"Key Excel exported to: {result}")


if __name__ == "__main__":
    main()
