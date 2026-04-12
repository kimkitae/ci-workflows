#!/usr/bin/env bash
#
# AI Code Review installer — opt-in script for any repo.
#
# Adds a 25-line stub workflow at .github/workflows/ai-review.yml that
# calls kimkitae/ci-workflows/.github/workflows/ai-review.yml@main.
#
# On every PR to develop/main the caller's repo will run an auto-fixing
# Claude code review loop (max 3 iterations by default).
#
# Usage — run inside any git repo that has a GitHub remote:
#
#   curl -sSL https://raw.githubusercontent.com/kimkitae/ci-workflows/main/install/ai-review.sh | bash
#
#   # or from a local clone of ci-workflows:
#   bash /path/to/ci-workflows/install/ai-review.sh [target-project-path]
#
# The installer:
#   1. Creates a new branch  chore/add-ai-review-<timestamp>
#   2. Writes the stub workflow file
#   3. Checks whether ANTHROPIC_API_KEY is already set as a repo secret
#        - If missing, offers to set it now (stdin prompt, not stored to disk)
#        - If you decline, the stub is still created but the first run will
#          fail with "ANTHROPIC_API_KEY missing" until you set it manually:
#            gh secret set ANTHROPIC_API_KEY --repo <owner/repo>
#   4. Commits, pushes, and opens a PR
#   5. STOPS — does NOT merge the PR. The user must merge it manually.
#
# Opt-out:
#   - Don't run the installer, or
#   - If already installed, delete .github/workflows/ai-review.yml and push.
#
# Requirements:
#   - bash, git, gh CLI (authenticated)
#   - Target repo must have a GitHub remote

set -euo pipefail

TARGET_DIR="${1:-$(pwd)}"

color() {
  # $1 = color code, $2 = message
  printf '\033[%sm%s\033[0m\n' "$1" "$2"
}
info()  { color "36" "→ $1"; }
ok()    { color "32" "✓ $1"; }
warn()  { color "33" "⚠ $1"; }
error() { color "31" "✗ $1" >&2; }

cd "$TARGET_DIR" || { error "Cannot cd to $TARGET_DIR"; exit 1; }

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  error "$TARGET_DIR is not a git repo"
  exit 1
fi

# Resolve repo slug via gh (fails if no GitHub remote or gh not auth'd)
REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
if [[ -z "$REPO_SLUG" ]]; then
  error "gh could not resolve the GitHub repo for $TARGET_DIR"
  error "Make sure 'gh auth status' is OK and the repo has a GitHub remote."
  exit 1
fi

info "Installing AI Code Review on $REPO_SLUG"

# ─── Guard: stub already exists ─────────────────────────────────────────────
STUB_PATH=".github/workflows/ai-review.yml"
if [[ -f "$STUB_PATH" ]]; then
  warn "$STUB_PATH already exists in this repo"
  read -r -p "Overwrite with the current stub? [y/N] " ans
  if [[ "${ans:-N}" != "y" && "${ans:-N}" != "Y" ]]; then
    info "Aborted — no changes made"
    exit 0
  fi
fi

# ─── Guard: working tree clean ──────────────────────────────────────────────
if [[ -n "$(git status --porcelain)" ]]; then
  warn "Working tree has uncommitted changes. Stash them first."
  git status --short
  exit 1
fi

# ─── Check ANTHROPIC_API_KEY secret ────────────────────────────────────────
info "Checking ANTHROPIC_API_KEY secret on $REPO_SLUG"
if gh secret list --repo "$REPO_SLUG" 2>/dev/null | awk '{print $1}' | grep -qx 'ANTHROPIC_API_KEY'; then
  ok "ANTHROPIC_API_KEY already set"
else
  warn "ANTHROPIC_API_KEY is NOT set on $REPO_SLUG"
  echo "  Enter the key now (input hidden) — or leave empty to skip and add later."
  printf "  ANTHROPIC_API_KEY: "
  # -s = silent (hide input)
  stty -echo 2>/dev/null || true
  read -r API_KEY || true
  stty echo 2>/dev/null || true
  echo
  if [[ -n "${API_KEY:-}" ]]; then
    printf '%s' "$API_KEY" | gh secret set ANTHROPIC_API_KEY --repo "$REPO_SLUG"
    ok "ANTHROPIC_API_KEY set on $REPO_SLUG"
    unset API_KEY
  else
    warn "Skipped — the workflow will fail on first run until you run:"
    echo "    gh secret set ANTHROPIC_API_KEY --repo $REPO_SLUG"
  fi
fi

# ─── Branch + stub + commit + push + PR ────────────────────────────────────
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
BASE_BRANCH="${AI_REVIEW_BASE_BRANCH:-$DEFAULT_BRANCH}"
# Prefer develop if it exists and caller did not override
if [[ "$BASE_BRANCH" == "$DEFAULT_BRANCH" ]] && git show-ref --verify --quiet refs/remotes/origin/develop; then
  BASE_BRANCH="develop"
fi

info "Base branch: $BASE_BRANCH"

TS=$(date +%s)
NEW_BRANCH="chore/add-ai-review-$TS"

git fetch origin "$BASE_BRANCH" --quiet
git checkout -b "$NEW_BRANCH" "origin/$BASE_BRANCH"

mkdir -p .github/workflows
cat > "$STUB_PATH" <<'YAML'
name: AI Code Review

# Auto-fix Claude code review for every PR to develop/main.
# Calls the reusable workflow from kimkitae/ci-workflows.

on:
  pull_request:
    types: [opened, synchronize]
    branches: [develop, main]

permissions:
  pull-requests: write
  contents: write
  issues: write

concurrency:
  group: ai-review-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  review:
    uses: kimkitae/ci-workflows/.github/workflows/ai-review.yml@main
    with:
      language: ko
      model: claude-sonnet-4-5
      max_iterations: 3
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
YAML

git add "$STUB_PATH"

if git diff --cached --quiet; then
  warn "Stub matches what is already on this branch — nothing to commit"
  git checkout - > /dev/null 2>&1 || true
  git branch -D "$NEW_BRANCH" > /dev/null 2>&1 || true
  exit 0
fi

git commit -m "chore(ci): add AI Code Review auto-fix workflow

Uses the reusable workflow from kimkitae/ci-workflows. On every PR
to develop/main, Claude reviews the diff and if the verdict is
'평가: 수정 필요' the workflow auto-commits fixes back to the PR
branch (max 3 iterations)." > /dev/null

info "Pushing $NEW_BRANCH"
git push -u origin "$NEW_BRANCH" --quiet

info "Opening PR"
PR_URL=$(gh pr create \
  --repo "$REPO_SLUG" \
  --base "$BASE_BRANCH" \
  --head "$NEW_BRANCH" \
  --title "chore(ci): add AI Code Review auto-fix workflow" \
  --body "Adds the reusable AI review workflow from kimkitae/ci-workflows.

On every PR to develop/main:
1. Claude reviews the diff
2. If verdict is '평가: 수정 필요', Claude auto-commits fixes back to the PR branch
3. Loops up to 3 iterations, then posts a summary comment

Disable by deleting \`.github/workflows/ai-review.yml\`.")

ok "Done"
echo "  PR: $PR_URL"
echo
info "Next steps:"
echo "  1. Review the PR above"
echo "  2. Merge it manually (auto-merge is intentionally disabled)"
echo "  3. From then on, every PR to develop/main triggers the auto-fix review"
