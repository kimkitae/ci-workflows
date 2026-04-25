#!/usr/bin/env bash
#
# Harness Review Hooks installer — opt-in script for any repo using the
# general-harness layout (https://github.com/kimkitae/general-harness).
#
# Adds a Stop hook to .claude/settings.json and copies two AI playbooks:
#
#   .claude/hooks/evening-review-trigger.sh   — Stop hook (DOW-aware)
#   docs/evening-review-prompt.md             — daily 5-step playbook
#   docs/weekly-review-prompt.md              — Sunday weekly playbook
#
# After install:
#   - Mon-Sat after 22:00 local: when Claude finishes a turn and there is at
#     least one commit that day, the Stop hook blocks Stop with a
#     decision:block JSON and instructs Claude to run the daily review.
#   - Sunday after 22:00 local: same flow but uses the weekly playbook.
#   - Idempotent — sentinel under .omc/logs/ ensures one fire per day.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/kimkitae/ci-workflows/main/install/harness-review-hooks.sh | bash
#
#   # or from a local clone of ci-workflows:
#   bash /path/to/ci-workflows/install/harness-review-hooks.sh [target-project-path]
#
# Requirements:
#   - bash, git
#   - Project should already have CLAUDE.md, docs/harness-log.md (general-harness)
#   - jq is preferred for safe settings.json merging; falls back to manual edit

set -euo pipefail

color() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
info()  { color "36" "→ $1"; }
ok()    { color "32" "✓ $1"; }
warn()  { color "33" "⚠ $1"; }
error() { color "31" "✗ $1" >&2; }

TARGET_DIR="${1:-$(pwd)}"
cd "$TARGET_DIR" || { error "Cannot cd to $TARGET_DIR"; exit 1; }

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  error "$TARGET_DIR is not a git repository"
  exit 1
fi

info "Installing harness-review hooks into $(pwd)"

# ─── Source: prefer local clone, fallback to GitHub raw ─────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd 2>/dev/null || true)"
LOCAL_TPL="$SCRIPT_DIR/../templates/harness-review"
RAW_BASE="https://raw.githubusercontent.com/kimkitae/ci-workflows/main/templates/harness-review"

fetch() {
  # $1 = relative path inside templates/harness-review
  # $2 = destination
  if [[ -f "$LOCAL_TPL/$1" ]]; then
    cp "$LOCAL_TPL/$1" "$2"
  else
    curl -fsSL "$RAW_BASE/$1" -o "$2"
  fi
}

# ─── Copy hook + playbooks (skip if exist) ──────────────────────────────────
mkdir -p .claude/hooks docs

HOOK_DST=".claude/hooks/evening-review-trigger.sh"
DAILY_DST="docs/evening-review-prompt.md"
WEEKLY_DST="docs/weekly-review-prompt.md"

for pair in \
  ".claude/hooks/evening-review-trigger.sh|$HOOK_DST" \
  "docs/evening-review-prompt.md|$DAILY_DST" \
  "docs/weekly-review-prompt.md|$WEEKLY_DST"
do
  src="${pair%%|*}"
  dst="${pair##*|}"
  if [[ -f "$dst" ]]; then
    warn "$dst already exists — skipping (delete it first to re-install)"
  else
    fetch "$src" "$dst"
    ok "+ $dst"
  fi
done

chmod +x "$HOOK_DST"

# ─── Wire Stop hook into .claude/settings.json ──────────────────────────────
SETTINGS=".claude/settings.json"
HOOK_CMD='bash $CLAUDE_PROJECT_DIR/.claude/hooks/evening-review-trigger.sh'

if [[ ! -f "$SETTINGS" ]]; then
  cat > "$SETTINGS" <<JSON
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${HOOK_CMD}"
          }
        ]
      }
    ]
  }
}
JSON
  ok "+ $SETTINGS (created with Stop hook)"
elif command -v jq >/dev/null 2>&1; then
  if jq -e '.hooks.Stop[]?.hooks[]?.command | select(test("evening-review-trigger"))' "$SETTINGS" >/dev/null 2>&1; then
    info "Stop hook already wired — skipping"
  else
    tmp="$(mktemp)"
    jq --arg cmd "$HOOK_CMD" '
      .hooks //= {} |
      .hooks.Stop //= [] |
      .hooks.Stop += [{ "hooks": [{ "type": "command", "command": $cmd }] }]
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    ok "~ $SETTINGS (Stop hook appended)"
  fi
else
  warn "jq not found — please manually add this Stop hook entry to $SETTINGS:"
  cat <<JSON

  "Stop": [
    {
      "hooks": [
        { "type": "command", "command": "${HOOK_CMD}" }
      ]
    }
  ]

JSON
fi

# ─── .gitignore nudge for sentinel files ────────────────────────────────────
if [[ -f .gitignore ]] && ! grep -q '\.omc/logs' .gitignore 2>/dev/null; then
  warn "Add this line to .gitignore so sentinel files don't get committed:"
  echo
  echo "    .omc/logs/"
  echo
fi

ok "Installed harness-review hooks"
echo
info "Next steps:"
echo "  1. Make sure docs/harness-log.md exists (from general-harness install)"
echo "  2. The hook fires on Stop after 22:00 local (override: EVENING_REVIEW_HOUR=20)"
echo "  3. Sunday evenings switch to the weekly playbook automatically"
echo "  4. To force a review now, delete sentinel: rm .omc/logs/evening-review.\$(date +%F).done"
