# `/youtrack-task all` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `all` sub-command: parallel, worktree-isolated workers per issue, a fresh unbiased reviewer per result, optional `--auto-merge`.

**Architecture:** The main session orchestrates (subagents cannot spawn subagents) and performs every YouTrack write. Two plugin agents (`ticket-worker`, `ticket-reviewer`) are leaves. A plugin `PreToolUse` Bash hook keyed on `agent_type` enforces push/merge limits for those agents.

**Tech Stack:** Markdown skill + agent definitions, bash + jq hook, existing `scripts/*`.

**Spec:** `docs/superpowers/specs/2026-11-03-youtrack-task-all-design.md`

## Global Constraints

- Git artifacts English; YouTrack text in the user's language (SKILL.md "Language").
- Config keys: `batch_query` (default `for: me #Unresolved State: Open sort by: updated desc`), `batch_max_parallel` (3), `batch_skip_tags` (`["manual"]`), `batch_review_rounds` (2).
- Flags: `all [ID ...] [--max N] [--no-review] [--dry-run] [--auto-merge]`.
- Push only the issue's own branch, never forced; merge only with `--auto-merge`; never delete branches; never admin-bypass.
- Nothing instance-specific in the repo. Scripts: bash, `chmod +x`, safe by construction.
- Per `CLAUDE.md`: update README, CHANGELOG, SPEC, config.example.toml, tests/README, both version files (0.13.0), tag `v0.13.0`.

## Review Focus

- Hook input without `jq`, or without `agent_type` (main session) → passes (fail open).
- `git push origin HEAD:main`, `git push --force`, `git push origin +feat/X` from a worker → denied.
- `git push -u origin feat/ABC-1-slug` from a worker → allowed.
- `gh pr merge` from worker/reviewer → denied; from the main session → not the hook's business.
- Reviewer running `git commit`/`git push`/`rm` → denied; `git diff`, test runners → allowed.
- `all` with zero ready issues → prints triage table and stops without side effects.

---

### Task 1: Subagent guard hook

**Files:**
- Create: `hooks/guard-subagent` (executable)
- Modify: `hooks/hooks.json` (add a second `PreToolUse` entry, matcher `Bash`)

**Interfaces:**
- Consumes: hook stdin JSON with `agent_type`, `tool_name`, `tool_input.command`.
- Produces: exit 0 (allow) or exit 2 with an explanation on stderr.

- [ ] **Step 1: Write the test cases first** as a shell loop piping JSON into the not-yet-existing hook (run from repo root). Cases and expected exit codes: worker + `git push -u origin fix/ABC-1-x` → 0; worker + `git push --force origin fix/ABC-1-x` → 2; worker + `git push origin HEAD:main` → 2; worker + `git push origin +fix/ABC-1-x` → 2; worker + `gh pr merge 5` → 2; worker + `git commit --no-verify -m x` → 2; worker + `git branch -D x` → 2; reviewer + `git diff main...HEAD` → 0; reviewer + `git commit -m x` → 2; reviewer + `git push` → 2; no `agent_type` + `gh pr merge 5` → 0; malformed JSON → 0.
- [ ] **Step 2: Run them** and confirm they fail (hook missing).
- [ ] **Step 3: Implement `hooks/guard-subagent`** in the style of `hooks/require-assignee` (`set -u`, fail open without `jq` or on parse errors). `agent_type` is matched by suffix (`ticket-worker`, `ticket-reviewer`), because plugin agents are namespaced `youtrack-task:ticket-worker`. Worker allow-rule for `git push`: no `--force`/`-f`/`--force-with-lease`, no `+` refspec, no `main`/`master` target, and the pushed ref (explicit or current branch) matches `^[a-z]+/[A-Z][A-Z0-9_]+-[0-9]+-`. Reviewer deny-list: `git push|commit|add|reset|checkout|switch|merge|rebase|stash|clean`, `gh pr`, `rm`, output redirection into files.
- [ ] **Step 4: Register in `hooks/hooks.json`** (matcher `Bash`, command `bash "${CLAUDE_PLUGIN_ROOT}/hooks/guard-subagent"`), update the file's `description`, `chmod +x`.
- [ ] **Step 5: Re-run the cases; all pass.** Also run `claude plugin validate .` if available.
- [ ] **Step 6: Commit** `feat: add subagent guard hook for ticket workers and reviewers`.

### Task 2: Agent definitions

**Files:**
- Create: `agents/ticket-worker.md`, `agents/ticket-reviewer.md`

**Interfaces:**
- Produces: worker returns a report with first line `STATUS: DONE | BLOCKED | ESCALATE`, then `BRANCH`, `COMMITS`, `FILES`, `TESTS` (command + result), `PLAN` (short), `QUESTION` (when blocked). Reviewer returns `VERDICT: PASS | CHANGES_REQUESTED` then findings, each `file:line — problem — expected`.

- [ ] **Step 1: `ticket-worker.md`** — frontmatter `name: ticket-worker`, description, `tools: Read, Edit, Write, Bash, Grep, Glob`. Body: inputs it receives (issue text, acceptance criteria, absolute worktree path, branch, base); rules — work only under the worktree path, prefix every Bash command with `cd <worktree> &&` (the shell does not persist between calls), absolute paths for file tools; TDD; English commits without attribution trailers; push only the issue branch, plain; never merge, never touch YouTrack; never ask questions — return `BLOCKED`/`ESCALATE`; return the report format above.
- [ ] **Step 2: `ticket-reviewer.md`** — `tools: Read, Grep, Glob, Bash`. Body: inputs are issue text, acceptance criteria, base and worktree path only; it must derive its own picture from `git diff <base>...HEAD`, re-run the project's tests itself, check each acceptance criterion explicitly, never trust claims in commit messages; read-only; return the verdict format above.
- [ ] **Step 3: Validate** with the `plugin-dev:plugin-validator` agent; fix findings.
- [ ] **Step 4: Commit** `feat: add ticket-worker and ticket-reviewer agents`.

### Task 3: Orchestration contract

**Files:**
- Create: `skills/youtrack-task/reference/batch.md`

**Interfaces:**
- Consumes: Task 2 report formats; `scripts/setup-workspace` output keys (`MODE`, `NEXT_CD`, `BRANCH`, `BASE`, `DIR`).

- [ ] **Step 1: Write `batch.md`** covering, in order: triage rules and the table columns (`ID | summary | verdict | reason`); serial setup via `setup-workspace --mode worktree`; the worker briefing template (all inputs listed in Task 2); parallelism cap and background dispatch; the review loop (new reviewer each round, max `batch_review_rounds`, then hand to user); overlap detection (`git diff --name-only <base>...HEAD` per branch, intersect); YouTrack write-back (pickup comment, plan comment for audit, completion comment with verdict) done only by the main session; PR step (one confirmation listing all PRs, then the `pr` flow per issue); `--auto-merge` conditions from the spec with the exact `gh` checks (`gh pr checks`, `gh pr view --json mergeable,reviewDecision`, `gh pr merge --merge`, no `--admin`, no `--delete-branch`); resume behaviour (existing worktree → reuse); degradation without subagents (sequential, reviewer as clean-context pass).
- [ ] **Step 2: Commit** `docs: add batch orchestration contract`.

### Task 4: SKILL.md wiring

**Files:**
- Modify: `skills/youtrack-task/SKILL.md` (frontmatter description, Guardrails, Config table, Dispatch table, new `## all` section)

- [ ] **Step 1: Guardrails** — replace "Pushing and opening a PR happen only in the explicit `pr` sub-command" with: pushing the issue's own branch (plain) is allowed; opening PRs only in `pr` or in `all` after the single listed confirmation; merging only under `all --auto-merge`; force-push and branch deletion remain forbidden everywhere.
- [ ] **Step 2: Config table** — add the four `batch_*` keys with defaults.
- [ ] **Step 3: Dispatch table + `## all` section** — flag list, a numbered flow matching the spec, and a pointer to `reference/batch.md`. Add `all` to the frontmatter description's sub-command list.
- [ ] **Step 4: Verify** key names and sub-command names match `config.example.toml` and SPEC (grep both for each key).
- [ ] **Step 5: Commit** `feat: add all sub-command to the skill`.

### Task 5: Docs, config, tests, release

**Files:**
- Modify: `README.md`, `SPEC.md`, `config.example.toml`, `tests/README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

- [ ] **Step 1: `config.example.toml`** — document the four keys with defaults.
- [ ] **Step 2: `README.md`** — intro bullet, entry in *During and after the work*, a how-to section "Work through many issues at once" (flow, `--auto-merge` warning as `> [!WARNING]`), flags table, *Config overrides* + *What lives where*, *Troubleshooting* (worker blocked by hook, nothing ready in triage, plugin cache stale so `agents/` missing).
- [ ] **Step 3: `SPEC.md`** — command surface, flow, file tree (`agents/`, `hooks/guard-subagent`), config block.
- [ ] **Step 4: `tests/README.md`** — rows 24+ : `all --dry-run` table only; `all` with two ready issues → two worktrees, two workers, reviews, no pushes to default; manual-tagged issue → skipped; reviewer sees no worker report (inspect briefing); `CHANGES_REQUESTED` loop caps at 2; worker push of issue branch ok / force-push blocked (hook); `--auto-merge` merges only green+PASS PRs and never deletes branches; without the flag no merge; hook cases from Task 1.
- [ ] **Step 5: CHANGELOG 0.13.0** (newest first) and bump both version files to `0.13.0`.
- [ ] **Step 6: Consistency check** — grep each config key and `all` flag across SKILL.md, README, SPEC, config.example.toml; run `tools/package-agensi` and confirm `unzip -tq` is clean and the zip still has `SKILL.md` at the root (agents/hook are plugin-only; note this limitation in README *Troubleshooting* for the skill-only install).
- [ ] **Step 7: Commit** `docs: document all sub-command, config and tests`, then on a feature branch: PR, and after merge `git tag -a v0.13.0 -m "all sub-command"` and push the tag (merge and tag push only after the user confirms).

## Self-review

- Spec coverage: command/flags (T3, T4), triage/setup/work/review/report/PR/merge (T3), roles and tools (T2), enforcement hook (T1), config (T4, T5), guardrail changes (T4), degradation without subagents (T3), release checklist (T5).
- Names consistent: `ticket-worker`, `ticket-reviewer`, `guard-subagent`, `batch_*` keys, `--auto-merge`.
- Not planned (YAGNI): predicting file overlap before the run; hook check of Edit/Write paths against the worktree.
