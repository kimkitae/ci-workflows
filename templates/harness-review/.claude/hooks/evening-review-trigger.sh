#!/bin/bash
# Stop hook — auto-fires the AI-driven harness review every evening.
# Branches on day-of-week:
#   - Sunday  -> docs/weekly-review-prompt.md   (daily + 4 weekly sweeps)
#   - Mon-Sat -> docs/evening-review-prompt.md  (daily 5-step procedure)
#
# Trigger conditions (ALL must hold):
#   1. Local hour >= EVENING_REVIEW_HOUR (default 22)
#   2. Today's review hasn't run yet (sentinel file under .omc/logs/)
#   3. There are commits today (otherwise nothing happened to review)
#
# Failure-safe: any error path exits 0 (allows Stop). Only the success path
# with all conditions satisfied emits a decision:block JSON.
#
# Environment overrides:
#   EVENING_REVIEW_HOUR  threshold hour 0-23 (default 22)
#   EVENING_REVIEW_DIR   sentinel directory (default .omc/logs)

set +e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" 2>/dev/null || exit 0
[ -d .git ] || exit 0

# Avoid re-firing while we're already in a forced continuation
INPUT="$(cat 2>/dev/null || true)"
if echo "$INPUT" | grep -q '"stop_hook_active":[[:space:]]*true'; then
  exit 0
fi

THRESHOLD_HOUR="${EVENING_REVIEW_HOUR:-22}"
NOW_HOUR=$(date +%H)
NOW_HOUR=${NOW_HOUR#0}
[ -z "$NOW_HOUR" ] && NOW_HOUR=0

TODAY=$(date +%Y-%m-%d)
DOW=$(date +%w)            # 0 = Sunday
SENTINEL_DIR="${EVENING_REVIEW_DIR:-.omc/logs}"
SENTINEL="${SENTINEL_DIR}/evening-review.${TODAY}.done"

[ -f "$SENTINEL" ] && exit 0
[ "$NOW_HOUR" -lt "$THRESHOLD_HOUR" ] && exit 0

COMMITS_TODAY=$(git log --since="$TODAY 00:00" --oneline 2>/dev/null | wc -l | tr -d ' ')
if [ "${COMMITS_TODAY:-0}" -eq 0 ]; then
  mkdir -p "$SENTINEL_DIR"
  touch "$SENTINEL"
  exit 0
fi

if [ "$DOW" = "0" ]; then
  PLAYBOOK="docs/weekly-review-prompt.md"
  KIND="weekly"
else
  PLAYBOOK="docs/evening-review-prompt.md"
  KIND="evening"
fi

if [ ! -f "$PLAYBOOK" ]; then
  mkdir -p "$SENTINEL_DIR"
  echo "[evening-review-trigger] missing playbook $PLAYBOOK at $(date)" >> "$SENTINEL_DIR/trigger.errors.log"
  touch "$SENTINEL"
  exit 0
fi

mkdir -p "$SENTINEL_DIR"
touch "$SENTINEL"

cat <<JSON
{
  "decision": "block",
  "reason": "[evening-review-trigger] Auto-fired ${KIND} review for ${TODAY} (dow=${DOW}). ${COMMITS_TODAY} commit(s) today. Read ${PLAYBOOK} and execute it end-to-end. Edit docs/harness-log.md, CLAUDE.md, .claude/hooks/, .githooks/pre-commit, and tests/smoke/ directly per the playbook. Finish with the standard summary block and commit (chore: ${KIND} review ${TODAY}). After committing, you may stop — sentinel ${SENTINEL} prevents re-firing today."
}
JSON
exit 0
