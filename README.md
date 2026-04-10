# CI Workflows

프로젝트에서 재사용 가능한 CI/CD 워크플로우.

## 사용법

프로젝트의 `.github/workflows/`에 아래 파일들을 추가하세요.

### 1. PR 시 E2E 테스트 + AI 리뷰

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
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}

  ai-review:
    uses: kimkitae/ci-workflows/.github/workflows/ai-review.yml@main
    with:
      language: ko
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 2. PR 머지 시 자동 배포

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

## 워크플로우 목록

| 워크플로우 | 설명 |
|-----------|------|
| `e2e-test.yml` | Playwright E2E 테스트 (Postgres + Redis) |
| `ai-review.yml` | Claude AI 코드 리뷰 |
| `deploy.yml` | Docker Compose 배포 (self-hosted runner) |

## 필요한 Secrets

| Secret | 용도 | 필수 |
|--------|------|------|
| `ANTHROPIC_API_KEY` | AI 리뷰, E2E 테스트 시 AI 기능 | ai-review: 필수 |
