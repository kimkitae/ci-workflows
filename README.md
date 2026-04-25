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

## Deploy 서버 부트스트랩 (배포 대상에서 1회 실행)

GitHub Actions 의 `deploy.yml` 이 `ssh DEPLOY_HOST` 로 들어가 `docker compose pull && up -d` 를 돌리려면 서버가 미리 준비되어 있어야 합니다 (레포 clone, `.env`, ghcr.io 로그인). 이 셋업을 한 줄로:

```bash
# 배포 대상 서버에서 (ssh 들어간 다음):
curl -sSL https://raw.githubusercontent.com/kimkitae/ci-workflows/main/install/deploy-server-bootstrap.sh \
  | bash -s -- <owner>/<repo>

# 예:
curl -sSL https://raw.githubusercontent.com/kimkitae/ci-workflows/main/install/deploy-server-bootstrap.sh \
  | bash -s -- kimkitae/project-management-system
```

스크립트가 하는 일 (idempotent — 여러 번 돌려도 안전):
1. `~/projects/<repo>` 에 clone (이미 있으면 fetch만)
2. `.env.example` → `.env` 복사 (이미 있으면 건드리지 않음)
3. `ghcr.io` 로그인 (PAT 입력 받음, public 이미지면 `SKIP_DOCKER_LOGIN=1` 로 스킵)
4. `docker-compose.prod.yml` 파싱 검증

환경 변수 오버라이드:
- `DEPLOY_PATH` — clone 위치 (기본 `~/projects/<repo>`)
- `COMPOSE_FILE` — compose 파일명 (기본 `docker-compose.prod.yml`)
- `GHCR_USER`, `GHCR_PAT` — 비대화형 로그인용
- `SKIP_DOCKER_LOGIN=1` — public 이미지일 때

스크립트가 끝나면 dev 머신에서 등록할 GitHub secrets 명령을 그대로 출력해줍니다.

---

## 워크플로우 목록

| 워크플로우 / 스크립트 | 설명 |
|----------------------|------|
| `e2e-test.yml` | Playwright E2E 테스트 (Postgres + Redis) |
| `deploy.yml` | Docker Compose 배포 (self-hosted runner) |
| `install/harness-review-hooks.sh` | 저녁/주간 회고 Stop hook 설치 (개발 머신에서) |
| `install/deploy-server-bootstrap.sh` | 배포 대상 서버 1회 셋업 (clone + .env + ghcr.io 로그인) |

## 필요한 Secrets

| Secret | 용도 | 필수 |
|--------|------|------|
| `ANTHROPIC_API_KEY` | E2E 테스트 시 AI 기능 | 선택 |
| `DEPLOY_HOST` | `deploy.yml` SSH 대상 hostname/IP | 배포 사용 시 필수 |
| `DEPLOY_USER` | SSH 사용자 | 배포 사용 시 필수 |
| `DEPLOY_SSH_KEY` | private key 전체 내용 | 배포 사용 시 필수 |
| `DEPLOY_PORT` | SSH 포트 (기본 22) | 비표준 포트일 때만 |
| `DEPLOY_HEALTH_URL` | 배포 후 헬스체크 public URL | 선택 |
