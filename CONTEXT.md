# foundry-based-cost-governance Context

This context defines the durable language for Azure AI Foundry 팀별 키 공유 및 사용량 모니터링 샘플.

## Language

| Term | Definition |
|------|-----------|
| Subscription Foundry Resource | Azure 구독 수준에서 공유되는 AI Foundry 리소스 |
| Model Deployment | Foundry 내 배포된 AI 모델 (GPT-4o, text-embedding 등) |
| Shared Key | 여러 팀/프로젝트가 공유하는 API 키 |
| Usage Quota | 모델별 할당된 사용량 제한 (TPM/RPM) |
| RBAC | Role-Based Access Control — Azure AD 기반 접근 제어 |
| Cost Alert | 사용량 기반 비용 알림 |

## Relationships

- Subscription → 1:N → AI Foundry Resource
- AI Foundry Resource → 1:N → Model Deployment
- Model Deployment → 1:1 → Usage Quota
- Team → N:M → Model Deployment (via RBAC)

## Flagged ambiguities

<!-- 해결이 필요한 모호한 용어를 여기에 기록합니다. -->
