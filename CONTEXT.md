# foundry-based-cost-governance Context

프로젝트 팀별 Azure Subscription을 분리하고, 각 Subscription에 AI Foundry 리소스를 배포하여 팀별 비용 거버넌스와 키 관리를 수행하는 샘플.

## Language

**Team**:
프로젝트 팀. 초기 목록: `catalog`, `image`, `search`. 각 Team은 전용 Subscription을 소유한다.
_Avoid_: Purpose, department (Team이 정식 명칭)

**Subscription**:
Team 전용 Azure Subscription. Team과 1:1 매핑. 비용 격리와 거버넌스의 최상위 경계.
_Avoid_: Resource Group, Project (격리 단위로서)

**Foundry Resource**:
Subscription 내에 리전별로 생성된 Azure AI Services 계정. 모델 가용성에 따라 하나의 Subscription에 여러 리전의 Foundry Resource가 존재할 수 있다. 각각 독립된 endpoint와 Resource Key를 가진다.

**Model Deployment**:
Foundry Resource 내 배포된 AI 모델 (GPT-4o, text-embedding 등).

**Resource Key**:
Foundry Resource에 접근하기 위한 API 키. 모든 Team의 키를 단일 Excel 파일에 평문으로 기록. Terraform output → Python 스크립트로 생성. 외부 개발자가 Entra ID 없이 API 키만으로 접근하는 시나리오.
_Avoid_: Shared Key, Key Vault 참조 (외부 개발자 Entra ID 미사용으로 불가)

**Usage Quota**:
모델별 할당된 사용량 제한 (TPM/RPM).

**Cost Dashboard**:
Team(=Subscription)별 토큰 사용량과 비용을 시각화하는 Azure Monitor Workbook. Application Insights에서 AI Foundry 토큰 텔레메트리(token usage, token cost)를 수집하고, Workbook으로 시각화. Terraform으로 Budget Alert도 함께 배포.

**Application Insights**:
AI Foundry의 토큰 수준 텔레메트리를 수집하는 모니터링 리소스. 각 Subscription에 1개 배포. Foundry Resource의 진단 설정(Diagnostic Settings)을 통해 연결.
_Avoid_: Azure Monitor Logs (Application Insights가 정식 명칭)

**Cost Alert**:
사용량 기반 비용 알림.

## Relationships

- **Team** → 1:1 → **Subscription**
- **Subscription** → 1:N → **Foundry Resource** (리전별, 모델 가용성에 따라)
- **Subscription** → 1:1 → **Application Insights**
- **Foundry Resource** → 1:N → **Model Deployment**
- **Foundry Resource** → 1:1 → **Resource Key** (Key1 + Key2)
- **Foundry Resource** → Diagnostic Settings → **Application Insights**
- **Model Deployment** → 1:1 → **Usage Quota**
- **Application Insights** → **Cost Dashboard** (Workbook이 KQL 쿼리로 시각화)

## Example dialogue

> **Dev:** "catalog 팀의 이번 달 비용이 얼마야?"
> **Domain expert:** "catalog Subscription의 Cost Dashboard를 보면 돼. Subscription 단위로 비용이 격리되니까."
>
> **Dev:** "image 팀에 o3-mini를 배포하고 싶은데 koreacentral에서 안 돼."
> **Domain expert:** "swedencentral에 Foundry Resource를 추가 생성하고 거기에 o3-mini를 배포하면 돼. 별도 Resource Key가 발급되고 Excel에 행이 추가될 거야."

## Flagged ambiguities

- "Subscription"이 Azure Subscription을 의미함을 확정 (Resource Group이나 Foundry Project가 아님)
- "catalog", "image", "search"는 AI 기능 분류가 아니라 프로젝트 팀 이름임을 확정
