#!/usr/bin/env bash
#
# Deploy target bootstrap — run ONCE on the server that GitHub Actions
# deploys to (the host behind your DEPLOY_HOST secret).
#
# What it does (idempotent):
#   1. Clones <owner>/<repo> via SSH to ~/projects/<repo-name> (or DEPLOY_PATH)
#   2. Copies .env.example -> .env if .env doesn't already exist
#   3. Logs the docker daemon into ghcr.io so private images can be pulled
#   4. Validates docker-compose.prod.yml is parseable
#
# Pairs with the deploy.yml workflow that ships in
# https://github.com/kimkitae/ci-workflows — that workflow assumes the
# server already has the repo cloned and is logged into ghcr.io.
#
# Usage (run on the deploy target):
#
#   curl -sSL https://raw.githubusercontent.com/kimkitae/ci-workflows/main/install/deploy-server-bootstrap.sh \
#     | bash -s -- <owner>/<repo>
#
#   # or from a local clone:
#   bash install/deploy-server-bootstrap.sh <owner>/<repo>
#
# Environment overrides:
#   DEPLOY_PATH       target directory (default: ~/projects/<repo-name>)
#   COMPOSE_FILE      compose path inside repo (default: docker-compose.prod.yml)
#   GHCR_USER         ghcr.io username (default: prompt)
#   GHCR_PAT          ghcr.io PAT with read:packages (default: prompt, hidden)
#   SKIP_DOCKER_LOGIN  set to 1 if images are public

set -euo pipefail

color() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
info()  { color "36" "→ $1"; }
ok()    { color "32" "✓ $1"; }
warn()  { color "33" "⚠ $1"; }
error() { color "31" "✗ $1" >&2; }

REPO_SLUG="${1:-}"
if [[ -z "$REPO_SLUG" || "$REPO_SLUG" != */* ]]; then
  error "Usage: bash deploy-server-bootstrap.sh <owner>/<repo>"
  exit 1
fi
REPO_NAME="${REPO_SLUG##*/}"
TARGET="${DEPLOY_PATH:-$HOME/projects/$REPO_NAME}"
COMPOSE="${COMPOSE_FILE:-docker-compose.prod.yml}"

# ─── Sanity ─────────────────────────────────────────────────────────────────
for cmd in git docker; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "$cmd is required but not installed"
    exit 1
  fi
done

# ─── 1. Clone (idempotent) ──────────────────────────────────────────────────
info "Target directory: $TARGET"
if [[ -d "$TARGET/.git" ]]; then
  ok "Repo already cloned — fetching latest"
  git -C "$TARGET" fetch --quiet origin
else
  mkdir -p "$(dirname "$TARGET")"
  info "Cloning git@github.com:${REPO_SLUG}.git"
  if ! git clone --quiet "git@github.com:${REPO_SLUG}.git" "$TARGET"; then
    warn "SSH clone failed — falling back to HTTPS"
    git clone --quiet "https://github.com/${REPO_SLUG}.git" "$TARGET"
  fi
  ok "Cloned to $TARGET"
fi

cd "$TARGET"

# ─── 2. .env (don't overwrite) ──────────────────────────────────────────────
if [[ -f .env ]]; then
  ok ".env already present — leaving as-is"
elif [[ -f .env.example ]]; then
  cp .env.example .env
  warn "Copied .env.example -> .env"
  warn "  Edit values BEFORE first deploy: $TARGET/.env"
else
  warn "No .env.example in repo — create $TARGET/.env manually before deploy"
fi

# ─── 3. ghcr.io login ───────────────────────────────────────────────────────
if [[ "${SKIP_DOCKER_LOGIN:-0}" = "1" ]]; then
  info "SKIP_DOCKER_LOGIN=1 — assuming public images"
elif docker info 2>/dev/null | grep -q "ghcr.io"; then
  ok "Docker already logged into ghcr.io"
else
  info "Docker login to ghcr.io"
  GHCR_USER="${GHCR_USER:-${REPO_SLUG%%/*}}"
  if [[ -z "${GHCR_PAT:-}" ]]; then
    echo "  Create a token at: https://github.com/settings/tokens/new?scopes=read:packages"
    printf "  PAT for %s (input hidden): " "$GHCR_USER"
    stty -echo 2>/dev/null || true
    read -r GHCR_PAT
    stty echo 2>/dev/null || true
    echo
  fi
  if [[ -z "$GHCR_PAT" ]]; then
    warn "Empty PAT — skipping docker login (deploy will fail on private images)"
  else
    printf '%s' "$GHCR_PAT" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
    unset GHCR_PAT
    ok "Logged into ghcr.io as $GHCR_USER"
  fi
fi

# ─── 4. Compose validation ──────────────────────────────────────────────────
if [[ -f "$COMPOSE" ]]; then
  if docker compose -f "$COMPOSE" config --quiet; then
    ok "$COMPOSE parses cleanly"
  else
    error "$COMPOSE failed to parse — fix .env values before deploy"
    exit 1
  fi
else
  warn "$COMPOSE not found in repo — deploy will fail until it exists"
fi

# ─── Done ───────────────────────────────────────────────────────────────────
echo
ok "Deploy server bootstrap complete"
echo
info "Next steps:"
echo "  1. Edit $TARGET/.env with real Supabase / DB / JWT values"
echo "  2. From your dev machine, set GitHub secrets:"
echo "       gh secret set DEPLOY_HOST  --repo $REPO_SLUG --body \"<this server's public hostname>\""
echo "       gh secret set DEPLOY_USER  --repo $REPO_SLUG --body \"$(whoami)\""
echo "       gh secret set DEPLOY_PORT  --repo $REPO_SLUG --body \"22\"  # or your sshd port"
echo "       gh secret set DEPLOY_SSH_KEY --repo $REPO_SLUG < <path to private key>"
echo "  3. Push to main — deploy.yml fires automatically"
