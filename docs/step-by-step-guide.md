# Step-by-Step 배포 가이드

이 문서는 Azure AI Foundry 비용 거버넌스 시스템을 **처음부터 끝까지** 배포하는 과정을 안내합니다.

---

## 목차

1. [사전 준비](#1-사전-준비)
2. [프로젝트 클론 및 환경 설정](#2-프로젝트-클론-및-환경-설정)
3. [팀별 tfvars 설정](#3-팀별-tfvars-설정)
4. [Terraform 초기화 및 배포](#4-terraform-초기화-및-배포)
5. [Excel 키 파일 생성](#5-excel-키-파일-생성)
6. [API 키 검증](#6-api-키-검증)
7. [비용 대시보드 확인](#7-비용-대시보드-확인)
8. [통합 대시보드 배포 (선택)](#8-통합-대시보드-배포-선택)
9. [리소스 정리](#9-리소스-정리)

---

## 1. 사전 준비

### 필수 도구

| 도구 | 최소 버전 | 설치 확인 |
|------|----------|----------|
| Terraform | 1.5+ | `terraform version` |
| Python | 3.10+ | `python3 --version` |
| Azure CLI | 2.50+ | `az version` |
| jq | 1.6+ | `jq --version` |

### Azure 리소스

- **Azure Subscription**: 팀당 1개 (예: catalog 팀, image 팀 → 최소 2개)
- **Service Principal** 또는 **az login** 인증
  - Service Principal 사용 시: 모든 Subscription에 **Contributor** 역할 필요
  - az login 사용 시: 해당 계정이 모든 Subscription에 접근 가능해야 함
- 각 Subscription에 `Microsoft.CognitiveServices` 리소스 프로바이더가 등록되어 있어야 합니다

### 리소스 프로바이더 등록 확인

```bash
# 각 Subscription에 대해 실행
az provider register -n Microsoft.CognitiveServices --subscription "<SUBSCRIPTION_ID>"
az provider register -n Microsoft.Insights --subscription "<SUBSCRIPTION_ID>"
az provider register -n Microsoft.Consumption --subscription "<SUBSCRIPTION_ID>"
```

---

## 2. 프로젝트 클론 및 환경 설정

### 2.1 프로젝트 클론

```bash
git clone https://github.com/jihys/foundry-based-cost-governance.git
cd foundry-based-cost-governance
```

### 2.2 Python 가상 환경 생성

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install openpyxl   # Excel 생성에 필요
```

### 2.3 인증 설정

**방법 A: Service Principal (자동화/CI용)**

```bash
cp sample.env .env
```

`.env` 파일을 편집합니다:

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

**방법 B: az login (수동 배포용)**

```bash
az login
az account list -o table   # Subscription 목록 확인
```

> **참고**: `az login`을 사용하는 경우 `deploy_all.sh` 스크립트 대신 수동으로 Terraform 명령어를 실행합니다 (Step 4.2 참조).

---

## 3. 팀별 tfvars 설정

각 팀에 대해 `.tfvars` 파일을 생성합니다.

### 3.1 example 파일 복사

```bash
cp infra/envs/catalog.tfvars.example infra/envs/catalog.tfvars
cp infra/envs/image.tfvars.example infra/envs/image.tfvars
```

### 3.2 Subscription ID 입력

각 파일을 열어 `<YOUR_SUBSCRIPTION_ID>`를 실제 값으로 교체합니다:

```hcl
# infra/envs/catalog.tfvars
team_name       = "catalog"
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # ← 실제 Subscription ID
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

### 3.3 모델 커스터마이징 (선택)

여러 리전이나 모델을 배포하려면 `regions` 맵을 확장합니다:

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

> **팁**: `sku_name`은 Subscription의 쿼터에 따라 `Standard` 또는 `GlobalStandard`를 선택합니다. 쿼터 확인: `az cognitiveservices usage list -l eastus --subscription <ID> -o table`

⚠️ **주의**: `.tfvars` 파일에는 Subscription ID가 포함되므로 **절대 Git에 커밋하지 마세요** (`.gitignore`에 이미 포함됨).

---

## 4. Terraform 초기화 및 배포

### 4.1 자동 배포 (deploy_all.sh)

Service Principal 인증이 설정된 경우:

```bash
# 드라이런 — 변경 사항만 확인
./scripts/deploy_all.sh --plan-only

# 실제 배포
./scripts/deploy_all.sh
```

스크립트가 수행하는 작업:
1. `infra/envs/*.tfvars` 파일에서 팀 목록 자동 탐지
2. 팀마다 Terraform workspace를 생성하고 `terraform apply` 실행
3. 결과를 `output/consolidated_outputs.json`에 수집
4. `output/team_keys.xlsx` Excel 파일 자동 생성

### 4.2 수동 배포 (az login 사용)

`az login`으로 인증한 경우 팀별로 직접 실행합니다:

```bash
cd infra

# Step 1: 초기화
terraform init

# Step 2: catalog 팀 배포
terraform workspace new catalog 2>/dev/null || terraform workspace select catalog
terraform plan -var-file=envs/catalog.tfvars        # 변경 사항 확인
terraform apply -var-file=envs/catalog.tfvars       # "yes" 입력하여 배포

# Step 3: image 팀 배포
terraform workspace new image 2>/dev/null || terraform workspace select image
terraform plan -var-file=envs/image.tfvars
terraform apply -var-file=envs/image.tfvars
```

### 4.3 배포 확인

배포 후 생성되는 리소스:

| 리소스 | 이름 패턴 | 용도 |
|--------|----------|------|
| Resource Group | `rg-{team}-ai-foundry` | 팀별 리소스 그룹 |
| AI Services | `ai-{team}-{region}` | OpenAI 모델 호스팅 |
| Log Analytics | `law-{team}` | 진단 로그 수집 |
| Application Insights | `appi-{team}` | 텔레메트리 |
| Monitor Workbook | `Cost Dashboard - {team}` | 토큰 사용량 시각화 |
| Budget | `budget-{team}` | 월간 비용 알림 |

확인 명령어:

```bash
az resource list --resource-group rg-catalog-ai-foundry --subscription <ID> -o table
```

---

## 5. Excel 키 파일 생성

### 5.1 Terraform Output 추출

수동 배포한 경우 각 팀의 output을 저장합니다:

```bash
mkdir -p output

# catalog 팀
cd infra
terraform workspace select catalog
terraform output -json team_info > ../output/catalog_output.json

# image 팀
terraform workspace select image
terraform output -json team_info > ../output/image_output.json
cd ..
```

### 5.2 Output 통합

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

### 5.3 Excel 생성

```bash
python3 -m src.auth.key_export \
  --input output/consolidated_outputs.json \
  --output output/team_keys.xlsx
```

생성된 Excel 파일의 컬럼:

| Team | Subscription ID | Resource Group | Region | Foundry Endpoint | API Key (Key1) | API Key (Key2) | Model Deployments |
|------|----------------|---------------|--------|-----------------|---------------|---------------|-------------------|

⚠️ **보안**: `output/team_keys.xlsx`에 API 키가 평문으로 저장됩니다. 파일을 안전하게 관리하세요.

---

## 6. API 키 검증

### 6.1 Jupyter Notebook 사용

```bash
jupyter notebook notebooks/verify_key.ipynb
```

노트북에서 수행하는 작업:
1. Excel 파일에서 팀별 endpoint와 API 키 읽기
2. Chat Completion API 호출 테스트 (gpt-4.1-mini)
3. 응답과 토큰 사용량 확인

### 6.2 커맨드라인 테스트

Excel 없이 직접 테스트할 수도 있습니다:

```bash
# Terraform output에서 endpoint/key 가져오기
cd infra && terraform workspace select catalog
ENDPOINT=$(terraform output -json team_info | jq -r '.regions.eastus.endpoint')
API_KEY=$(terraform output -json team_info | jq -r '.regions.eastus.key1')
cd ..

# Chat Completion 호출
curl -s "${ENDPOINT}openai/deployments/gpt-41-mini/chat/completions?api-version=2024-12-01-preview" \
  -H "Content-Type: application/json" \
  -H "api-key: ${API_KEY}" \
  -d '{"messages": [{"role": "user", "content": "Hello, say hi in Korean"}], "max_tokens": 50}' \
  | jq '.choices[0].message.content, .usage'
```

예상 출력:

```json
"안녕하세요!"
{
  "prompt_tokens": 14,
  "completion_tokens": 4,
  "total_tokens": 18
}
```

---

## 7. 비용 대시보드 확인

### 7.1 로그 수집 대기

API 호출 후 **5~15분** 정도 기다리면 Diagnostic Settings를 통해 토큰 사용량 로그가 Log Analytics에 수집됩니다.

### 7.2 Azure Portal에서 대시보드 열기

1. [Azure Portal](https://portal.azure.com) 접속
2. 해당 팀의 Subscription으로 이동
3. **리소스 그룹** → `rg-{team}-ai-foundry` 선택
4. 리소스 목록에서 **Workbook** (GUID 형태 이름) 클릭
5. 4개 패널 확인:
   - **Token Usage Daily**: 일별 토큰 사용량 바 차트
   - **Token Summary by Model**: 모델별 요약 테이블
   - **Estimated Cost Trend**: 비용 추세 라인 차트
   - **Request Count Daily**: 일별 요청 수

### 7.3 Log Analytics에서 직접 쿼리

```bash
# Workspace ID 가져오기
WS_ID=$(az monitor log-analytics workspace show \
  --workspace-name law-catalog \
  --resource-group rg-catalog-ai-foundry \
  --subscription <SUBSCRIPTION_ID> \
  --query customerId -o tsv)

# 토큰 사용량 확인
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

## 8. 통합 대시보드 배포 (선택)

여러 Subscription의 데이터를 한 곳에서 보려면 통합 대시보드를 배포합니다.

### 8.1 tfvars 설정

```bash
cp infra/unified/terraform.tfvars.example infra/unified/terraform.tfvars
```

`infra/unified/terraform.tfvars`를 편집합니다:

```hcl
subscription_id = "<MANAGEMENT_SUBSCRIPTION_ID>"   # 통합 대시보드를 배포할 Subscription
location        = "eastus"

team_workspaces = {
  "catalog" = "/subscriptions/<CATALOG_SUB_ID>/resourceGroups/rg-catalog-ai-foundry/providers/Microsoft.OperationalInsights/workspaces/law-catalog"
  "image"   = "/subscriptions/<IMAGE_SUB_ID>/resourceGroups/rg-image-ai-foundry/providers/Microsoft.OperationalInsights/workspaces/law-image"
}
```

> **팁**: Log Analytics workspace의 ARM Resource ID는 배포 후 Azure Portal이나 `az monitor log-analytics workspace show` 명령으로 확인할 수 있습니다.

### 8.2 배포

```bash
cd infra/unified
terraform init
terraform plan      # 변경 사항 확인
terraform apply     # 배포
```

### 8.3 통합 대시보드 확인

배포 후 Azure Portal에서:

1. 관리용 Subscription으로 이동
2. 리소스 그룹 `rg-unified-cost-dashboard` 선택
3. **"Unified Cost Dashboard - All Teams"** Workbook 클릭
4. 5개 패널에서 전체 팀 데이터 확인:
   - 기존 4개 패널 (팀별 구분 포함)
   - **Team Comparison**: 팀 간 토큰/비용 비교 테이블

### 8.4 새 팀 추가

새 팀을 추가할 때는 `team_workspaces`에 항목만 추가하면 됩니다:

```hcl
team_workspaces = {
  "catalog" = "/subscriptions/xxx/...workspaces/law-catalog"
  "image"   = "/subscriptions/yyy/...workspaces/law-image"
  "search"  = "/subscriptions/zzz/...workspaces/law-search"   # ← 추가
}
```

```bash
terraform apply
```

---

## 9. 리소스 정리

### 자동 정리 (deploy_all.sh)

```bash
source .env
./scripts/deploy_all.sh --destroy
```

### 수동 정리

```bash
cd infra

# 팀별 리소스 삭제
terraform workspace select catalog
terraform destroy -var-file=envs/catalog.tfvars

terraform workspace select image
terraform destroy -var-file=envs/image.tfvars

# 통합 대시보드 삭제
cd unified
terraform destroy
```

---

## 트러블슈팅

### Budget 에러: "Start date should not be prior to current month"

Budget의 `start_date`가 현재 월보다 과거입니다. `infra/main.tf`에서 `start_date`를 현재 월 1일로 수정합니다:

```hcl
time_period {
  start_date = "2026-07-01T00:00:00Z"   # 현재 월의 1일
}
```

### 모델 배포 실패: InsufficientQuota

Subscription의 해당 모델 쿼터가 0입니다. 사용 가능한 쿼터 확인:

```bash
az cognitiveservices usage list -l eastus --subscription <ID> -o table
```

`Standard` SKU로 쿼터가 있는 모델을 선택하거나, Azure Portal에서 쿼터 증가를 요청하세요.

### 대시보드에 데이터가 안 보임

1. API 호출 후 **15분 이상** 기다리세요 (Diagnostic 로그 수집 지연)
2. `AzureOpenAIRequestUsage` 카테고리가 활성화되어 있는지 확인:
   ```bash
   az monitor diagnostic-settings show \
     --name diag-{team}-{region} \
     --resource /subscriptions/<ID>/resourceGroups/rg-{team}-ai-foundry/providers/Microsoft.CognitiveServices/accounts/ai-{team}-{region} \
     --query "logs[?category=='AzureOpenAIRequestUsage'].enabled"
   ```
3. Log Analytics에 데이터가 도착했는지 직접 확인:
   ```bash
   az monitor log-analytics query -w <WORKSPACE_GUID> \
     --analytics-query "AzureDiagnostics | where Category == 'AzureOpenAIRequestUsage' | count"
   ```
