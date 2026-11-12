# 🚀 Usage

Everyday workflows in detail. For the quick tour see the [README](../README.md);
for the batch command see [`batch.md`](./batch.md).

**On this page:** [Pick up an issue](#-pick-up-an-issue) ·
[Create an issue](#-create-an-issue) ·
[Work in parallel](#-work-several-tasks-in-parallel) ·
[During and after the work](#-during-and-after-the-work) ·
[Full lifecycle](#-the-full-lifecycle)

---

## 🌿 Pick up an issue

```text
/youtrack-task                 # lists your Open / In Progress issues, you pick one
/youtrack-task INFRA-42        # go straight to that issue
```

Before anything else, `scripts/read-config` resolves your `config.toml` with all
defaults. A setting such as `confirm_branch_name = false` is therefore applied every
time. The other scripts and the review-gate hook read their settings through the
same script, so all of them see the same value for a key. Keys under a `[table]`
such as `[type_prefix]` are ignored by all of them.

| # | Step | What happens |
|:-:|------|--------------|
| 1 | **Fetch** | Pulls the issue (summary, description, type, priority, state, subsystem) and its comments, then shows a short brief. |
| 2 | **Sanity check** | Verifies you are in a git repo that roughly matches the issue's YouTrack project. Warns, never blocks. |
| 3 | **Workspace** | `scripts/setup-workspace` decides worktree vs. in place and creates the branch `‹prefix›/‹ID›-‹slug›` from the current tip of your default branch. |
| 4 | **In Progress** | Moves the issue to *In Progress* (unless it is already there or further) and comments *📌 Picked up in Claude Code — branch `…`*. |
| 5 | **Plan** | Explores the repo and drafts a plan; you review and iterate until it is right. |
| 6 | **Write back the plan** | After your approval the plan is posted as a Markdown comment *📝 Implementation plan (Claude Code)*. |
| 7 | **Implement** *(only with `--implement`)* | Implements the plan, runs the review gate, posts the completion comment and stops before push. |

Details behind the steps:

- **Branch name.** The prefix comes from the issue Type: `Bug→fix`, `Feature→feat`,
  `Task→chore`, `Epic→feat`, `Cosmetics→style`, else `chore`. Example:
  `chore/INFRA-42-rotate-vault-unseal-keys`. The slug is always English, even when
  the issue is not.
- **Dirty tree.** The skill asks whether to stash or carry the changes onto the
  branch. An existing branch or worktree is resumed, not recreated.
- **Planning.** With the [`superpowers`](https://github.com/obra/superpowers) plugin
  installed, planning runs through it (`brainstorming`, or `systematic-debugging`
  for bugs, then `writing-plans` for larger work). Otherwise a plain plan-mode pass.
- **Plan copy.** If the repo has a `docs/` directory, a copy is saved to
  `docs/plans/‹ID›.md`. It is always English, like every git artifact; the YouTrack
  comment follows the issue's language.
- **Resume.** Resuming an existing worktree checks the issue's comments first: a plan
  comment that is already there is reused, not posted again.
- **Implementation (step 7).** With `superpowers`: `test-driven-development`
  throughout, `subagent-driven-development` (or `executing-plans` with
  `--checkpoints`) for a written plan, and `verification-before-completion` against
  the acceptance criteria. Without it: the normal dev workflow.
- **Review gate.** Either way the work goes through a fresh, independent
  `ticket-reviewer` subagent that never sees your session's reasoning. A `PASS` is
  stamped on that exact commit. The completion comment is posted next, and
  `/youtrack-task pr` is the following step. The reviewer is read-only and runs an
  allowlist; a command it needs but may not run ends the gate as `BLOCKED`, not as a
  code finding (see [Configuration](configuration.md#letting-the-reviewer-run-more)).

### Flags

| Flag | Effect |
|------|--------|
| `--no-move` | Don't change the issue state; still add the pickup comment. |
| `--no-writeback` | Don't change state and don't add the pickup comment. |
| `--base ‹branch›` | Branch from `‹branch›` instead of the detected default. |
| `--worktree` / `--no-worktree` | Force / skip an isolated git worktree for this pickup (default: `worktree` config, itself `auto`). |
| `--confirm-branch` / `--no-confirm-branch` | Ask / don't ask whether the computed branch name is OK. With `--no-confirm-branch` the name is accepted and just shown (default: `confirm_branch_name` config, itself `true`). |
| `--implement` | Run step 7 after the plan is written back. Without it the flow ends once the plan is on the issue and prints the command to continue. On an existing worktree it carries on from the plan comment already there. |
| `--checkpoints` | Execute an architectural plan with review stops after each phase (`superpowers:executing-plans`) instead of one continuous run. |
| `--confirm-pr` / `--no-confirm-pr` | `pr` only: ask / don't ask "push and open a PR?" (default: `confirm_pr` config, itself `true`; the flag wins). The commits and diffstat are still shown and the review gate still applies. |
| `--no-review` | Skip the review gate for this run. `pr` then asks before pushing and labels the PR *Review: skipped*. Default: every task with commits is reviewed; `--review` is accepted and does nothing. |

---

## 📝 Create an issue

```text
/youtrack-task new "hover on tinted rows loses the colour, needs a same-hue hover instead"
/youtrack-task new                     # interactive: free text, or field by field
/youtrack-task new --project ADMIN --title "..." --description "..." --priority Major --type Bug
/youtrack-task new "..." --assignee max.muster   # assign someone else (login or email)
```

**Free-text mode** (first form): give one blob of text. Claude generates the title
and a **structured description**: Summary / Context / Goal / Acceptance criteria /
Scope / Technical notes / Open questions. A later `/youtrack-task <id>` reads the
same structure back to build its plan, so nothing is lost between capturing and
working the task.

| Field | Behaviour |
|-------|-----------|
| **Language** | Title and description follow the language of your text (German in → German out). An explicit `--title` is used as given. The confirm step shows a `Language:` line; say "English" there to regenerate in English. |
| **Project** | Required. `--project` defaults to the YouTrack project matching the current repo. |
| **Title, description** | Required, generated in free-text mode. You review and edit them before the issue is created. |
| **Priority** | Optional. Project default otherwise; proposed automatically only if the text says "blocker" / "asap" / etc. |
| **Type** | Inferred from the content and shown for confirmation when you don't pass `--type`. |
| **Assignee** | The owner of your API token by default. `--assignee ‹login\|email›`, or an explicit "assign to …" / "für …" in the free text, assigns someone else. |

If the requested assignee doesn't exist, the issue falls back to you and the
confirmation step flags it (`⚠ max.musterr not found → API-key owner`). You can still
correct it before anything is created. After creating, Claude offers to pick the
issue up.

---

## 🌲 Work several tasks in parallel

Put `worktree = "always"` in `~/.config/youtrack-task/config.toml` (or pass
`--worktree` each time). Every pickup then lands in its own **isolated git
worktree**:

```text
# terminal 1
cd ~/projects/admin-dashboard-vue && claude
> /youtrack-task ADMIN-1        # → .worktrees/ADMIN-1-…  on feat/ADMIN-1-…

# terminal 2, at the same time
cd ~/projects/admin-dashboard-vue && claude
> /youtrack-task ADMIN-6        # → .worktrees/ADMIN-6-…  on fix/ADMIN-6-…
```

- Each worktree gets its own `node_modules` / `vendor` (copy-on-write clone on APFS:
  instant, no extra disk until changed) and a symlinked `.env`.
- Drop a `.claude/youtrack-worktree-setup.sh` in the repo for anything
  project-specific (per-worktree DB, asset build).
- The worktree directory is ignored via `.git/info/exclude`, so no commit lands on
  your branch.
- **Cleanup is automatic where it is safe.** `/youtrack-task pr` sweeps every
  worktree whose PR has already merged or closed; the one you just opened a PR for
  stays, because review fixes go there. `/youtrack-task done` removes the current
  issue's worktree once its PR is merged. Dirty worktrees are always left alone.

| Command | Does |
|---------|------|
| `/youtrack-task worktree list` | List this plugin's worktrees and each issue's YouTrack state. |
| `/youtrack-task worktree prune` | Remove every worktree whose PR is merged/closed (clean only). |
| `/youtrack-task worktree take <ID>` | Free `<ID>`'s branch from its worktree and `git switch` to it **here**. |
| `/youtrack-task worktree remove <ID>` | Just drop `<ID>`'s worktree (branch kept, no switch). |

**`worktree` modes**

| Value | Behaviour |
|-------|-----------|
| `auto` (default) | A worktree only when the current checkout is busy (dirty or on a task branch) or another worktree exists. The *first* pickup in a clean repo stays in place: fine for one-at-a-time work. |
| `always` | Every pickup gets a worktree. Use this for parallel work. |
| `off` | Always switches the current checkout in place. |

---

## 🔧 During and after the work

```text
/youtrack-task comment <text>          # add a comment to the current branch's issue
/youtrack-task comment INFRA-42 <text> # ...or to a specific issue (a leading issue ID is the issue)
/youtrack-task log 1h30m <what>        # log time on the current branch's issue
/youtrack-task log INFRA-42 45m <what> # ...or on a specific issue
/youtrack-task pr                      # push branch + open PR + link it + move to Testing
/youtrack-task link <pr-url>           # attach an already-open PR to the issue
/youtrack-task testing                 # move the issue to Testing
/youtrack-task done                    # move the issue to Done
/youtrack-task worktree list|prune|take <ID>|remove <ID>   # manage worktrees
/youtrack-task all [ID ...] [--auto-merge]   # many issues in parallel + independent review
```

- `comment`, `log`, `pr`, `link`, `testing` and `done` take the issue ID from your
  current branch name. Pass an explicit `ID` as the first argument to override.
- **State moves are forward-only** along `Open → In Progress → Testing → Done`.
  The state ladder is fixed; only the state names are configurable. Asking to move
  an issue to a state it is already at or past does nothing.

> [!IMPORTANT]
> `pr` is the only command that pushes. The exception is `all`, whose main session
> pushes the branches of reviewed issues after one confirmation.

**What `pr` does and does not do**

- Asks first (shows the commits and diffstat), unless you set `confirm_pr = false`
  or pass `--no-confirm-pr`. That setting never applies to `all`, which always asks
  its one batch confirmation.
- Makes the tree clean first (commit or stash, asked once), then runs the review,
  then shows the diffstat.
- Needs the [`gh` CLI](https://cli.github.com/).
- Never force-pushes and never deletes remote branches. It merges only under
  `all --auto-merge`.

**Languages**

| Output | Language |
|--------|----------|
| Branch names, commit messages, PR title and body | Always English, even for a German issue. |
| YouTrack comments and the title/description of issues created by `new` | The issue's language. Your own "English everywhere" rules for code and docs don't override this. |

---

## 🔄 The full lifecycle

```text
/youtrack-task new …     →  (optional) create the issue first
/youtrack-task ADMIN-6   →  branch, In Progress, plan, (optional) implement
/youtrack-task pr        →  review check + push + GitHub PR + PR link on the issue + → Testing
      … PR review + merge …
/youtrack-task done      →  → Done
```

A worked walk-through of one issue from `new` to `done`, with the state changes and
comments each step writes, is in
[`examples/full-lifecycle.md`](../skills/youtrack-task/examples/full-lifecycle.md).

If you'd rather run your own richer ship flow (tests, version bump, changelog), do
that and then `/youtrack-task link <pr-url>` to record the PR on the issue. `done`
is always last: it means "merged and accepted", so run it after the PR lands.
