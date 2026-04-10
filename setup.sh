#!/bin/bash
set -euo pipefail

# CI Workflows Setup Script
# Usage: bash <(curl -s https://raw.githubusercontent.com/kimkitae/ci-workflows/main/setup.sh)

REPO_URL="https://raw.githubusercontent.com/kimkitae/ci-workflows/main/templates"

echo "=== CI Workflows Setup ==="
echo ""

# Detect project name from git remote or directory
PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
echo "Project: $PROJECT_NAME"
echo ""

# Prompt for configuration
read -rp "DB name [${PROJECT_NAME}_db]: " DB_NAME
DB_NAME=${DB_NAME:-${PROJECT_NAME}_db}

read -rp "DB user [${PROJECT_NAME}]: " DB_USER
DB_USER=${DB_USER:-${PROJECT_NAME}}

read -rp "DB password [testpass]: " DB_PASSWORD
DB_PASSWORD=${DB_PASSWORD:-testpass}

read -rp "Project directory on server [/home/kitae/${PROJECT_NAME}]: " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-/home/kitae/${PROJECT_NAME}}

read -rp "Docker services to deploy (space-separated) [${PROJECT_NAME}-backend ${PROJECT_NAME}-frontend]: " SERVICES
SERVICES=${SERVICES:-${PROJECT_NAME}-backend ${PROJECT_NAME}-frontend}

read -rp "Self-hosted runner label [${PROJECT_NAME}-server]: " RUNNER_LABEL
RUNNER_LABEL=${RUNNER_LABEL:-${PROJECT_NAME}-server}

read -rp "Backend health URL [http://127.0.0.1:8384/health]: " BACKEND_HEALTH
BACKEND_HEALTH=${BACKEND_HEALTH:-http://127.0.0.1:8384/health}

read -rp "Frontend health URL [http://127.0.0.1:8383]: " FRONTEND_HEALTH
FRONTEND_HEALTH=${FRONTEND_HEALTH:-http://127.0.0.1:8383}

read -rp "Review language (ko/en) [ko]: " REVIEW_LANG
REVIEW_LANG=${REVIEW_LANG:-ko}

echo ""
echo "--- Generating workflow files ---"

mkdir -p .github/workflows

# CI (E2E tests)
cat > .github/workflows/ci.yml << EOF
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
      db-name: ${DB_NAME}
      db-user: ${DB_USER}
      db-password: ${DB_PASSWORD}
      backend-port: 4000
      frontend-port: 3000
    secrets:
      ANTHROPIC_API_KEY: \${{ secrets.ANTHROPIC_API_KEY }}
EOF

# AI Code Review
cat > .github/workflows/ai-review.yml << EOF
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
      language: ${REVIEW_LANG}
    secrets:
      ANTHROPIC_API_KEY: \${{ secrets.ANTHROPIC_API_KEY }}
EOF

# Deploy
cat > .github/workflows/deploy.yml << EOF
name: Deploy

on:
  pull_request:
    types: [closed]
    branches: [develop]
  workflow_dispatch:
    inputs:
      skip_tests:
        description: Skip post-deploy verification
        type: boolean
        default: false

concurrency:
  group: deploy-${PROJECT_NAME}
  cancel-in-progress: false

jobs:
  auto-deploy:
    if: github.event_name == 'pull_request' && github.event.pull_request.merged == true
    uses: kimkitae/ci-workflows/.github/workflows/deploy.yml@main
    with:
      project-dir: ${PROJECT_DIR}
      services: ${SERVICES}
      branch: develop
      runner-labels: '["self-hosted", "linux", "${RUNNER_LABEL}"]'
      backend-health-url: ${BACKEND_HEALTH}
      frontend-health-url: ${FRONTEND_HEALTH}
EOF

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Created:"
echo "  .github/workflows/ci.yml        - E2E tests on PR"
echo "  .github/workflows/ai-review.yml - AI code review on PR"
echo "  .github/workflows/deploy.yml    - Auto deploy on merge"
echo ""
echo "Required GitHub secrets:"
echo "  ANTHROPIC_API_KEY - for AI code review"
echo ""
echo "Next steps:"
echo "  1. git add .github/workflows/"
echo "  2. git commit -m 'ci: add CI/CD workflows'"
echo "  3. git push"
