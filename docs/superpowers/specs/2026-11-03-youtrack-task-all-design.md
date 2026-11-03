# Design: `/youtrack-task all` — batch processing with independent review

## Intent

The plugin handles one issue per run. With many open issues, the user has to
brief the agent by hand each time ("work through these tickets in parallel, use
a separate reviewer"). `all` turns that into one command: several issues are
implemented in parallel by isolated workers, each result is checked by a fresh,
unbiased reviewer, and the outcome is written back to YouTrack.

## Goals

- One command starts parallel work on several issues, each in its own worktree.
- Every result is reviewed by an agent that has not seen the worker's reasoning.
- Only issues that are safe to automate run unattended; the rest are surfaced.
- The user stays in control of risk: one triage confirmation up front; merging
  is off unless `--auto-merge` is passed.

## Non-goals

- No automation of host, network, firewall or secret-rotation work.
- No replacement of the interactive flow for architectural issues.
- No generic (non-YouTrack) orchestrator in this release. The orchestration
  rules live in `reference/batch.md` without YouTrack assumptions so they can
  be extracted later.

## Anti-goals (failure even if it "works")

- A worker or reviewer writes to YouTrack, pushes to the wrong branch, or merges.
- The reviewer inherits the worker's conclusions and rubber-stamps them.
- Two parallel workers silently overwrite each other.

## Command

```
/youtrack-task all [ID ...] [--max N] [--no-review] [--dry-run] [--auto-merge]
```

- `ID ...` — explicit issues; without them, `batch_query` selects candidates.
- `--max N` — parallel workers (default `batch_max_parallel`, 3).
- `--no-review` — skip the reviewer (not recommended).
- `--dry-run` — triage only; no workspace, no writes.
- `--auto-merge` — authorises the run to merge the PRs it opened (see Merge).

## Flow

1. **Triage (read-only).** Fetch candidates, classify each as *ready*,
   *needs-human* or *blocked*, print one table, ask for one confirmation. The
   table states whether `--auto-merge` is on.
   - *needs-human*: carries a tag from `batch_skip_tags` (default `manual`),
     has no acceptance criteria, has open questions, or looks architectural.
   - *blocked*: depends on an unresolved linked issue.
2. **Setup (serial).** Per ready issue: `scripts/setup-workspace --mode worktree`,
   then the normal pickup write-back. Serial avoids `index.lock` races.
3. **Work (parallel, background).** One `ticket-worker` per issue, at most
   `--max` at a time. It works only inside its worktree, uses TDD, commits
   locally in English, and may push its own issue branch. It never asks
   questions: it returns `BLOCKED:<question>` or `ESCALATE:architectural`.
4. **Review.** A fresh `ticket-reviewer` per issue. Input: issue title,
   description and acceptance criteria, and `git diff <base>...HEAD`. It does
   not receive the worker's report. It re-runs the tests itself and returns
   `PASS` or `CHANGES_REQUESTED` with findings. On `CHANGES_REQUESTED`, a new
   worker fixes, then a new reviewer reviews, up to `batch_review_rounds`
   (default 2); then the issue is handed to the user.
5. **Report.** Per issue: status, review verdict, files touched, overlap
   warnings (files changed by more than one issue in this run). Completion
   comments are written to YouTrack by the main session.
6. **PRs.** After one confirmation covering the whole list, open PRs through the
   existing `pr` flow (state moves to Testing).
7. **Merge (only with `--auto-merge`).** See below.

## Push and merge policy

- Pushing **the issue's own branch** (plain push, never forced) is allowed for
  workers and the main session. Pushing the default branch, any other branch, or
  using `--force` is never allowed.
- Without `--auto-merge`: no merging, as today.
- With `--auto-merge`, the main session may merge a PR only if all hold:
  it was opened by this run, review is `PASS`, required CI checks are green,
  the PR is mergeable without conflicts, no admin bypass is used. A merge that
  the host blocks is reported, never worked around. Branches are not deleted.
  Workers and reviewers never merge; only the main session does.

## Roles

| Role | Tools | Writes |
| --- | --- | --- |
| Main session (orchestrator) | all | YouTrack, PRs, merges |
| `ticket-worker` | Read, Edit, Write, Bash, Grep, Glob | its worktree; push of its own branch |
| `ticket-reviewer` | Read, Grep, Glob, Bash | nothing |

Subagents cannot spawn subagents, so orchestration stays in the main session.
All YouTrack writes happen there, which keeps the language and assignee rules
in one place.

## Enforcement

- `hooks/hooks.json` gets a `PreToolUse` Bash hook. Hook input carries
  `agent_type`/`agent_id`, so it can target workers and reviewers: deny force
  pushes, pushes to a branch other than the issue branch, `gh pr merge`, and
  (for reviewers) any write command.
- Subagents have no working-directory option. Workers receive the absolute
  worktree path and must use it for every file path and prefix shell commands
  with `cd <dir> &&` or use `git -C <dir>`.

## Configuration additions

| Key | Default |
| --- | --- |
| `batch_query` | `for: me #Unresolved State: Open sort by: updated desc` |
| `batch_max_parallel` | `3` |
| `batch_skip_tags` | `["manual"]` |
| `batch_review_rounds` | `2` |

## Guardrail changes (SKILL.md)

- Push: the issue's own branch is allowed in `all`; the rule against force-push
  and pushing elsewhere stays.
- Merge: allowed only under `--auto-merge` with the conditions above.
- PR confirmation may be a single confirmation listing all PRs.

## Decided by the user

- Command name `all`; push of the issue branch is allowed; `--auto-merge` flag
  exists and is opt-in per run.

## Decided by me (to be checked)

- Default parallelism 3; skip tag `manual`; two review rounds.
- Workers plan internally; the plan is posted as a comment for audit and the
  triage confirmation replaces per-issue plan approval.
- Overlap between issues is reported after the run, not predicted before it.

## Open points for the builder

- Spike result: a `cd` in one Bash call does not persist to the next call in a
  subagent (the shell returns to the session cwd). Workers therefore prefix
  every command with `cd <worktree> &&` (or use `git -C <worktree>`) and use
  absolute paths for file tools. The hook can additionally reject Edit/Write
  calls from `ticket-worker` whose path is outside its worktree.
- Exact stdin shape of the hook for the target tool names; verify with a test.
- Without subagent support (other agents), `all` degrades to sequential work in
  the main session with the reviewer step run as a clean-context pass.
