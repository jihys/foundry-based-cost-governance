# Step-by-Step Deployment Guide

This document walks you through deploying the Azure AI Foundry Cost Governance system **from scratch**.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Clone & Environment Setup](#2-clone--environment-setup)
3. [Configure Team tfvars](#3-configure-team-tfvars)
4. [Initialize & Deploy with Terraform](#4-initialize--deploy-with-terraform)
5. [Generate Excel Key File](#5-generate-excel-key-file)
6. [Verify API Keys](#6-verify-api-keys)
7. [Check Cost Dashboard](#7-check-cost-dashboard)
8. [Deploy Unified Dashboard (Optional)](#8-deploy-unified-dashboard-optional)
9. [Clean Up Resources](#9-clean-up-resources)

---

## 1. Prerequisites

### Required Tools

| Tool | Minimum Version | Verify |
|------|----------------|--------|
| Terraform | 1.5+ | `terraform version` |
| Python | 3.10+ | `python3 --version` |
| Azure CLI | 2.50+ | `az version` |
| jq | 1.6+ | `jq --version` |

### Azure Resources

- **Azure Subscriptions**: One per team (e.g., catalog team, image team → minimum 2 subscriptions)
- **Authentication**: Either a Service Principal or `az login`
  - Service Principal: Must have **Contributor** role on all target subscriptions
  - az login: The account must have access to all target subscriptions
- `Microsoft.CognitiveServices` resource provider must be registered on each subscription

### Register Resource Providers

```bash
# Run for each subscription
az provider register -n Microsoft.CognitiveServices --subscription "<SUBSCRIPTION_ID>"
az provider register -n Microsoft.Insights --subscription "<SUBSCRIPTION_ID>"
az provider register -n Microsoft.Consumption --subscription "<SUBSCRIPTION_ID>"
```

---

## 2. Clone & Environment Setup

### 2.1 Clone the Repository

```bash
git clone https://github.com/jihys/foundry-based-cost-governance.git
cd foundry-based-cost-governance
```

### 2.2 Create Python Virtual Environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install openpyxl   # Required for Excel generation
```

### 2.3 Configure Authentication

**Option A: Service Principal (for automation/CI)**

```bash
cp sample.env .env
```

Edit the `.env` file:

```bash
export ARM_CLIENT_ID="<service-principal-app-id>"
export ARM_CLIENT_SECRET="<service-principal-password>"
export ARM_TENANT_ID="<azure-ad-tenant-id>"
export ALERT_EMAIL="team-lead@example.com"
export MONTHLY_BUDGET_USD=100
```

```bash
source .env
```

**Option B: az login (for manual deployment)**

```bash
az login
az account list -o table   # Verify subscription access
```

> **Note**: When using `az login`, run Terraform commands manually instead of using `deploy_all.sh` (see Step 4.2).

---

## 3. Configure Team tfvars

Create a `.tfvars` file for each team.

### 3.1 Copy Example Files

```bash
cp infra/envs/catalog.tfvars.example infra/envs/catalog.tfvars
cp infra/envs/image.tfvars.example infra/envs/image.tfvars
```

### 3.2 Fill in Subscription IDs

Open each file and replace `<YOUR_SUBSCRIPTION_ID>` with the actual value:

```hcl
# infra/envs/catalog.tfvars
team_name       = "catalog"
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # ← actual Subscription ID
alert_email     = "catalog-team@example.com"

regions = {
  "eastus" = [
    {
      name     = "gpt-41-mini"
      model    = "gpt-4.1-mini"
      version  = "2025-04-14"
      sku_name = "Standard"
      capacity = 30
    },
  ]
}
```

### 3.3 Customize Models (Optional)

To deploy across multiple regions or with different models, extend the `regions` map:

```hcl
regions = {
  "eastus" = [
    { name = "gpt-41-mini",  model = "gpt-4.1-mini",  version = "2025-04-14", sku_name = "Standard", capacity = 30 },
  ]
  "westus" = [
    { name = "gpt-4o",       model = "gpt-4o",        version = "2024-11-20", sku_name = "Standard", capacity = 30 },
  ]
}
```

> **Tip**: Choose `Standard` or `GlobalStandard` for `sku_name` based on your subscription quota. Check quota: `az cognitiveservices usage list -l eastus --subscription <ID> -o table`

⚠️ **Important**: `.tfvars` files contain subscription IDs and are **excluded from Git** via `.gitignore`. Never commit them.

---

## 4. Initialize & Deploy with Terraform

### 4.1 Automated Deployment (deploy_all.sh)

If Service Principal authentication is configured:

```bash
# Dry run — review planned changes only
./scripts/deploy_all.sh --plan-only

# Deploy
./scripts/deploy_all.sh
```

What the script does:
1. Auto-discovers teams from `infra/envs/*.tfvars`
2. Creates a Terraform workspace per team and runs `terraform apply`
3. Collects all outputs into `output/consolidated_outputs.json`
4. Generates `output/team_keys.xlsx` via `src/auth/key_export.py`

### 4.2 Manual Deployment (with az login)

If authenticated via `az login`, run Terraform per team:

```bash
cd infra

# Step 1: Initialize
terraform init

# Step 2: Deploy catalog team
terraform workspace new catalog 2>/dev/null || terraform workspace select catalog
terraform plan -var-file=envs/catalog.tfvars        # Review changes
terraform apply -var-file=envs/catalog.tfvars       # Type "yes" to deploy

# Step 3: Deploy image team
terraform workspace new image 2>/dev/null || terraform workspace select image
terraform plan -var-file=envs/image.tfvars
terraform apply -var-file=envs/image.tfvars
```

### 4.3 Verify Deployment

Resources created per team:

| Resource | Name Pattern | Purpose |
|----------|-------------|---------|
| Resource Group | `rg-{team}-ai-foundry` | Team resource container |
| AI Services | `ai-{team}-{region}` | OpenAI model hosting |
| Log Analytics | `law-{team}` | Diagnostic log collection |
| Application Insights | `appi-{team}` | Telemetry |
| Monitor Workbook | `Cost Dashboard - {team}` | Token usage visualization |
| Budget | `budget-{team}` | Monthly cost alerts |

Verify with:

```bash
az resource list --resource-group rg-catalog-ai-foundry --subscription <ID> -o table
```

---

## 5. Generate Excel Key File

### 5.1 Extract Terraform Outputs

If you deployed manually, save each team's output:

```bash
mkdir -p output

# catalog team
cd infra
terraform workspace select catalog
terraform output -json team_info > ../output/catalog_output.json

# image team
terraform workspace select image
terraform output -json team_info > ../output/image_output.json
cd ..
```

### 5.2 Consolidate Outputs

```bash
python3 -c "
import json

teams = {}
for team in ['catalog', 'image']:
    with open(f'output/{team}_output.json') as f:
        teams[team] = {
            'team_name': {'value': team},
            'team_info': {'value': json.load(f)}
        }

with open('output/consolidated_outputs.json', 'w') as f:
    json.dump(teams, f, indent=2)
print('Consolidated JSON created')
"
```

### 5.3 Generate Excel

```bash
python3 -m src.auth.key_export \
  --input output/consolidated_outputs.json \
  --output output/team_keys.xlsx
```

The generated Excel contains:

| Team | Subscription ID | Resource Group | Region | Foundry Endpoint | API Key (Key1) | API Key (Key2) | Model Deployments |
|------|----------------|---------------|--------|-----------------|---------------|---------------|-------------------|

⚠️ **Security**: `output/team_keys.xlsx` contains plaintext API keys. Handle the file securely.

---

## 6. Verify API Keys

### 6.1 Using Jupyter Notebook

```bash
jupyter notebook notebooks/verify_key_en.ipynb
```

The notebook will:
1. Read team endpoints and API keys from the Excel file
2. Test a Chat Completion API call (gpt-4.1-mini)
3. Display the response and token usage

### 6.2 Command-Line Test

You can also test directly without the notebook:

```bash
# Get endpoint/key from Terraform output
cd infra && terraform workspace select catalog
ENDPOINT=$(terraform output -json team_info | jq -r '.regions.eastus.endpoint')
API_KEY=$(terraform output -json team_info | jq -r '.regions.eastus.key1')
cd ..

# Call Chat Completion
curl -s "${ENDPOINT}openai/deployments/gpt-41-mini/chat/completions?api-version=2024-12-01-preview" \
  -H "Content-Type: application/json" \
  -H "api-key: ${API_KEY}" \
  -d '{"messages": [{"role": "user", "content": "Hello, say hi in Korean"}], "max_tokens": 50}' \
  | jq '.choices[0].message.content, .usage'
```

Expected output:

```json
"안녕하세요!"
{
  "prompt_tokens": 14,
  "completion_tokens": 4,
  "total_tokens": 18
}
```

---

## 7. Check Cost Dashboard

### 7.1 Wait for Log Ingestion

After making API calls, wait **5–15 minutes** for diagnostic logs to flow into Log Analytics via Diagnostic Settings.

### 7.2 Open Dashboard in Azure Portal

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to the team's subscription
3. Open **Resource Groups** → select `rg-{team}-ai-foundry`
4. Click the **Workbook** resource (GUID-style name)
5. View the 4 panels:
   - **Token Usage Daily**: Daily token usage bar chart
   - **Token Summary by Model**: Per-model summary table
   - **Estimated Cost Trend**: Cost trend line chart
   - **Request Count Daily**: Daily request count bar chart

### 7.3 Query Log Analytics Directly

```bash
# Get workspace GUID
WS_ID=$(az monitor log-analytics workspace show \
  --workspace-name law-catalog \
  --resource-group rg-catalog-ai-foundry \
  --subscription <SUBSCRIPTION_ID> \
  --query customerId -o tsv)

# Check token usage
az monitor log-analytics query -w "$WS_ID" \
  --analytics-query "
    AzureDiagnostics
    | where Category == 'AzureOpenAIRequestUsage'
    | extend props = parse_json(properties_s)
    | extend model = tostring(props.modelName)
    | extend tokens = toint(props.totalTokens)
    | summarize TotalTokens=sum(tokens), Requests=count() by model
  " -o table
```

---

## 8. Deploy Unified Dashboard (Optional)

To view data from all subscriptions in a single dashboard, deploy the unified workbook.

### 8.1 Configure tfvars

```bash
cp infra/unified/terraform.tfvars.example infra/unified/terraform.tfvars
```

Edit `infra/unified/terraform.tfvars`:

```hcl
subscription_id = "<MANAGEMENT_SUBSCRIPTION_ID>"   # Where to deploy the unified dashboard
location        = "eastus"

team_workspaces = {
  "catalog" = "/subscriptions/<CATALOG_SUB_ID>/resourceGroups/rg-catalog-ai-foundry/providers/Microsoft.OperationalInsights/workspaces/law-catalog"
  "image"   = "/subscriptions/<IMAGE_SUB_ID>/resourceGroups/rg-image-ai-foundry/providers/Microsoft.OperationalInsights/workspaces/law-image"
}
```

> **Tip**: Get the Log Analytics workspace ARM resource ID from the Azure Portal or via `az monitor log-analytics workspace show`.

### 8.2 Deploy

```bash
cd infra/unified
terraform init
terraform plan      # Review changes
terraform apply     # Deploy
```

### 8.3 View Unified Dashboard

After deployment, in Azure Portal:

1. Navigate to the management subscription
2. Open resource group `rg-unified-cost-dashboard`
3. Click **"Unified Cost Dashboard - All Teams"** workbook
4. View 5 panels with cross-team data:
   - Same 4 panels as per-team dashboards (with team labels)
   - **Team Comparison**: Side-by-side token/cost comparison table

### 8.4 Adding New Teams

To add a new team, simply add an entry to `team_workspaces`:

```hcl
team_workspaces = {
  "catalog" = "/subscriptions/xxx/...workspaces/law-catalog"
  "image"   = "/subscriptions/yyy/...workspaces/law-image"
  "search"  = "/subscriptions/zzz/...workspaces/law-search"   # ← new team
}
```

```bash
terraform apply
```

---

## 9. Clean Up Resources

### Automated Cleanup (deploy_all.sh)

```bash
source .env
./scripts/deploy_all.sh --destroy
```

### Manual Cleanup

```bash
cd infra

# Destroy per-team resources
terraform workspace select catalog
terraform destroy -var-file=envs/catalog.tfvars

terraform workspace select image
terraform destroy -var-file=envs/image.tfvars

# Destroy unified dashboard
cd unified
terraform destroy
```

---

## Troubleshooting

### Budget Error: "Start date should not be prior to current month"

The budget's `start_date` is earlier than the current month. Update `start_date` in `infra/main.tf` to the first day of the current month:

```hcl
time_period {
  start_date = "2026-07-01T00:00:00Z"   # First day of current month
}
```

### Model Deployment Failure: InsufficientQuota

The subscription has zero quota for that model. Check available quota:

```bash
az cognitiveservices usage list -l eastus --subscription <ID> -o table
```

Choose a model with available `Standard` SKU quota, or request a quota increase in the Azure Portal.

### Dashboard Shows No Data

1. Wait **at least 15 minutes** after making API calls (diagnostic log ingestion delay).
2. Verify `AzureOpenAIRequestUsage` category is enabled:
   ```bash
   az monitor diagnostic-settings show \
     --name diag-{team}-{region} \
     --resource /subscriptions/<ID>/resourceGroups/rg-{team}-ai-foundry/providers/Microsoft.CognitiveServices/accounts/ai-{team}-{region} \
     --query "logs[?category=='AzureOpenAIRequestUsage'].enabled"
   ```
3. Check if data has arrived in Log Analytics:
   ```bash
   az monitor log-analytics query -w <WORKSPACE_GUID> \
     --analytics-query "AzureDiagnostics | where Category == 'AzureOpenAIRequestUsage' | count"
   ```
