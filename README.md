# CI Workflows

프로젝트에서 재사용 가능한 CI/CD 워크플로우.

## 빠른 시작 (자동 셋업)

새 프로젝트에 CI를 적용하려면:

```bash
bash <(curl -s https://raw.githubusercontent.com/kimkitae/ci-workflows/main/setup.sh)
```

대화형으로 프로젝트 설정을 입력하면 `.github/workflows/` 파일이 자동 생성됩니다.

## 수동 설정

### 1. E2E 테스트 (PR 시)

```yaml
# .github/workflows/ci.yml
name: CI
on:
  pull_request:
    branches: [develop, main]

jobs:
  e2e:
    uses: kimkitae/ci-workflows/.github/workflows/e2e-test.yml@main
    with:
      backend-dir: backend
      frontend-dir: frontend
      db-name: my_test_db
      db-user: myuser
      db-password: mypass
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 2. 자동 배포 (PR 머지 시)

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  pull_request:
    types: [closed]
    branches: [develop]

jobs:
  deploy:
    if: github.event.pull_request.merged == true
    uses: kimkitae/ci-workflows/.github/workflows/deploy.yml@main
    with:
      project-dir: /home/user/my-project
      services: my-backend my-frontend
      runner-labels: '["self-hosted", "linux", "my-server"]'
      backend-health-url: http://127.0.0.1:8384/health
      frontend-health-url: http://127.0.0.1:8383
```

## Harness Review Hooks (저녁/주간 회고 자동화)

Claude Code Stop hook으로 매일 저녁(평일·토) AI가 직접 `harness-log.md` / `CLAUDE.md` / `.claude/hooks/`를 편집하고, 일요일 저녁에는 주간 sweep까지 수행하도록 설치합니다.

```bash
# 한 줄 설치
curl -sSL https://raw.githubusercontent.com/kimkitae/ci-workflows/main/install/harness-review-hooks.sh | bash
```

추가되는 것:

| 파일 | 역할 |
|------|------|
| `.claude/hooks/evening-review-trigger.sh` | Stop hook (DOW 분기, 22시 이후 1회/일) |
| `docs/evening-review-prompt.md` | 평일 저녁 5단계 AI 플레이북 |
| `docs/weekly-review-prompt.md` | 일요일용 (daily + 4 weekly sweep) |
| `.claude/settings.json` | Stop hook 등록 (jq로 안전 머지) |

전제: 프로젝트가 [general-harness](https://github.com/kimkitae/general-harness) 레이아웃을 따른다 (`CLAUDE.md`, `docs/harness-log.md` 존재).

옵션:
- `EVENING_REVIEW_HOUR=20` 등으로 발화 시각 조정
- 강제 재실행: `rm .omc/logs/evening-review.$(date +%F).done`
- 비활성화: hook을 `.claude/settings.json` 에서 제거

---

## 워크플로우 목록

| 워크플로우 | 설명 |
|-----------|------|
| `e2e-test.yml` | Playwright E2E 테스트 (Postgres + Redis) |
| `deploy.yml` | Docker Compose 배포 (self-hosted runner) |
| `install/harness-review-hooks.sh` | 저녁/주간 회고 Stop hook 설치 |

## 필요한 Secrets

| Secret | 용도 | 필수 |
|--------|------|------|
| `ANTHROPIC_API_KEY` | E2E 테스트 시 AI 기능 | 선택 |
