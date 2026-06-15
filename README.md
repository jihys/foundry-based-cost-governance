# foundry-based-cost-governance

🌐 [English version](README.en.md)

Azure AI Foundry 팀별 Subscription 분리, 키 공유, 사용량 모니터링 샘플

## Overview

팀(Team)별로 Azure Subscription을 분리하고, 각 Subscription에 AI Foundry 리소스를 배포하여 **비용 격리**와 **키 관리**를 수행하는 PoC 샘플입니다.

### Architecture

```
Team (catalog, image, search)
 └── Subscription (1:1)
      ├── Foundry Resource (리전별 1:N — 모델 가용성에 따라)
      │    ├── Model Deployment (gpt-4o, text-embedding-3-large, o3-mini …)
      │    └── Resource Key (Key1, Key2)
      ├── Application Insights (1:1 — 토큰 텔레메트리 수집)
      │    └── Cost Dashboard (Workbook — KQL 쿼리로 시각화)
      └── Budget Alert (월간 비용 임계값 알림)
```

- **Team**: 프로젝트 팀. 각 Team은 전용 Subscription을 소유
- **Foundry Resource**: Subscription 내 리전별 Azure AI Services 계정. 각각 독립된 endpoint와 Resource Key 보유
- **Resource Key**: API 키 기반 인증. Terraform output → Python 스크립트로 단일 Excel 파일에 기록
- **Cost Dashboard**: Application Insights에서 토큰 사용량/비용을 수집하여 Azure Monitor Workbook으로 시각화

## Prerequisites

- **Azure Subscriptions**: 팀당 1개 (예: catalog, image, search → 3개 Subscription)
- **Service Principal**: `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID` — 모든 Subscription에 Contributor 권한
- **Terraform** ≥ 1.5
- **Python** ≥ 3.11
- **jq** (deploy 스크립트에서 JSON 처리에 사용)

## Project Structure

```
├── infra/                  # Terraform IaC
│   ├── main.tf             # Azure AI Services, App Insights, Budget, Workbook
│   ├── variables.tf        # 입력 변수 정의
│   ├── outputs.tf          # 팀별 endpoint/key 출력
│   ├── versions.tf         # provider 버전
│   └── envs/               # 팀별 tfvars
│       ├── catalog.tfvars
│       ├── image.tfvars
│       └── search.tfvars
├── scripts/
│   └── deploy_all.sh       # 멀티팀 Terraform 배포 오케스트레이터
├── src/
│   └── auth/
│       └── key_export.py   # Terraform output JSON → Excel 변환
├── notebooks/
│   └── verify_key.ipynb    # API 키 검증 샘플 노트북
├── tests/
│   └── test_key_export.py  # key_export 유닛 테스트
├── output/                 # (gitignored) 배포 결과물
│   ├── consolidated_outputs.json
│   └── team_keys.xlsx
├── requirements.txt
├── sample.env
└── README.md
```

## Quick Start

### 1. Clone & Setup

```bash
git clone <repo-url>
cd foundry-based-cost-governance

python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. 환경 변수 설정

```bash
cp sample.env .env
```

`.env` 파일을 편집하여 Service Principal 정보를 입력합니다:

```bash
export ARM_CLIENT_ID="<service-principal-app-id>"
export ARM_CLIENT_SECRET="<service-principal-password>"
export ARM_TENANT_ID="<azure-ad-tenant-id>"
export ALERT_EMAIL="team-lead@example.com"
export MONTHLY_BUDGET_USD=100
```

### 3. 팀별 tfvars 편집

`infra/envs/` 디렉토리의 각 `.tfvars` 파일에 팀 Subscription ID와 모델 배포 설정을 입력합니다:

```hcl
# infra/envs/catalog.tfvars
team_name       = "catalog"
subscription_id = "<catalog-team-subscription-id>"
alert_email     = "catalog-team@example.com"

regions = {
  "eastus" = [
    { name = "gpt-4o", model = "gpt-4o", version = "2024-11-20", sku_name = "GlobalStandard", capacity = 30 },
    { name = "text-embedding-3-large", model = "text-embedding-3-large", version = "1", sku_name = "Standard", capacity = 120 },
  ]
}
```

### 4. 배포 실행

```bash
# 환경 변수 로드
source .env

# 드라이런 (plan-only)
./scripts/deploy_all.sh --plan-only

# 실제 배포
./scripts/deploy_all.sh
```

`deploy_all.sh`는 다음을 수행합니다:
1. `infra/envs/*.tfvars`에서 팀 목록 자동 탐지
2. 팀별로 Terraform workspace 생성 및 `apply`
3. 모든 팀의 Terraform output을 `output/consolidated_outputs.json`으로 수집
4. `src/auth/key_export.py`로 `output/team_keys.xlsx` 생성

### 5. 키 검증

생성된 Excel 파일로 API 키가 작동하는지 확인합니다:

```bash
# Jupyter Notebook에서 검증
jupyter notebook notebooks/verify_key.ipynb
```

노트북은 Excel에서 endpoint와 API 키를 읽어 Chat Completion, Embedding 호출을 테스트합니다.

## Cost Dashboard

배포 완료 후 Azure Portal에서 팀별 비용을 확인할 수 있습니다:

1. **Azure Portal** → 해당 Team Subscription 선택
2. **Application Insights** → **Workbooks** 메뉴
3. Terraform이 배포한 Cost Dashboard Workbook에서 토큰 사용량/비용 시각화 확인

Budget Alert는 `monthly_budget_usd` 임계값(기본 100 USD)의 80%, 100%, 120% 도달 시 `alert_email`로 알림을 발송합니다.

## Security Note

> **⚠️ 이 샘플은 PoC/학습 목적입니다.**

- `output/team_keys.xlsx`에 API 키가 **평문**으로 기록됩니다
- Excel 파일은 `.gitignore`에 포함하고, 절대 Git에 커밋하지 마십시오
- **프로덕션 환경**에서는 다음을 권장합니다:
  - Azure Key Vault에 키 저장
  - Entra ID (`DefaultAzureCredential`) 기반 인증
  - RBAC으로 팀별 접근 권한 관리

## License

MIT
