# CI Workflows

프로젝트에서 재사용 가능한 CI/CD 워크플로우.

## 빠른 시작 (자동 셋업)

새 프로젝트에 CI를 적용하려면:

```bash
bash <(curl -s https://raw.githubusercontent.com/kimkitae/ci-workflows/main/setup.sh)
```

대화형으로 프로젝트 설정을 입력하면 `.github/workflows/` 파일이 자동 생성됩니다.

## 수동 설정

### 1. AI 코드 리뷰 (PR 시)

> **중요**: `permissions` 블록 필수 (private 레포에서 PR 코멘트 작성에 필요)

```yaml
# .github/workflows/ai-review.yml
name: AI Code Review
on:
  pull_request:
    types: [opened, synchronize]
    branches: [develop, main]

permissions:
  pull-requests: write
  contents: read

jobs:
  review:
    uses: kimkitae/ci-workflows/.github/workflows/ai-review.yml@main
    with:
      language: ko
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 2. E2E 테스트 (PR 시)

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

### 3. 자동 배포 (PR 머지 시)

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

## 주의사항

- **Private 레포**: `ai-review.yml` caller에 `permissions: pull-requests: write` 필수
- **AI Review와 CI 분리**: AI Review는 별도 워크플로우로 분리 권장 (ci.yml에 합치면 permissions 충돌)
