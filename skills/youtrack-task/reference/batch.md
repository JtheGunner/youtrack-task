# Batch mode — `/youtrack-task all`

Work through several issues in one run: isolated workers in parallel, a fresh
reviewer per result, write-back to YouTrack, optional merging. Bound by the
**Guardrails** in `SKILL.md`.

> **Roles.** The main session orchestrates and performs **every** YouTrack write
> and every merge. `ticket-worker` and `ticket-reviewer` (plugin agents) are
> leaves: subagents cannot spawn subagents, and keeping the writes in one place
> keeps the language and assignee rules in one place. The plugin hook
> `hooks/guard-subagent` enforces the limits below for those two agents.

```
/youtrack-task all [ID ...] [--max N] [--no-review] [--dry-run] [--auto-merge]
```

## 1. Triage (read-only)

Candidates: the explicit `ID ...`, else `search_issues` with `batch_query`.
For each, `get_issue` (+ comments) and classify:

| Verdict | When |
| --- | --- |
| **ready** | has acceptance criteria, no open questions, bounded scope, none of the reasons below |
| **needs-human** | carries a tag in `batch_skip_tags` (default `manual`); no acceptance criteria; open questions; looks architectural; touches servers / network / secrets / data stores |
| **blocked** | linked to an unresolved issue it depends on |

Print one table — `ID | summary | verdict | reason` — plus the run settings
(`max`, review on/off, **auto-merge on/off**). `--dry-run` stops here, with no
workspace and no write. Otherwise ask **one** confirmation; the user may drop
rows. No ready issue → say so and stop. Only *ready* rows continue; the others
are listed again in the final report.

## 2. Setup (serial)

Per confirmed issue, one after another (parallel `git worktree add` races on
`index.lock`):

1. `scripts/setup-workspace --id <ID> --slug <slug> --prefix <prefix> --mode worktree`
   (slug and prefix per `reference/branching.md`). Keep `DIR`, `BRANCH`, `BASE`.
   `existing-worktree` / `existing-branch` → resume: reuse it, skip the pickup
   write-back.
2. Pickup write-back per `reference/writeback.md` (state → In Progress, pickup
   comment).

## 3. Work (parallel, background)

Dispatch one `ticket-worker` per issue, at most `--max` (default
`batch_max_parallel`) at a time, in the background; start the next as one
finishes. Briefing, verbatim sections: issue ID + title; description with its
acceptance criteria; absolute worktree path (`DIR`); branch; base; the reminder
that shell directory does not persist between calls.

Handle the report's `STATUS`:

| STATUS | Do |
| --- | --- |
| `DONE` | go to review |
| `BLOCKED` | post the question as a comment (user's language), mark the issue *needs-human* in the report, continue with the others |
| `ESCALATE` | same, noting the work looks architectural and belongs in `/youtrack-task <ID>` |

Post the worker's `PLAN` as the plan comment (template in `writeback.md`) for
audit — the triage confirmation replaces per-issue plan approval.

## 4. Review

Unless `--no-review`: for each `DONE` issue dispatch a **new** `ticket-reviewer`.
Its briefing holds only: issue ID + title, description with acceptance criteria,
the worktree path, the base. **Never include the worker's report, plan, commit
messages' claims or any of your own conclusions** — independence is the point.

- `PASS` → done reviewing.
- `CHANGES_REQUESTED` → dispatch a new `ticket-worker` with the original
  briefing plus the reviewer's `FINDINGS`, then a **new** reviewer. At most
  `batch_review_rounds` (default 2) rounds; still failing → the issue goes to
  the user as *needs-human* with the open findings. Never loop silently.

## 5. Report

Per issue: ID, final status (`PASS` / `needs-human` / `blocked`), review rounds,
branch, files touched, tests run. **Overlap:** for every pair of branches
intersect `git diff --name-only <base>...<branch>`; list shared files as a
merge-conflict warning. Post one completion comment per issue (template in
`writeback.md`, including the verdict). Do not move issue states here — `pr`
moves to Testing.

## 6. Pull requests

Show the list of PASS issues (branch, commits, diffstat) and ask **one**
confirmation covering all of them. Then run the `pr` flow's steps 4–7 for each
(plain push of the issue branch, `gh pr create`, PR comment, → Testing). Existing
PRs are reused. Without confirmation, stop here and say how to continue
(`/youtrack-task pr <ID>` per issue).

## 7. Merge — only with `--auto-merge`

Without the flag: never merge; tell the user the PRs are ready.

With the flag the main session (never a worker or reviewer) may merge a PR only
if **all** hold, checked fresh immediately before each merge:

- the PR was opened or reused by this run, and its issue is `PASS`;
- `gh pr checks <n>` shows all required checks passing (none pending or failed);
- `gh pr view <n> --json mergeable,mergeStateStatus,reviewDecision` says
  mergeable and not blocked or changes-requested;
- merge with plain `gh pr merge <n> --merge` — **no** `--admin`, **no**
  `--delete-branch`, no force. If the host refuses (branch protection, required
  review), report it and leave the PR open; never work around it.

Merge sequentially. After each merge, re-check the remaining PRs (a merge can
make the next one conflict); a PR that turned unmergeable is reported, not
forced. Afterwards `git fetch` and run `scripts/sweep-worktrees`; then offer
`/youtrack-task done <ID>` per merged issue (state changes stay explicit).

## Without subagent support

If the agent cannot dispatch subagents: process the ready issues one at a time
in the main session through the normal primary flow's step 8, and run the review
as a separate clean-context pass (re-read the issue and the diff only; ignore
your own earlier reasoning). Say that the review is weaker than with a separate
agent.

## Language

Same contract as `SKILL.md`: git artifacts English (workers and reviewers are
told so); every comment this flow writes to YouTrack follows the issue's
language.
