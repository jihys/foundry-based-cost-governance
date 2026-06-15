#!/usr/bin/env bash
# deploy_all.sh — Multi-team Terraform deployment orchestrator
#
# Usage:
#   ./scripts/deploy_all.sh              # Deploy all teams
#   ./scripts/deploy_all.sh --plan-only  # Dry-run (terraform plan)
#   ./scripts/deploy_all.sh --destroy    # Tear down all teams
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFRA_DIR="$REPO_ROOT/infra"
ENVS_DIR="$INFRA_DIR/envs"
OUTPUT_DIR="$REPO_ROOT/output"
CONSOLIDATED_JSON="$OUTPUT_DIR/consolidated_outputs.json"
EXCEL_OUTPUT="$OUTPUT_DIR/team_keys.xlsx"

# --- Flags -------------------------------------------------------------------
PLAN_ONLY=false
DESTROY=false

for arg in "$@"; do
  case "$arg" in
    --plan-only) PLAN_ONLY=true ;;
    --destroy)   DESTROY=true ;;
    -h|--help)
      sed -n '3,7p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $arg" >&2
      echo "Usage: $0 [--plan-only | --destroy]" >&2
      exit 1
      ;;
  esac
done

if $PLAN_ONLY && $DESTROY; then
  echo "ERROR: --plan-only and --destroy are mutually exclusive." >&2
  exit 1
fi

# --- Validate required env vars ----------------------------------------------
for var in ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_TENANT_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Required environment variable $var is not set." >&2
    exit 1
  fi
done

# --- Cleanup trap -------------------------------------------------------------
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "" >&2
    echo "ERROR: Script failed with exit code $exit_code." >&2
  fi
}
trap cleanup EXIT

# --- Discover teams from tfvars files ----------------------------------------
TEAMS=()
for tfvars in "$ENVS_DIR"/*.tfvars; do
  [[ -e "$tfvars" ]] || continue
  TEAMS+=("$(basename "$tfvars" .tfvars)")
done

if [[ ${#TEAMS[@]} -eq 0 ]]; then
  echo "ERROR: No .tfvars files found in $ENVS_DIR" >&2
  exit 1
fi

echo "=== Teams discovered: ${TEAMS[*]} ==="
echo ""

# --- Helper: extract subscription_id from a tfvars file ----------------------
get_subscription_id() {
  grep '^subscription_id' "$1" | sed 's/.*= *"\(.*\)"/\1/'
}

# --- Initialize Terraform ----------------------------------------------------
cd "$INFRA_DIR"
echo "=== Initializing Terraform ==="
terraform init -input=false
echo ""

# --- Deploy / Plan / Destroy each team ---------------------------------------
for team in "${TEAMS[@]}"; do
  tfvars_file="$ENVS_DIR/${team}.tfvars"
  sub_id="$(get_subscription_id "$tfvars_file")"

  echo "=== [$team] Subscription: $sub_id ==="
  export ARM_SUBSCRIPTION_ID="$sub_id"

  terraform workspace select -or-create "$team"

  if $DESTROY; then
    echo "--- [$team] Destroying resources..."
    terraform destroy -var-file="envs/${team}.tfvars" -auto-approve
    echo "--- [$team] Destroy complete."
  elif $PLAN_ONLY; then
    echo "--- [$team] Planning (dry run)..."
    terraform plan -var-file="envs/${team}.tfvars"
    echo "--- [$team] Plan complete."
  else
    echo "--- [$team] Applying..."
    terraform apply -var-file="envs/${team}.tfvars" -auto-approve
    echo "--- [$team] Apply complete."
  fi
  echo ""
done

# --- Skip output collection for plan-only / destroy --------------------------
if $PLAN_ONLY; then
  echo "=== Plan-only mode — skipping output collection ==="
  exit 0
fi

if $DESTROY; then
  echo "=== Destroy mode — skipping output collection ==="
  exit 0
fi

# --- Collect outputs from all workspaces -------------------------------------
echo "=== Collecting Terraform outputs ==="
mkdir -p "$OUTPUT_DIR"

consolidated="{}"
for team in "${TEAMS[@]}"; do
  tfvars_file="$ENVS_DIR/${team}.tfvars"
  sub_id="$(get_subscription_id "$tfvars_file")"
  export ARM_SUBSCRIPTION_ID="$sub_id"

  terraform workspace select "$team"
  team_output="$(terraform output -json)"
  consolidated="$(echo "$consolidated" | jq \
    --arg team "$team" \
    --argjson output "$team_output" \
    '. + {($team): $output}')"
done

echo "$consolidated" > "$CONSOLIDATED_JSON"
echo "Consolidated outputs saved to: $CONSOLIDATED_JSON"

# --- Generate Excel key sheet ------------------------------------------------
echo ""
echo "=== Generating Key Excel ==="
cd "$REPO_ROOT"
python -m src.auth.key_export --input "$CONSOLIDATED_JSON" --output "$EXCEL_OUTPUT"

echo ""
echo "=== Deployment complete ==="
echo "Excel output: $EXCEL_OUTPUT"
