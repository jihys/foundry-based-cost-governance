# foundry-based-cost-governance

Azure AI Foundry 팀별 키 공유 및 사용량 모니터링 샘플

## Tech Stack

- **Language**: Python 3.11+
- **Framework**: Azure SDK (`azure-ai-projects`, `azure-identity`, `azure-mgmt-cognitiveservices`)
- **Infra**: Terraform (Azure AI Foundry, RBAC, Budget Alerts)
- **Test**: pytest
- **Docs**: Markdown

## Implementation Structure

```
src/                    # 메인 소스 코드
├── auth/               # 인증 및 키 관리
├── usage/              # 사용량 모니터링
├── sharing/            # 리소스 공유 로직
└── utils/              # 공통 유틸리티
tests/                  # 테스트
infra/                  # Terraform IaC
notebooks/              # 샘플 노트북
docs/                   # 문서
```

## Naming

- **Files**: `snake_case.py`
- **Classes**: `PascalCase`
- **Functions/Variables**: `snake_case`
- **Constants**: `UPPER_SNAKE_CASE`
- **Branches**: `feat/<issue-id>-short-desc`, `fix/<issue-id>-short-desc`
- **Commits**: `type(scope): description` (conventional commits)

## Code Rules

- Type hints on all public functions
- Docstrings on all public classes and functions
- No hardcoded secrets — use environment variables or Azure Identity
- Prefer `DefaultAzureCredential` for authentication
- All API keys managed through Azure Key Vault or RBAC

## Git Rules

- Squash merge to `main`
- Branch protection: require PR review
- No direct pushes to `main`

## Agent Skills

<!-- setup-matt-pocock-skills 실행 후 채워짐 -->
