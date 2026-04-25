# Weekly Harness Review — AI Playbook (Sunday only)

> **You are the weekly harness reviewer.** Auto-fires Sunday evenings via the
> Stop hook in `.claude/hooks/evening-review-trigger.sh`. This playbook is a
> **superset** of `docs/evening-review-prompt.md` — do everything daily would
> do, then add the 4 weekly-only sweeps below.
>
> **Mandate**: edit files directly. Don't ask. Stop only when the work is done.

---

## Inputs (in addition to daily inputs)

1. **Last 7 days of commits**
   ```
   git log --since="7 days ago" --oneline
   git log --since="7 days ago" --pretty=tformat: --numstat
   ```
2. **All `harness-log.md` entries from the last 7 days**
3. **Hook fire frequency** (proxy: git log on `.claude/hooks/`)
4. **CLAUDE.md current line count** (`wc -l CLAUDE.md`)

---

## Procedure

### Phase 1 — Run the daily review first

Execute every step in `docs/evening-review-prompt.md` (steps 1-5). Identify and record today's misfires before doing anything weekly.

### Phase 2 — Weekly aggregation (4 sweeps)

#### Sweep A — Pattern aggregation
Read every `harness-log.md` entry from the last 7 days. Group by **Pattern bucket**. For each bucket:

- Hit >= 2 times this week and not yet in CLAUDE.md → **promote to CLAUDE.md Forbidden Patterns** with a one-line rule.
- Already in CLAUDE.md and still hit >= 2 times → **promote to `.claude/hooks/<name>.sh`** (real sensor, emits `permissionDecision: deny`). Register in `.claude/settings.json`.
- Already in `.claude/hooks/` and still bypassed → **promote to `.githooks/pre-commit`**.

Star the top 1-2 buckets that crossed a threshold. Write the promotion in this commit.

#### Sweep B — Hook demotion
For every file in `.claude/hooks/`:

- Run `git log --since="6 months ago" --diff-filter=A -- .claude/hooks/<file>` — was it added more than 6 months ago?
- Search `harness-log.md` for any mention of the rule it enforces.
- If older than 6 months **and** never journaled as the catching guard → **demote**:
  - Move enforcement back into `CLAUDE.md` as a soft rule, OR
  - Delete the hook file entirely if the underlying risk is gone.
- Update `.claude/settings.json` if you removed a hook.

Demoting is a feature, not damage. The harness shrinks too.

#### Sweep C — CLAUDE.md prune
- `wc -l CLAUDE.md`. If > 200 lines → identify the 3 oldest / least-cited rules.
- For each: search 6 months of `harness-log.md` for that rule's name. Zero hits → delete it.
- If > 300 lines and you can't find 3 to cut, flag it in the summary as a structural problem (split into modules under `docs/harness/`).

#### Sweep D — Critical paths sanity
- Re-read the Critical Paths table in `CLAUDE.md`.
- For each row: does the smoke test file actually exist under `tests/smoke/`?
- For any row missing a smoke test: add a stub (xtest or `it.skip` with a clear TODO) so the table doesn't lie.
- For any smoke test referencing a deleted file: remove the row.

### Phase 3 — Commit

Bundle daily + weekly changes into one commit:

```
git add docs/harness-log.md CLAUDE.md .claude/hooks .claude/settings.json .githooks tests/smoke
git commit -m "chore: weekly review YYYY-MM-DD

Daily:
- <bullets from daily phase>

Weekly:
- Promoted: <pattern -> layer>
- Demoted:  <hook -> reason>
- Pruned:   <N lines off CLAUDE.md>
- Critical paths: <added/removed/renamed>"
```

### Phase 4 — Output to user

End with **both** the daily summary block **and** this weekly block:

```
=== Weekly review YYYY-MM-DD (Sunday) ===
Patterns promoted:   <N> (CLAUDE.md / hooks / pre-commit / CI)
Hooks demoted:       <N> (list)
CLAUDE.md size:      <before> -> <after> lines
Critical paths:      <count> rows, <N> with smoke / <N> without
Top 2 watch buckets: <pattern A>, <pattern B>
Next Sunday focus:   <one sentence>
```

---

## Hard rules (strict)

- **Never promote on a single occurrence.** Threshold is 2.
- **Never demote a hook younger than 6 months** even if it never fired — it's an insurance policy, not unused code.
- **Don't touch unrelated code.** Only `docs/harness-log.md`, `CLAUDE.md`, `.claude/`, `.githooks/`, `tests/smoke/`.
- **Respect Commit Policy** in `CLAUDE.md`: explicit paths, no `git add .`, no `--no-verify`, no push without instruction.
- **If you cut a rule, write the cut into the commit message.** "Removed forbidden-pattern row 'X' — last journaled 8 months ago."
