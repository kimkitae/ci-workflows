#!/usr/bin/env node
// AI Code Review with auto-fix loop.
//
// Loop logic:
//   1. Fetch PR diff.
//   2. Send diff to Claude and ask for Korean verdict "평가: 수정 필요" or "평가: 수정 불필요".
//   3. If verdict is "수정 불필요" — post approval comment and exit.
//   4. If verdict is "수정 필요":
//        a. Send issues + full file contents to Claude, request JSON map of
//           { "path/to/file": "<new full file content>" }.
//        b. Apply the new contents, commit, push.
//        c. Increment iteration; re-run review with the new diff.
//   5. Stop after MAX_FIX_ITERATIONS iterations and post a warning comment.
//
// Required env:
//   ANTHROPIC_API_KEY    — Claude API key
//   GH_TOKEN             — github token with repo:write
//   PR_NUMBER            — pull request number
//   BASE_REF             — PR base branch (e.g. "develop")
//   HEAD_REF             — PR head branch (e.g. "feature/x")
//   MAX_FIX_ITERATIONS   — max auto-fix rounds (default: 3)
//   CLAUDE_MODEL         — model slug (default: claude-sonnet-4-5)

import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const {
  ANTHROPIC_API_KEY,
  GH_TOKEN,
  PR_NUMBER,
  BASE_REF,
  HEAD_REF,
  MAX_FIX_ITERATIONS = '3',
  MAX_DIFF_SIZE = '80000',
  CLAUDE_MODEL = 'claude-sonnet-4-5',
} = process.env;

if (!ANTHROPIC_API_KEY) die('ANTHROPIC_API_KEY missing');
if (!GH_TOKEN) die('GH_TOKEN missing');
if (!PR_NUMBER) die('PR_NUMBER missing');

const MAX_ITER = Math.max(1, parseInt(MAX_FIX_ITERATIONS, 10) || 3);
const DIFF_CHAR_LIMIT = Math.max(10_000, parseInt(MAX_DIFF_SIZE, 10) || 80_000);
const FILE_CHAR_LIMIT = 30_000; // per-file cap

function die(msg) {
  console.error(`[ai-review] ${msg}`);
  process.exit(1);
}

function sh(cmd, opts = {}) {
  return execSync(cmd, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'inherit'], ...opts }).trim();
}

function shQuiet(cmd) {
  try {
    return execSync(cmd, { encoding: 'utf8' }).trim();
  } catch (e) {
    return '';
  }
}

async function callClaude(systemPrompt, userPrompt, maxTokens = 4096) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: CLAUDE_MODEL,
      max_tokens: maxTokens,
      system: systemPrompt,
      messages: [{ role: 'user', content: userPrompt }],
    }),
  });
  const body = await res.text();
  if (!res.ok) {
    die(`Claude API ${res.status}: ${body.slice(0, 500)}`);
  }
  const data = JSON.parse(body);
  return data.content.map((c) => c.text || '').join('\n').trim();
}

function truncate(text, limit) {
  if (text.length <= limit) return text;
  return text.slice(0, limit) + `\n\n... [truncated, ${text.length - limit} more chars]`;
}

function getChangedFiles() {
  const out = shQuiet(`git diff --name-only origin/${BASE_REF}...HEAD`);
  return out
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean)
    .filter((f) => {
      // Skip binaries, lockfiles, large generated artifacts
      if (!existsSync(f)) return false;
      if (/\.(png|jpg|jpeg|gif|webp|ico|pdf|zip|tar|gz|lock)$/i.test(f)) return false;
      if (f.includes('package-lock.json') || f.includes('yarn.lock')) return false;
      return true;
    });
}

function getDiff() {
  // Compare current branch tip against PR base
  return shQuiet(`git diff origin/${BASE_REF}...HEAD`);
}

async function runReview(diff, iteration) {
  const system = `You are a senior code reviewer for a TypeScript / Next.js / Express codebase. Read the PR diff and produce a concise review in Korean.

YOU MUST START THE OUTPUT WITH THIS EXACT LINE:

평가: 수정 필요
  — or —
평가: 수정 불필요

Then, if "수정 필요", include two sections:

문제점:
1. \`<file>:<line>\` — <one-sentence description of the bug>
2. ...

제안사항:
1. <one-sentence concrete fix, mentioning the file/function>
2. ...

Rules:
- Flag ONLY real bugs, security issues, runtime errors, broken types, or regressions.
- Do NOT flag style preferences, hypothetical future concerns, or things the diff does not touch.
- Do NOT suggest architectural rewrites — stay scoped to the diff.
- Cap each section at 5 items.
- If the diff looks fine, output "평가: 수정 불필요" and a single sentence summary (no 문제점/제안사항 sections).`;

  const user = `Iteration ${iteration}/${MAX_ITER}.\n\nPR #${PR_NUMBER} diff (base=${BASE_REF}, head=${HEAD_REF}):\n\n${truncate(diff, DIFF_CHAR_LIMIT)}`;
  return await callClaude(system, user, 2048);
}

function parseVerdict(review) {
  // Match "평가: 수정 필요" or "평가: 수정 불필요"
  const match = review.match(/평가\s*[:\uFF1A]?\s*(수정\s*불필요|수정\s*필요)/);
  if (!match) return 'unknown';
  return match[1].includes('불필요') ? 'pass' : 'needs_fix';
}

async function generateFixes(review, changedFiles) {
  const truncatedFiles = [];

  const fileBlocks = changedFiles
    .map((f) => {
      try {
        const content = readFileSync(f, 'utf8');
        const wasTruncated = content.length > FILE_CHAR_LIMIT;
        if (wasTruncated) truncatedFiles.push(f);
        const displayed = wasTruncated
          ? truncate(content, FILE_CHAR_LIMIT)
          : content;
        const tag = wasTruncated ? ' [TRUNCATED — DO NOT MODIFY]' : '';
        return `=== FILE: ${f}${tag} ===\n${displayed}`;
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .join('\n\n');

  const truncatedNote = truncatedFiles.length > 0
    ? `\n- CRITICAL: The following files are marked [TRUNCATED — DO NOT MODIFY] because they exceed the context window. You MUST NOT include them in the output JSON — they can only be fixed manually: ${truncatedFiles.join(', ')}`
    : '';

  const system = `You are a code-fixing bot. Given a code review and the current file contents, output ONLY a JSON object mapping file paths to their NEW full content.

Format (STRICT):
{
  "path/to/file.tsx": "<full new file content as a single string>",
  "path/to/other.ts": "<...>"
}

Rules:
- Output ONLY the JSON object. No markdown fences, no prose, no comments.
- Only include files you actually need to modify.
- Each value must be the COMPLETE new file content, not a diff or a patch.
- Preserve everything you do not need to change — do not drop unrelated code.
- Keep TypeScript compiling.
- Do not introduce new dependencies.
- Do not rename files or move code between files.
- Escape newlines and quotes properly for valid JSON.${truncatedNote}`;

  const user = `Code review (issues to fix):\n${review}\n\nCurrent files:\n\n${fileBlocks}`;

  // Large max_tokens for full file replacements (big PRs need headroom)
  return await callClaude(system, user, 16384);
}

function extractJson(raw) {
  // Strip ```json fences if Claude ignored the instruction
  let s = raw.trim();
  if (s.startsWith('```')) {
    s = s.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/i, '').trim();
  }
  // Find first { and last }
  const start = s.indexOf('{');
  const end = s.lastIndexOf('}');
  if (start === -1 || end === -1 || end < start) {
    throw new Error(`No JSON object found in response:\n${s.slice(0, 500)}`);
  }
  return JSON.parse(s.slice(start, end + 1));
}

function applyFixes(fixMap) {
  const applied = [];
  for (const [path, newContent] of Object.entries(fixMap)) {
    if (typeof newContent !== 'string' || newContent.length === 0) {
      console.warn(`[ai-review] skipping ${path}: invalid content`);
      continue;
    }
    if (!existsSync(path)) {
      console.warn(`[ai-review] skipping ${path}: file not found`);
      continue;
    }
    // Safety guard: reject if new content is less than 50% of original length.
    // This catches the case where Claude received a truncated file and wrote
    // back only the portion it saw, silently deleting the rest.
    const original = readFileSync(path, 'utf8');
    if (newContent.length < original.length * 0.5) {
      console.warn(
        `[ai-review] skipping ${path}: new content (${newContent.length} chars) is ` +
        `less than 50% of original (${original.length} chars) — likely truncation damage`
      );
      continue;
    }
    writeFileSync(path, newContent);
    applied.push(path);
  }
  return applied;
}

function gitCommitAndPush(files, iteration) {
  sh('git config user.name "ai-reviewer[bot]"');
  sh('git config user.email "ai-reviewer@users.noreply.github.com"');
  for (const f of files) sh(`git add "${f}"`);
  // Bail if nothing actually changed
  const diff = shQuiet('git diff --cached --name-only');
  if (!diff) {
    console.log('[ai-review] no staged changes, skipping commit');
    return false;
  }
  sh(`git commit -m "fix: AI review auto-fix iteration ${iteration}"`);
  sh(`git push origin HEAD:${HEAD_REF}`);
  return true;
}

function postComment(body) {
  const escaped = body.replace(/"/g, '\\"').replace(/`/g, '\\`').replace(/\$/g, '\\$');
  try {
    execSync(`gh pr comment ${PR_NUMBER} --body "${escaped}"`, {
      env: { ...process.env, GH_TOKEN },
      stdio: 'inherit',
    });
  } catch (e) {
    console.error('[ai-review] failed to post comment');
  }
}

async function main() {
  console.log(`[ai-review] PR #${PR_NUMBER}, base=${BASE_REF}, head=${HEAD_REF}, max_iter=${MAX_ITER}`);

  for (let i = 1; i <= MAX_ITER; i++) {
    console.log(`\n=== Iteration ${i}/${MAX_ITER} ===`);

    const diff = getDiff();
    if (!diff) {
      console.log('[ai-review] empty diff — nothing to review');
      postComment(`🤖 AI Code Review: 변경사항 없음 (iteration ${i})`);
      return;
    }

    const review = await runReview(diff, i);
    console.log(review);
    const verdict = parseVerdict(review);
    console.log(`[ai-review] verdict = ${verdict}`);

    if (verdict === 'pass') {
      postComment(`🤖 AI Code Review: ✅ 수정 불필요 (iteration ${i}/${MAX_ITER})\n\n${review}`);
      console.log('[ai-review] approved — exiting');
      return;
    }

    if (verdict === 'unknown') {
      postComment(`⚠️ AI Code Review: 응답 파싱 실패 (iteration ${i})\n\n\`\`\`\n${review.slice(0, 800)}\n\`\`\``);
      die('could not parse verdict');
    }

    // needs_fix
    if (i === MAX_ITER) {
      postComment(`⚠️ AI Code Review: ${MAX_ITER}회 자동 수정 후에도 '수정 필요' — 수동 개입 필요\n\n최종 review:\n${review}`);
      die(`max iterations reached`);
    }

    const changedFiles = getChangedFiles();
    console.log(`[ai-review] generating fixes for ${changedFiles.length} file(s)`);
    if (changedFiles.length === 0) {
      postComment(`⚠️ AI Code Review: 변경된 파일을 찾지 못함 (iteration ${i})`);
      die('no changed files');
    }

    let fixMap;
    try {
      const raw = await generateFixes(review, changedFiles);
      fixMap = extractJson(raw);
    } catch (e) {
      // Graceful fallback: post the review comment and exit 0 instead of failing.
      // This happens when the diff is too large for Claude to produce full-file JSON
      // within the token limit (e.g., big PRs with 1000+ line changes).
      console.warn(`[ai-review] fix JSON parse failed: ${e.message}`);
      postComment(`🤖 AI Code Review (iteration ${i}) — '수정 필요' 감지, 자동 수정은 diff가 커서 실패\n\n${review}\n\n> 자동 수정 불가: ${String(e.message).slice(0, 200)}. 수동으로 위 제안사항을 반영해주세요.`);
      console.log('[ai-review] posted review comment, exiting gracefully');
      return;
    }

    const applied = applyFixes(fixMap);
    if (applied.length === 0) {
      postComment(`⚠️ AI Code Review: 적용할 수정사항 없음 (iteration ${i})\n\n${review}`);
      die('no fixes applied');
    }
    console.log(`[ai-review] applied fixes to: ${applied.join(', ')}`);

    const pushed = gitCommitAndPush(applied, i);
    if (!pushed) {
      postComment(`⚠️ AI Code Review: 수정 후 diff 없음 (iteration ${i}) — 루프 종료`);
      return;
    }

    postComment(`🤖 AI Code Review iteration ${i} — '수정 필요' 감지, 자동 수정 커밋\n\n${review}\n\n**수정된 파일**: ${applied.map((f) => `\`${f}\``).join(', ')}`);
  }
}

main().catch((e) => {
  console.error('[ai-review] unhandled error:', e);
  process.exit(1);
});
