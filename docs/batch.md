# 🤖 Work through many issues at once (`all`)

```text
/youtrack-task all [ID ...] [--max N] [--no-review] [--dry-run] [--auto-merge]
```

One command instead of briefing the agent by hand. Back to the
[README](../README.md) · [Usage](./usage.md) · [Troubleshooting](./troubleshooting.md).

```text
 triage ──▶ setup ──▶ work (parallel) ──▶ review ──▶ report ──▶ PRs ──▶ merge*
 you OK     worktree   one worker/issue    fresh      table     you OK   *only with
 once       per issue  TDD, local commits  reviewer   + overlap          --auto-merge
```

| # | Phase | What happens |
|:-:|-------|--------------|
| 1 | 🔍 **Triage** | Read-only. Each candidate is sorted into *ready*, *needs-human* or *blocked* and shown in one table. You confirm once. `--dry-run` stops here. |
| 2 | 🛠️ **Work** | Each ready issue gets its own worktree and its own `ticket-worker` agent (at most `--max`, default 3, at a time). |
| 3 | 🧪 **Independent review** | A fresh `ticket-reviewer` per issue checks the result. |
| 4 | 📊 **Report and PRs** | A table with verdicts, files touched and overlap warnings. After one more confirmation the main session pushes and opens the PRs; the issues move to Testing. |
| 5 | 🔀 **Merge** | Never, unless you pass `--auto-merge`. |

## Phase details

### 1. Triage

- **Candidates:** the IDs you name, else the issues matching `batch_query`. The query
  is limited to this repo's YouTrack project and read page by page.
- If nothing is *ready*, the table is all you get: no follow-up question.
- Issues are **never** run unattended when they are tagged `manual`, lack acceptance
  criteria, have open questions, are of architectural size, or touch servers /
  network / secrets / data stores.

### 2. Work

- Workers use TDD, commit locally in English, and never push, merge or write to
  YouTrack.
- A worker that hits ambiguity stops and reports a question instead of guessing.

### 3. Independent review

- It is the same review gate every task goes through. The reviewer sees only the
  issue, its acceptance criteria and the diff, never the worker's report or
  reasoning, and re-runs the tests itself.
- `CHANGES_REQUESTED` triggers a fix and a *new* reviewer, up to `review_rounds`
  (default 2). Then the issue is handed back to you.

### 4. Report and PRs

- Overlap warnings flag files changed by more than one issue, i.e. likely merge
  conflicts.
- Only issues that passed review qualify.

### 5. Merge

With `--auto-merge`, the run merges only PRs *it created* that meet all of these:

- the head commit is exactly the one the reviewer passed
- at least one required check exists and all checks are green
- the PR is `CLEAN`
- no file overlaps with another issue of the run

PRs are merged one by one, re-checking each time. The run never uses admin bypass,
never deletes remote branches, and leaves a PR open if the host refuses.
`--auto-merge` is refused together with `--no-review` or without subagent support,
since a merge needs an independent review.

> [!WARNING]
> `--auto-merge` lets the agent change your default branch. Use it only on
> repositories with branch protection (required checks / reviews) and a token that
> cannot force-push. Those server-side rules, not the plugin, are the real safety
> net.

---

## 🛡️ Guard hook

The plugin ships a `PreToolUse` hook that confines the worker and reviewer agents:

| Agent | Limits |
|-------|--------|
| both | No pushes, merges or PR creation. No network tools. No history rewriting such as `commit --amend` or `reset --hard`. |
| reviewer | Read-only. |
| worker | `Edit` / `Write` / `MultiEdit` may only touch files inside its worktree, never anything under `.git`. |

> [!NOTE]
> The hook needs `jq` and is a best-effort layer on top of the agents'
> instructions, not isolation. Interpreter one-liners (`python3 -c`, `node -e`) and
> package installs are not blocked, and tests the reviewer runs execute code of the
> branch under review. Server-side branch protection and a token without merge /
> force-push rights are the real boundary.

## 🔒 Enforce the review gate

> [!TIP]
> Want the gate enforced rather than just instructed? Set `review_gate_hook = "on"`
> in your config.

- The plugin's `require-review` hook then blocks `git push` and `gh pr create` for an
  issue branch (a branch whose name carries an issue ID) unless that exact commit
  has a review stamp. This also applies when you run them by hand or through `/ship`.
- `/youtrack-task pr --no-review` records a waiver and lets the push through.
- Default is `off`. It needs `jq` and is best effort.
- It cannot follow quoted or `$`-expanded push arguments and directories, so it
  rejects those: write the remote, refspecs and `cd` path out unquoted.
