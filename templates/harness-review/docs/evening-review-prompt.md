# Evening Harness Review — AI Playbook

> **You are the harness reviewer.** Run this every evening (auto-triggered by
> `.claude/hooks/evening-review-trigger.sh` Stop hook on Mon-Sat after 22:00).
> Your job: convert today's friction into permanent harness improvements —
> directly editing `docs/harness-log.md`, `CLAUDE.md`, and `.claude/hooks/`.
>
> **Mandate**: edit files. Don't propose. Stop only when work is done or there
> is genuinely nothing to journal.

---

## Inputs to read in order

1. **Today's commits + diff stats**
   ```
   git log --since="$(date +%Y-%m-%d) 00:00" --oneline
   git log --since="$(date +%Y-%m-%d) 00:00" --pretty=tformat: --numstat
   ```
2. **Recent agent transcripts / your own session** — what got walked back, redone, or hot-fixed today?
3. **`docs/harness-log.md`** — current journal + open-patterns watch list
4. **`CLAUDE.md`** — current rules (forbidden patterns, critical paths)
5. **`.claude/hooks/*.sh`** — current automated guards

---

## The 5-step procedure

### Step 1 — Identify misfires

Look for evidence in today's git log + your conversation memory:

- Reverts, force-pushes, `--amend`, or "fix:" commits chasing earlier "feat:" commits in the same day
- Manual workarounds that bypassed the standard flow defined in CLAUDE.md
- Schema or contract drift between layers (DB / API / client)
- Direct cross-layer calls that skip the documented service boundary
- Missing API doc / type annotations on a newly exposed surface
- Hard delete where soft delete is required
- Any change shipped without an impact-range report
- Smoke test newly broken or skipped
- Pre-commit hook bypassed with `--no-verify`
- Anything that confused you for >5 minutes (root cause: which guard would have prevented this?)

If you find none → write a 1-line "Quiet day" entry in `docs/harness-log.md` and skip to Step 5.

### Step 2 — Journal each misfire

Append to `docs/harness-log.md` under today's date heading. Format:

```
### YYYY-MM-DD — <one-line symptom>

- **Symptom**: what went visibly wrong
- **Root cause**: the underlying mistake
- **Action**: what you did or what guard would catch it next time
- **Pattern bucket**: <name> (use existing bucket if same kind happened before)
```

### Step 3 — Promote when threshold hit

Use the **>= 2 of 3** decision rule from `CLAUDE.md` (Steering Loop):
- Same mistake repeated >= 2 times
- Cost is high (prod outage, data loss, secret leak, API bill)
- Rule fits in one line / one paragraph

| Already in | Hits today | Action |
|------------|-----------|--------|
| Nowhere    | 1st time  | Just journal in `harness-log.md` |
| `harness-log.md` | 2nd time | **Add to `CLAUDE.md` Forbidden Patterns** |
| `CLAUDE.md` | Still happening | **Write a `.claude/hooks/<name>.sh` sensor** that emits `permissionDecision: deny` on the offending pattern; register it in `.claude/settings.json` |
| `.claude/hooks/` | Still bypassed | **Move enforcement into `.githooks/pre-commit`** so the commit can't land |
| `.githooks/pre-commit` | Still bypassed in CI | **Add a GitHub Actions check** as the final gate |

When promoting, **demote** any guard that hasn't fired in 6 months — read git log on `.claude/hooks/` and `CLAUDE.md` line history to check.

### Step 4 — Update critical paths if needed

If today's work created or moved a critical path (new endpoint, new file owner, new smoke test), update the **Critical Paths** table in `CLAUDE.md`. Add a smoke test stub under `tests/smoke/` if one is missing.

### Step 5 — Commit

```
git add docs/harness-log.md CLAUDE.md .claude/hooks .githooks tests/smoke
git commit -m "chore: evening review YYYY-MM-DD

<bullet summary of changes — one line per change>"
```

Push only if the user said so. Otherwise leave the commit local.

---

## Output to user (always end with this block)

```
=== Evening review YYYY-MM-DD ===
Misfires found:    <N>
Journaled:         <N entries in harness-log.md>
Promoted to rules: <N changes to CLAUDE.md>
Promoted to hooks: <N hook files>
Promoted to gate:  <0|1>
Demoted:           <list of removed/relaxed guards>
Commit:            <sha or "none — nothing to record">
Tomorrow's watch:  <1-2 patterns at threshold-1>
```

If you skipped a step because there was nothing to do, say so explicitly — "Step 3: nothing crossed threshold today."

---

## Hard rules for this review

- **Edit files. Don't propose.** You have Write/Edit. Use them.
- **Quote evidence** for every promotion ("happened in commit X and Y").
- **Don't invent misfires.** No misfires today is a valid result.
- **Don't touch unrelated code.** Only `docs/harness-log.md`, `CLAUDE.md`, `.claude/hooks/`, `.githooks/pre-commit`, `tests/smoke/`.
- **Respect Commit Policy** in `CLAUDE.md`: explicit paths, no `git add .`, no `--no-verify`, never push without instruction.
- **Don't hit Step 3 promotion on a single occurrence.** Threshold is real. Patience.
