---
name: youtrack-task
description: Use when the user runs /youtrack-task, pastes a YouTrack issue URL or ID (e.g. PROJ-123), or wants to work with a JetBrains YouTrack ticket — pick up or plan one, create one ("leg ein Ticket an"), book time on it ("Zeit auf Ticket buchen"), comment on it, move it to Testing or Done, attach or open a PR for it, or work through several tickets as a batch.
---

# youtrack-task

Pick up a YouTrack issue and turn it into a running branch + a reviewed plan,
with state and comments written back to YouTrack.

## Preconditions

Before doing anything, confirm the YouTrack MCP server is available: tools such as
`get_issue`, `search_issues`, `add_issue_comment` and `update_issue` must exist.
This document writes them as in Claude Code (`mcp__youtrack__get_issue`); other
agents namespace them differently (`youtrack_get_issue`) — use the connected
server's tool with the matching base name.

If no such tools exist, stop and print:

> The YouTrack MCP server isn't connected. Add a YouTrack MCP server to your agent
> (URL `https://<your-youtrack-host>/mcp`, header `Authorization: Bearer <permanent
> token from YouTrack → Profile → Account Security>`). In the Claude Code plugin:
> `export YOUTRACK_MCP_URL=…` and `export YOUTRACK_TOKEN=…`, restart, reinstall /
> enable the plugin. Other agents: add an HTTP MCP server in their MCP settings.
> See the README.

Do not attempt REST calls or `curl` as a fallback.

## Guardrails

This skill sets up work and drives planning; with `--implement` it goes on to
implement the plan, following the normal development workflow. Throughout, these are
hard limits — never cross them without the user explicitly approving that
specific action. For the `all` agents these limits are enforced as **best
effort** by `hooks/guard-subagent` plus server-side protection (branch
protection, a token without merge / force-push rights); the hook does not stop
interpreter one-liners (`python3 -c`, `node -e`) or package installs:

- **Never commit to the repository's default branch.** Pre-existing uncommitted
  changes are handled per `reference/branching.md` (stash or carry onto the
  feature branch) — never by committing them on the base branch.
- **Never bypass or fight git hooks.** No `git commit --no-verify`; no amending or
  rewriting existing commits. If a hook fails, stop and report it.
- **Never mutate application state for testing** — no writes to databases, seed
  data, fixtures, user records, passwords, or auth tokens, even to enable visual
  QA. If QA needs a particular data state, ask the user to set it up or point at
  it, otherwise describe what could not be verified.
- **Never start servers, daemons, or watchers without asking**, and stop any you
  were told to start.
- **Pushing and opening a PR happen only in the explicit `pr` sub-command** (or
  the user's own `/ship`), after a confirmation prompt — unless `pr` was told not
  to ask (config `confirm_pr = false` or `--no-confirm-pr`), the user's standing
  authorization for that push and PR and nothing more: the review gate and the
  other checks still apply. Never as an implicit part of the primary flow, `done`
  or anything else. Within an explicit `all` run the **main session** may push an
  issue's own branch (plain push, never another ref) and open PRs for the whole
  batch after **one** confirmation listing them; workers and reviewers never push.
  **Never force-push.** Never delete a remote branch; local deletion is only the
  safe `git branch -d` of a merged branch by `sweep-worktrees`.
- **No unlisted confirmation questions.** The invocation authorizes the work it
  names. Ask only the questions this document specifies, each in a step or a
  table over a resolved value. Never *"Shall I continue?"* / *"OK to proceed?"*,
  and not after a wrong input either: stop and say what is wrong.
- **No push or PR without a review.** Before a branch is pushed or a PR opened
  (`pr`, and `all` step 6) the review gate in `reference/review.md` must have
  stamped `PASS` on the exact HEAD. The only exceptions are the explicit
  `--no-review` / `review_before_pr = never` paths, which are labelled
  *skipped* in the PR and on the issue. With `review_gate_hook = "on"` the plugin
  hook `hooks/require-review` enforces this for pushes and `gh pr create`.
- **Merging a PR happens only in `all --auto-merge`**, by the main session, under
  the conditions in `reference/batch.md` (review `PASS` on the exact head commit,
  required checks green, `CLEAN`, no overlap, no admin bypass). Without that
  flag, never merge.
- **Worktree removal** (`done` cleanup, `worktree prune`) never uses
  `git worktree remove --force` and never `git branch -D`. A worktree with
  uncommitted changes is left alone and reported, not removed.
- The only YouTrack writes are: the pickup state change + comment, the plan
  comment, the completion comment (template in `reference/writeback.md`), in `all` the worker-plan,
  question (`BLOCKED` / `ESCALATE`), status and per-issue completion comments
  written by the main session, and the explicit
  `new` (create + its Type / Priority / Assignee fields) / `comment` / `log` /
  `pr` / `link` / `testing` / `done` sub-commands.
- **Language** — git artifacts are always English, YouTrack-side text always
  follows the user's / the issue's language. See "Language" below; it is a hard
  rule, not a style preference.
- **Assignee** — an issue is never created unassigned: the assignee is the API-key
  owner (`get_current_user`) unless the user named someone else. This holds for
  **every** `create_issue` call, also ones made directly in conversation ("leg die
  Issues an"): pass `Assignee` in `customFields`. (The plugin's `create_issue` hook
  rejects a call without one.)

## Language

Two outputs, two rules. Never mix them up, and never let a global or project rule
("English everywhere", "code and docs in English") bleed from one into the other.

| Output | Language |
| --- | --- |
| **Git artifacts** — branch names, commit messages, PR titles and bodies, locally written plan / design docs | **Always English.** Translate the issue title for these, and only for these. |
| **YouTrack-side text** — issue title and description (`new`), plan / pickup / completion / state comments, anything written with `add_issue_comment`, `create_issue`, `update_issue` | **The user's language** (below). Never silently English. |

**Which language is "the user's language"?** First match wins:
1. An explicit instruction from the user (*"write it in English"*, *"auf Englisch"*).
2. For `new`: the language of the user's input text (free text, or the
   `--title` / `--description` they typed).
3. For an existing issue: the language of its title + description.
4. Mixed or unclear: the language the user is writing to you in this session.

English is the answer only if one of these says English. YouTrack text is read by
people, so the "developer-facing text is English" rules of a user's global
instructions or a repo's `CLAUDE.md` do **not** apply to it (they cover code,
comments, docs and git).

**Before every YouTrack write** (`create_issue`, `update_issue` with text,
`add_issue_comment`) check that the title / body is in the resolved language; if
not, rewrite it first. Fixed template headings and emoji (`📌 Picked up in Claude
Code`, `## 📝 Implementation plan`) stay as written; everything after them is the
resolved language. A `comment` sub-command text is sent verbatim.

## Scripts

This skill bundles helpers in its `scripts/` directory — run them, don't
reimplement their logic. **`<skill-dir>`** is the directory that holds this
`SKILL.md`: `${CLAUDE_SKILL_DIR}` in Claude Code, in other agents the base
directory the skill was loaded from. Call every script by its absolute path,
`<skill-dir>/scripts/<name>`, with the **working directory set to the target repo**
(or its worktree) — the scripts find the repo from it, so never `cd` into
`scripts/`. A `cd` does not persist between Bash calls:
`(cd <repo-or-worktree> && <skill-dir>/scripts/<name> …)`.

- `read-config` — step 0 of every invocation: config with defaults applied.
- `setup-workspace` — step 4: worktree-vs-in-place, branch / worktree creation, resume detection, bootstrap.
- `sweep-worktrees` — `pr` step 8, `done`, `worktree prune`: removes finished worktrees safely.
- `worktree-detach` — `worktree take` / `remove`: frees one issue's branch from its worktree.
- `review-stamp` — review gate and `pr`: records / checks "PASS on this exact commit".

All echo `KEY=VALUE` lines; contract: `reference/worktrees.md` (`review-stamp`:
`reference/review.md`).

**Are the scripts on disk?** Step 0 asks first:
`test -x <skill-dir>/scripts/read-config && echo SCRIPTS=present || echo SCRIPTS=missing`

| Result | Do this |
| --- | --- |
| `SCRIPTS=present` | use the scripts as written everywhere in this document |
| `SCRIPTS=missing` | read `reference/scripts-fallback.md` before acting; never write the scripts out yourself |

## Config

Optional file `~/.config/youtrack-task/config.toml`; every key is optional.

**Load it first, on every invocation, before any decision that depends on it:** run
`<skill-dir>/scripts/read-config` and use its `KEY=VALUE` output as the only source
of config values. The Defaults column is documentation, not something to apply
from memory — a value you did not get from `read-config` (or, without `scripts/`,
from reading the file) is unknown. Flags override config for one run.
`setup-workspace` / `sweep-worktrees` read the file themselves.

| Key | Default |
| --- | --- |
| `list_query` | `for: me #Unresolved State: {In Progress}, {Open} sort by: updated desc` |
| `in_progress_state` | `In Progress` |
| `testing_state` | `Testing` |
| `done_state` | `Done` |
| `local_plan_copy` | `auto` |
| `default_new_type` | *(unset)* — fallback Type for `new` when inference is uncertain |
| `use_superpowers` | `auto` — `auto` \| `always` \| `never` (see `reference/superpowers.md`) |
| `review_before_pr` | `always` — `always` (every task with commits is reviewed before push/PR; `auto` is accepted as a synonym) \| `never` (see `reference/review.md`) |
| `review_gate_hook` | `off` — `on` makes `hooks/require-review` block a push / `gh pr create` of an issue branch without a review stamp (see `reference/review.md`) |
| `review_rounds` | `2` — max fix / re-review rounds per issue in the review gate (`batch_review_rounds` is accepted as an alias) |
| `worktree` | `auto` — `auto` (worktree when the checkout is dirty, on a non-default branch, or a plugin worktree already exists; parallel work wants `always`) \| `off` \| `always` |
| `confirm_branch_name` | `true` — `false` accepts the computed branch name without asking (it is still shown; `--confirm-branch` / `--no-confirm-branch` override per run) |
| `confirm_pr` | `true` — `false` makes `pr` push and open the PR without the confirmation question (commits and diffstat are still shown; `--confirm-pr` / `--no-confirm-pr` override per run). Applies to `pr` only: `all` always asks its one batch confirmation |
| `worktree_dir` | `.worktrees` — dir under the repo root that holds worktrees |
| `worktree_clone` | `["node_modules", "vendor"]` — dirs CoW-copied into a new worktree (`+ "storage"` for Laravel repos) |
| `worktree_link` | `[".env"]` — paths symlinked from the main checkout into a new worktree |
| `batch_query` | `for: me #Unresolved sort by: updated desc` — candidates for `all` when no IDs are given; the current repo's `project: {KEY}` is added unless the query already has a `project:` clause |
| `batch_max_parallel` | `3` — parallel workers for `all` |
| `batch_skip_tags` | `["manual"]` — issues with one of these tags are never worked on by `all` |
| `batch_review_rounds` | alias of `review_rounds`, kept for existing configs |
| `[type_prefix]` table | see `reference/branching.md` |

## Resolving a project

Everywhere the skill needs "the current repo's YouTrack project" (bare issue
number, repo sanity check, `new`, `all`), read `reference/projects.md` and use its
procedure — never an ad-hoc guess; `find_projects` returns at most 20 projects
per page. A project key the user typed (`--project KEY`) goes straight to
`get_project`. An issue ID's prefix is authoritative for that issue's project.

## Issue IDs

`ISSUE_ID_RE` is `[A-Z][A-Z0-9_]*-[0-9]+`. It is the one form used by this skill,
`reference/*.md`, the scripts and the hooks (`review-stamp`, `hooks/require-review`);
`tests/skill-text.sh` keeps them identical. Never write a variant of it.

| Where an ID is needed | Rule |
| --- | --- |
| an argument is "an issue ID" | the whole token matches `^ISSUE_ID_RE$` |
| the ID of the current branch | the **first** match of `ISSUE_ID_RE` in `git branch --show-current` (`fix/P2X-5-foo` → `P2X-5`, never `X-5`) |
| leading token of `comment` / `log` / `pr` / `link` / `testing` / `done` | a token that matches `^ISSUE_ID_RE$` **is** the issue ID and the rest is the text; any other first token means there is no ID argument — the ID comes from the branch (else ask) and the whole remainder is the text |

## Dispatch on the first argument

| First arg | Action |
| --- | --- |
| *(none)*, an issue ID (`^ISSUE_ID_RE$`), or a bare number | **Primary flow** (below); read `reference/pickup.md` at step 4 |
| `new` | create a new issue — read `reference/new.md` before acting |
| `comment` | comment on the leading issue ID or else the current branch's issue — read `reference/subcommands.md` before acting |
| `log` | time logging — read `reference/subcommands.md` before acting |
| `pr` | push the branch, open a PR, link it on the issue, move to Testing — read `reference/pr.md` before acting |
| `link` | attach an existing PR URL to the issue as a comment — read `reference/subcommands.md` before acting |
| `testing` | move the issue to `testing_state` — read `reference/subcommands.md` before acting |
| `done` | move the issue to `done_state` — read `reference/subcommands.md` before acting |
| `worktree` | `list` / `prune` / `take` / `remove` this plugin's worktrees — read `reference/subcommands.md` before acting |
| `all` | work through several issues in parallel with independent review — read `reference/batch.md` before acting |

**Every invocation, whatever the first argument, starts with step 0:** check that
the scripts are on disk and run `<skill-dir>/scripts/read-config` (**Scripts**,
**Config**) before anything that depends on a config value. For `comment` / `log`
/ `pr` / `link` / `testing` / `done`, the issue ID is resolved per "Issue IDs":
a leading ID argument, else the branch's ID, else ask.

---

## Primary flow

```
/youtrack-task [ISSUE-ID | N] [--no-move] [--no-writeback] [--base <branch>]
               [--worktree | --no-worktree] [--checkpoints] [--review | --no-review]
               [--confirm-branch | --no-confirm-branch] [--implement]
```

- `--no-move` — keep the issue state on pickup (the pickup comment is still written).
- `--no-writeback` — no pickup state change and no pickup comment.
- `--base <branch>` — branch from `<branch>` instead of the detected default.
- `--worktree` / `--no-worktree` — force / skip an isolated worktree (default:
  config `worktree`). See `reference/worktrees.md`.
- `--confirm-branch` / `--no-confirm-branch` — ask / don't ask about the computed
  branch name in step 4 (default: config `confirm_branch_name`; the flag wins).
- `--implement` — run step 8 after the plan is written back; without it the flow
  ends after step 7. On an existing worktree it continues from the plan comment.
- `--checkpoints` — step 8 runs an architectural plan with
  `superpowers:executing-plans` instead of `subagent-driven-development`.
- `--no-review` — skip the review gate in step 8 (default: every task with commits
  is reviewed, see `review_before_pr`); `pr` then asks before pushing. `--review`
  changes nothing.

### 0. Load config

Check that the scripts are on disk (see **Scripts**), then run
`<skill-dir>/scripts/read-config` and keep its output for the whole run (see
**Config**). No other step reads or guesses config values.

### 1. Resolve the issue ID

First match wins:

1. **Full ID** (`^ISSUE_ID_RE$`) → use it verbatim.
2. **Bare number** `N` → `<PROJECT>-N`, the project resolved per "Resolving a
   project". Read it with `get_issue` (also step 2's fetch), echo *"→ `<PROJECT>-N`:
   <summary>. Continue?"* and proceed only on yes. No project key → ask for a full ID.
3. **No arg** → the first `ISSUE_ID_RE` match in `git branch --show-current`; ask
   *"Continue on `<ID>` (from branch `<branch>`)?"* and proceed only on yes.
4. **Still nothing** → `search_issues` with `list_query`, show `<ID> — <summary> —
   <state>` per line, ask for an issue ID. A bare number in the reply is rule 2,
   **never** a position in the list. Empty list → ask for an explicit ID.

**ID not found** — when `get_issue` finds no issue for the ID from rule 1 or 2,
stop: print the ID, and name `<PROJECT>-<number>` of this repo's project as the
likely intended one if that issue exists. The user runs it again with the right
ID. No pickup, no go-ahead question, no automatic substitution.

### 2. Fetch context

`get_issue` and `get_issue_comments`. Show a short brief: ID, title, Type,
Priority, State, Subsystem (if any), and a 2–4 sentence gist of the description
and any decisive comment.

### 3. Repo sanity check

`git rev-parse --is-inside-work-tree` must succeed, else stop: *"Not inside a git
repository — cd into the project first."* Compare `git remote get-url origin`
loosely to the issue's project (`get_project`; the ID's prefix already names it, no
search needed). On a clear mismatch warn once — *"`<ID>` is in project `<PROJ>` but
this repo looks like `<slug>` — continue anyway?"* — and continue only on yes.
Never hard-block.

### 4. Set up the workspace

Compute `<prefix>` and `<slug>` per `reference/branching.md` (English, leading
type word stripped, 40-char cap). Then decide. The effective value is the flag if
one was given (`--confirm-branch` = `true`, `--no-confirm-branch` = `false`), else
`CONFIRM_BRANCH_NAME` from the step-0 output:

| Effective `confirm_branch` | do this |
| --- | --- |
| `false` | print one line `→ Branch: <name>` and go straight on. **No question, no go-ahead gate.** |
| `true` | print `→ Branch: <name>`, ask accept/rename, then go on. Ask only about the name. |

Either way, the pickup (workspace, state change, pickup comment, planning) is
already authorized by the invocation: never bundle it into an extra "OK to
proceed?" question. Then **read `reference/pickup.md` before acting**: it runs
`<skill-dir>/scripts/setup-workspace`, acts on its `MODE=` output (enter the
worktree, resume an existing one), and holds the **resume check** that steps 5–7
follow. Do not hand-roll the branch / worktree logic.

### 5. Write-back on pickup

Skip this step with `--no-writeback`, or when the resume check found the pickup
comment. Otherwise follow `reference/writeback.md`: resolve the state field via
`get_issue_fields_schema`; if the issue is before `In Progress` on the ladder,
`update_issue` → `in_progress_state`; then `add_issue_comment` with the pickup
template (a one-liner noting the recreated branch if the issue was already In
Progress). `--no-move` skips only the state change.

### 6. Plan the work

With the `superpowers` plugin available (and `use_superpowers` not `never`), plan
**and** run step 8 through it — routing, plan document location and bounded vs
architectural are in `reference/superpowers.md`. Otherwise use plain plan mode.
Either way: explore the repo, produce a plan, present it, iterate until the user
approves it, and note whether it is **bounded** or **architectural** (step 8 needs it).

### 7. Write-back the plan

Only after the user approves the plan, and not when the resume check found the
plan comment:
- `add_issue_comment` with the plan as Markdown (template in
  `reference/writeback.md`). It is YouTrack-side text: the issue's language.
- **Local copy.** A plan or design document already written by the superpowers
  path **is** the local copy: name its path, write no second one. Otherwise
  `local_plan_copy`: `auto` → `docs/plans/<ID>.md` if the repo has a `docs/`
  directory; `always` → always (create `docs/plans/`); `never` → no file. A local
  copy is a git artifact: **always English**, translated if the comment is not.

Then summarise what landed where (branch, state, comment URL, local file). Step 8
follows from `--implement`.

### 8. Implement (`--implement`)

| `--implement` | Do this |
| --- | --- |
| given | run this step; no question, the flag is the go-ahead |
| absent | the flow ends after step 7. Print one line — *"Plan is on `<ID>`. Run `/youtrack-task <ID> --implement` to implement it."* — and stop. No question |

Bound by the **Guardrails** above.

**superpowers path** — `reference/superpowers.md` step 8: bounded → TDD
(`superpowers:test-driven-development`); architectural →
`superpowers:subagent-driven-development` (`superpowers:executing-plans` with
`--checkpoints`); both end with `superpowers:verification-before-completion`
against the acceptance criteria. **Fallback path** — the normal development
workflow (TDD where it applies) plus a manual check against the acceptance criteria.

**Review gate (both paths).** Once the work is verified, run the gate in
`reference/review.md` with `fixer = main-session`: a fresh `ticket-reviewer`, a
minimal briefing, the result stamped on the exact commit. It applies to every task
with commits; `--no-review` or `review_before_pr = never` skips it. A `FAILED` gate
stops here with the open findings — no completion comment that claims the work is done.

Then post the completion comment (template in `reference/writeback.md`: branch,
files touched, `Review: PASS @ <short-sha>` or `Review: skipped`). Do not push, open
a PR or move the issue here — tell the user the branch is ready and that
`/youtrack-task pr` or their own `/ship` is the next step.

---

## all

`/youtrack-task all [ID ...] [--max N] [--no-review] [--dry-run] [--auto-merge]`
— read `reference/batch.md` before acting: triage, workers, the review loop, PRs
and merge are specified there, don't improvise. `confirm_pr` does not apply to
`all`: its one batch confirmation is always asked. Only the main session writes
to YouTrack, pushes and merges; workers commit locally. Issues tagged with one of
`batch_skip_tags`, or that look like server / network / secret / data-store work,
are never run unattended.

## Notes

- Every YouTrack write is one MCP call; on a 403 report which call failed and keep going (in the primary flow the branch already exists).
- Re-resolve the state field per project and never invent custom-field names — read the schema first.
