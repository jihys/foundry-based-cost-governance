# foundry-model-key-sharing

Azure AI Foundry 팀별 키 공유 및 사용량 모니터링 샘플

## Overview

Azure AI Foundry의 구독 수준 리소스를 여러 팀이 공유할 때 필요한 패턴을 보여주는 샘플입니다:

- **키 공유**: Subscription Foundry 리소스의 API 키를 안전하게 공유하는 방법
- **사용량 모니터링**: 팀별/모델별 사용량 추적 및 알림
- **RBAC 설정**: 팀별 접근 권한 관리
- **비용 거버넌스**: 예산 알림 및 할당량 관리

## Setup

```bash
# 가상환경 생성 및 활성화
python -m venv .venv
source .venv/bin/activate

# 의존성 설치
pip install -r requirements.txt

# 환경변수 설정
cp sample.env .env
# .env 파일을 편집하여 Azure 리소스 정보 입력
```

## Project Structure

```
├── src/
│   ├── auth/           # 인증 및 키 관리
│   ├── usage/          # 사용량 모니터링
│   ├── sharing/        # 리소스 공유 로직
│   └── utils/          # 공통 유틸리티
├── infra/              # Bicep IaC (Azure 인프라)
├── notebooks/          # 샘플 노트북
├── tests/              # 테스트
└── docs/               # 문서
```

## Development Workflow

이 프로젝트는 skills-first 에이전트 워크플로우를 사용합니다.

- **Orchestrator**: `@orchestrator` — 멀티 에이전트 오케스트레이션
- **Planner**: `@planner` — PRD 생성, 이슈 분해
- **Senior Developer**: `@senior-developer` — TDD 구현, 디버깅
- **Researcher**: `@researcher` — 코드베이스 탐색, 패턴 분석
- **Reviewer**: `@reviewer` — 코드 리뷰, 보안 검토
- **PR Author**: `@pr-author` — PR 생성 및 워크플로우 감사
- **Documentation Writer**: `@documentation-writer` — 문서화

## License

MIT
