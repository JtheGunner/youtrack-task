---
name: youtrack-task
description: Use when the user runs /youtrack-task, or asks to pick up / start / work on / plan / create / file / log a JetBrains YouTrack issue, ticket or bug ("leg ein Ticket an", "erfasse den Fehler als Issue", "create an issue for this"). Fetches the issue over the YouTrack MCP server, creates a git branch (optionally an isolated worktree for parallel tasks), moves the issue to In Progress, drives planning, and writes results back to the issue. Also handles /youtrack-task new|comment|log|pr|link|testing|done|worktree|all (all = work through several issues in parallel with independent review).
---

# youtrack-task

Pick up a YouTrack issue and turn it into a running branch + a reviewed plan,
with state and comments written back to YouTrack.

## Preconditions

Before doing anything, confirm the YouTrack MCP server is available: tools such as
`get_issue`, `search_issues`, `add_issue_comment` and `update_issue` of a YouTrack
MCP server must exist.

**Tool names.** This document writes them as they appear in Claude Code
(`mcp__youtrack__get_issue`). Other agents prefix or namespace MCP tools
differently (for example `youtrack_get_issue` or `youtrack.get_issue`); use
whichever tool of the connected YouTrack MCP server has the matching base name
(`get_issue`, `create_issue`, …).

If no such tools exist, stop and print:

> The YouTrack MCP server isn't connected. Add a YouTrack MCP server to your agent
> (URL `https://<your-youtrack-host>/mcp`, header `Authorization: Bearer <permanent
> token from YouTrack → Profile → Account Security>`).
> - Claude Code plugin: `export YOUTRACK_MCP_URL=…` and `export YOUTRACK_TOKEN=…`,
>   restart, reinstall/enable the plugin.
> - Other agents (Cursor, Copilot, …): add an HTTP MCP server with the same URL and
>   header in that agent's MCP settings. See the README.

Do not attempt REST calls or `curl` as a fallback.

## Guardrails

This skill sets up work and drives planning; once a plan is approved it may go on
to implement, following the normal development workflow. Throughout, these are
hard limits — never cross them without the user explicitly approving that
specific action:

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
  to ask (config `confirm_pr = false` or `--no-confirm-pr`), which is the user's
  standing authorization for that push and PR and nothing more: the review gate
  and the other checks still apply. Never as an implicit part
  of the primary flow, `done`, or anything else. Within an explicit `all` run,
  the **main session** may push an issue's own branch (plain push, never any
  other ref) and open PRs for the whole batch after **one** confirmation listing
  them; workers and reviewers never push. **Never force-push.** Never delete a
  remote branch; local deletion is only the safe `git branch -d` of a merged
  branch by `sweep-worktrees`.
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
  comment, an optional one-line completion comment, in `all` the worker-plan,
  question (`BLOCKED` / `ESCALATE`), status and per-issue completion comments
  written by the main session, and the explicit
  `new` (create + its Type / Priority / Assignee fields) / `comment` / `log` /
  `pr` / `link` / `testing` / `done` sub-commands.
- **Language** — git artifacts are always English, YouTrack-side text always
  follows the user's / the issue's language. See "Language" below; it is a hard
  rule, not a style preference.

- **Assignee** — an issue is never created unassigned. The assignee is the
  issue's creator (the API-key owner, `get_current_user`) unless the user named
  someone else. This holds for **every** `create_issue` call, including ones made
  directly in conversation ("leg die Issues an", a bug found while testing)
  without running `new`: pass `Assignee` in `customFields`, and follow the
  Language rules below for the text. (The plugin's `create_issue` hook rejects a
  call without an Assignee.)

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

English is the answer only if one of these says English. Text in YouTrack is
read by people, so the "developer-facing text is English" rules in a user's
global instructions or a repo's `CLAUDE.md` do **not** apply to it — those cover
code, comments, docs and git, not issue-tracker prose.

**Before every YouTrack write** (`create_issue`, `update_issue` with text,
`add_issue_comment`) check that the title / body you are about to send is in the
resolved language. If it is not, rewrite it first. Fixed template headings and
emoji (`📌 Picked up in Claude Code`, `## 📝 Implementation plan`) stay as
written; everything after them is the resolved language. A `comment` sub-command
text is sent verbatim, as the user wrote it.

## Scripts

This skill bundles helpers in its `scripts/` directory — run them, don't
reimplement their logic:
- `read-config` — step 0 of every invocation: resolves the config below with
  defaults applied. Never decide a config value without it.
- `setup-workspace` — step 4: the worktree-vs-in-place decision, branch / worktree
  creation, resume detection, and worktree bootstrap. Reads the config below.
- `sweep-worktrees` — `pr` step 8, `done`, and `worktree prune`: removes finished
  worktrees (clean + PR merged/closed) safely.
- `worktree-detach` — `worktree take` / `worktree remove`: drop the worktree
  holding one issue's branch (branch kept), optionally `git switch` to it here.
- `review-stamp` — the review gate and `pr`: records and checks "PASS on this exact
  commit" (`write` / `check`).

All echo `KEY=VALUE` lines; the contract is in `reference/worktrees.md`
(`review-stamp`: `reference/review.md`).

**If `scripts/` isn't on disk** (the skill was loaded through a connection that
doesn't materialise bundled files), do not write the scripts out yourself. Degrade
to plain git, in place, never forcing anything:
- `setup-workspace` → `git switch -c <prefix>/<ID>-<slug> <base>` from a clean tree
  (ask before stashing); report `MODE=inplace`. No worktree.
- `read-config` → read `~/.config/youtrack-task/config.toml` with the Read tool
  (if it exists) and apply the defaults in the Config table yourself.
- `sweep-worktrees` / `worktree prune` → skip and say so.
- `worktree take` / `worktree remove` → print the `git worktree remove <path>` /
  `git switch <branch>` commands for the user to run.
- `review-stamp` → still run the review gate (it needs no script), keep the
  reviewed SHA in this session only, and say that `pr` in a later session cannot
  verify it and will review again.

## Config

Optional file `~/.config/youtrack-task/config.toml`; every key is optional.

**Load it first, on every invocation, before any decision that depends on it**
(step 0 of the primary flow and of every sub-command): run
`scripts/read-config` (from this skill's `scripts/` directory) and use its
`KEY=VALUE` output as the only source of config values. The Defaults column below
is documentation, not something to apply from memory — a value you did not get
from `read-config` (or, without `scripts/`, from reading the file) is unknown.
Flags override config for one run. `setup-workspace` / `sweep-worktrees` read the
file themselves. Defaults:

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
| `confirm_pr` | `true` — `false` makes `pr` push and open the PR without the confirmation question (commits and diffstat are still shown; `--confirm-pr` / `--no-confirm-pr` override per run) |
| `worktree_dir` | `.worktrees` — dir under the repo root that holds worktrees |
| `worktree_clone` | `["node_modules", "vendor"]` — dirs CoW-copied into a new worktree (`+ "storage"` for Laravel repos) |
| `worktree_link` | `[".env"]` — paths symlinked from the main checkout into a new worktree |
| `batch_query` | `for: me #Unresolved State: Open sort by: updated desc` — candidates for `all` when no IDs are given |
| `batch_max_parallel` | `3` — parallel workers for `all` |
| `batch_skip_tags` | `["manual"]` — issues with one of these tags are never worked on by `all` |
| `batch_review_rounds` | alias of `review_rounds`, kept for existing configs |
| `[type_prefix]` table | see `reference/branching.md` |

## Resolving a project

Everywhere the skill needs "the current repo's YouTrack project" (bare issue
number, repo sanity check, `new`), use this one procedure — never an ad-hoc
guess. `find_projects` returns **at most 20 projects per page**, so one call with
an empty query shows only the first page; a project missing from it may still
exist. Names differ from keys (repo `intelli-key-port` ↔ key `IKP`), so match on
the **name**, not the key.

1. **Candidates.** The repo name from `git remote get-url origin` (strip the
   `.git` suffix and any owner path) and the basename of the working directory,
   each also with `-` / `_` removed.
2. **Targeted search.** `find_projects(query=<candidate>)` per candidate. A
   case-insensitive exact name match wins. A single substring match is offered for
   confirmation. Several matches → ask which.
3. **Full listing, only if step 2 found nothing.** Page through
   `find_projects(query="", limit=20, offset=0, 20, 40, …)` until a page returns
   fewer than 20 items, then match the candidates against every name.
4. **Verify.** `get_project` on the chosen key before using it.
5. **Only now** may you say there is no matching project — after steps 2 and 3.
   A list you show the user to pick from must be the complete one from step 3
   (or say it is partial). Never answer *"there is no project named …"* from a
   single unpaged call.

The 20-item cap and the paging loop are spelled out in `reference/projects.md`.

A project key the user typed (`--project KEY`) skips 1–3 and goes straight to
`get_project`. An issue ID's prefix is authoritative for that issue's project.

## Dispatch on the first argument

| First arg | Action |
| --- | --- |
| *(none)*, an issue ID (`^[A-Z][A-Z0-9_]+-\d+$`), or a bare number | **Primary flow** (below) |
| `new` | create a new issue — see "new" below |
| `comment` | `add_issue_comment` with the rest of the line, to the current branch's issue |
| `log` | time logging — see "log" below |
| `pr` | push the branch, open a PR, link it on the issue, move to Testing — see "pr" below |
| `link` | attach an existing PR URL to the issue as a comment — see "link" below |
| `testing` | move the issue to `testing_state` — see "state sub-commands" |
| `done` | move the issue to `done_state` — see "state sub-commands" |
| `worktree` | `list` / `prune` / `take` / `remove` this plugin's worktrees — see "worktree" below |
| `all` | work through several issues in parallel with independent review — see "all" below |

**Every invocation, whatever the first argument, starts with step 0:** run
`scripts/read-config` (see **Config**) before anything that depends on a config
value. The sub-commands below do not repeat it.

For `comment` / `log` / `pr` / `link` / `testing` / `done`, resolve the issue ID
from an explicit leading `ISSUE-ID` argument if given, else extract `[A-Z]+-\d+`
from `git branch --show-current`, else ask the user.

---

## Primary flow

```
/youtrack-task [ISSUE-ID | N] [--no-move] [--no-writeback] [--base <branch>]
               [--worktree | --no-worktree] [--checkpoints] [--review | --no-review]
               [--confirm-branch | --no-confirm-branch]
```

- `--no-move` — don't change the issue state on pickup (keep the pickup comment).
- `--no-writeback` — no pickup state change and no pickup comment.
- `--base <branch>` — branch from `<branch>` instead of the detected default.
- `--worktree` / `--no-worktree` — force / skip an isolated git worktree for this
  pickup (default: `config` `worktree`, itself defaulting to `auto`). See
  `reference/worktrees.md`.
- `--confirm-branch` / `--no-confirm-branch` — ask / don't ask whether the computed
  branch name is OK in step 4 (default: config `confirm_branch_name`, itself
  `true`). The flag wins over the config. Without the question the name is
  accepted as computed and only shown.
- `--checkpoints` — step 8 executes an architectural plan with
  `superpowers:executing-plans` (review stop after each phase) instead of
  `subagent-driven-development`.
- `--no-review` — skip the review gate in step 8 for this run (default: every
  task with commits is reviewed; see `config` `review_before_pr`). `pr` will then
  ask before pushing an unreviewed branch. `--review` is accepted and changes nothing.

### 0. Load config

Run `scripts/read-config` and keep its output for the whole run (see **Config**).
No other step reads or guesses config values.

### 1. Resolve the issue ID

Resolve in this order:

1. **Arg is a full ID** (`^[A-Z][A-Z0-9_]+-\d+$`) → use it verbatim.
2. **Arg is a bare number** `N` → qualify it with the current repo's project key
   (see below): the issue is `<PROJECT>-N`. Echo one line —
   *"→ `<PROJECT>-N`: <summary>. Continue?"* — and proceed only on yes. If the
   project key can't be determined, ask for a full ID instead.
3. **No arg** → `git branch --show-current`; if it contains `[A-Z]+-\d+`, extract
   that ID and ask *"Continue on `<ID>` (from branch `<branch>`)?"* — proceed
   only on yes.
4. **Still nothing** → `mcp__youtrack__search_issues` with `list_query` and show
   the candidates as:
   `<ID> — <summary> — <state>` (one per line, no leading row numbers).
   Ask the user to reply **with an issue ID** (e.g. `ADMIN-6`). A bare number in
   the reply is treated exactly like rule 2 (→ `<PROJECT>-N`), **never** as a
   position in the list. Empty list → say so, ask for an explicit ID.

**Current repo's project key:** resolve it with "Resolving a project" above, or
take the dominant project prefix among the issues returned by `list_query` for
this repo. This is the same project used for the sanity check in step 3.

### 2. Fetch context

- `mcp__youtrack__get_issue` for full detail.
- `mcp__youtrack__get_issue_comments` for existing discussion.

Show the user a short brief: ID, title, Type, Priority, State, Subsystem (if the
issue has one), and a 2–4 sentence gist of the description + any decisive comment.

### 3. Repo sanity check

- `git rev-parse --is-inside-work-tree` must succeed. If not, stop: *"Not inside a
  git repository — cd into the project first."*
- `git remote get-url origin` → repo slug. Compare loosely to the issue's project
  (use `mcp__youtrack__get_project` for its name / short name; the issue ID's
  prefix already names the project, so no project search is needed). On a clear
  mismatch, warn once: *"`<ID>` is in project `<PROJ>` but this repo looks like
  `<slug>` — continue anyway?"* Continue only on yes. Never hard-block.

### 4. Set up the workspace

Compute `<prefix>` and `<slug>` per `reference/branching.md` (English, leading
type word stripped, 40-char cap). Then decide from the step-0 output:

| `--no-confirm-branch`, or `CONFIRM_BRANCH_NAME=false` without `--confirm-branch` | do this |
| --- | --- |
| yes | print one line `→ Branch: <name>` and go straight on. **No question, no go-ahead gate.** |
| no | show the name for accept/rename, then go on. Ask only about the name. |

Either way, the pickup (workspace, state change, pickup comment, planning) is
already authorized by the invocation: never bundle it into an extra "OK to
proceed?" question. Then run the bundled script — **do not hand-roll the branch /
worktree logic**, the script is the source of truth
(spec: `reference/worktrees.md`):

```
scripts/setup-workspace --id <ID> --slug <slug> --prefix <prefix> \
    [--base <branch>] [--mode worktree|inplace]
```
(run it from this skill's `scripts/` directory). `--mode worktree` for
`--worktree`, `--mode inplace` for `--no-worktree`; omit otherwise — the script
reads `config` `worktree`, does the dirty / branch / existing-worktree checks,
creates or resumes, and bootstraps a new worktree.

Act on its `KEY=VALUE` output:

| `MODE=` | do this |
| --- | --- |
| `inplace` | you're on `BRANCH` in the repo root. Report `BRANCH` / `BASE`. |
| `worktree` | `cd` to `NEXT_CD` (or `EnterWorktree` that path). Report `BRANCH` `BASE` `DIR` `CLONED` `LINKED` + any `NOTE=` lines. Steps 5–8 run there. |
| `existing-worktree` | a worktree for this issue already exists → `cd` to `NEXT_CD` (or `EnterWorktree`). Announce *"Resuming `<ID>` in `<DIR>`."* **Skip step 5.** In step 6 reuse the existing plan comment — don't re-brainstorm unless asked, don't re-post it in step 7. |
| `existing-branch` | a branch for this issue exists but isn't checked out. Ask the user: `git switch <BRANCH>`, or `git worktree add <repo>/<worktree_dir>/<ID>-<slug> <BRANCH>` then enter it. **Skip step 5.** Reuse the plan comment as above. |

`ERROR=dirty-tree` (exit 2) → tracked changes present, in-place branch wanted.
Ask the user: stash (`git stash push -u`, re-run, then pop or keep) or carry
(re-run with `--allow-dirty` — the changes ride onto the feature branch). Never a
commit on the base branch. Any other `ERROR=` → stop and show it.

### 5. Write-back on pickup

Skip this whole step if `--no-writeback` was passed, or if step 4 returned
`existing-worktree` / `existing-branch` (the pickup already happened).

Follow `reference/writeback.md`:
- resolve the state field via `get_issue_fields_schema`
- if the issue is before `In Progress` on the ladder, `update_issue` → `in_progress_state`
  (skip silently if already at In Progress / Testing / Done)
- `add_issue_comment` with the pickup template. If the issue was already In
  Progress and step 4 made a fresh branch anyway (a previous session's branch was
  lost), make it a one-liner noting the branch was recreated.

`--no-move` skips only the state change, keeps the pickup comment.

### 6. Plan the work

If the `superpowers` plugin is available (and `use_superpowers` isn't `never`),
run planning **and** step 8 through it — see `reference/superpowers.md` for the
full routing (Type → process skill, which description section feeds which skill,
where the plan document goes, bounded vs architectural). In short: Bug →
`superpowers:systematic-debugging` then design; else `superpowers:brainstorming`;
architectural work also goes through `superpowers:writing-plans`.

Otherwise (fallback): hand the issue into plain plan mode. Either way — explore
the current repo for the files the change touches, produce a plan, present it for
review, iterate until the user approves it. Note whether the result is **bounded**
or **architectural**; step 8 depends on it.

### 7. Write-back the plan

Only after the user approves the plan:
- `mcp__youtrack__add_issue_comment` with the plan rendered as Markdown, using the
  plan template from `reference/writeback.md`.
- **Local copy.** If step 6's superpowers path already wrote a plan / design
  document locally (the architectural case — `docs/superpowers/specs/…` or
  `docs/plans/<ID>-plan.md`), that file **is** the local copy: do not write a
  second one; just name its path. Otherwise apply `local_plan_copy`:
  - `auto` (default): if the repo already has a `docs/` directory, write
    `docs/plans/<ID>.md`. No `docs/` → skip, don't create it.
  - `always`: always write `docs/plans/<ID>.md` (create `docs/plans/` if needed).
  - `never`: never write a local file.

Then summarise what landed where (branch, YouTrack state, comment URL if the MCP
result includes one, local file if written).

### 8. Implement (optional)

Only if the user wants to proceed now. Bound by the **Guardrails** above.

**superpowers path** — follow `reference/superpowers.md` step 8:
- bounded → implement directly with `superpowers:test-driven-development`.
- architectural → execute the plan with `superpowers:subagent-driven-development`
  (or `superpowers:executing-plans` when `--checkpoints` is passed), TDD inside
  each task.
- both → `superpowers:verification-before-completion` with the acceptance
  criteria as the checklist before finishing.

**Fallback path** — the normal development workflow (TDD where it applies) plus a
manual verification pass against the acceptance criteria.

**Review gate (both paths).** Once the work is verified, run the review gate in
`reference/review.md` with `fixer = main-session`: a fresh `ticket-reviewer`
subagent, a minimal briefing, the result stamped on the exact commit. It applies
to every task with commits, bounded or architectural. `--no-review` or config
`review_before_pr = never` skips it. A `FAILED` gate stops here with the open
findings; do not post a completion comment that claims the work is done.

Then post one short completion comment (`add_issue_comment`, template in
`reference/writeback.md`) listing the branch, the files touched and the review
result (`Review: PASS @ <short-sha>`, or `Review: skipped`). Do not push,
open a PR, or move the issue here — tell the user the branch is ready and that
`/youtrack-task pr` or their own `/ship` is the next step.

---

## State sub-commands (`testing`, `done`)

1. Resolve the issue ID (arg → branch → ask).
2. Resolve the state field via `get_issue_fields_schema`.
3. Determine ladder positions. Target: `testing_state` for `testing`,
   `done_state` for `done`.
4. If the issue is already at or past the target on the ladder
   (`Open<In Progress<Testing<Done`), report its current state and do nothing.
5. Otherwise `update_issue` to the target, then `add_issue_comment` with the
   matching template. If the user appended text after the sub-command, include it
   in the comment as a note.
6. After `done`:
   - if a local branch for this issue still exists and `gh pr view <branch>`
     shows no merged PR, add one line — *"Branch `<branch>` isn't merged yet —
     `/youtrack-task pr` or `/ship` to integrate it."* No git action.
   - otherwise run `scripts/sweep-worktrees` (from this skill's `scripts/` dir)
     and report its `REMOVED` / `KEPT_DIRTY` / `KEPT_OPEN` lines. It removes only
     clean worktrees whose PR is merged/closed — never `--force`, never `-D`,
     never a dirty one.

Never move an issue backward. `testing` / `done` change YouTrack state and, via
`sweep-worktrees`, only ever *remove* finished worktrees — they never create or
switch branches.

## log

`/youtrack-task log [ISSUE-ID] <duration> [description...]`

1. Resolve issue ID (explicit arg, else from branch, else ask).
2. `<duration>` is the next token, in YouTrack period format (`1h`, `30m`,
   `1h30m`, `2d`). If it doesn't parse as a period, stop and show the format.
3. Everything after `<duration>` is the work description (optional).
4. Call `mcp__youtrack__log_work` with issue, duration, and description.
5. Confirm what was logged.

## comment

`/youtrack-task comment <text...>`

1. Resolve issue ID from the current branch (else ask).
2. `mcp__youtrack__add_issue_comment` with the verbatim text (no emoji prefix
   added — the user's words stand as-is).
3. Confirm.

## new

```
/youtrack-task new "<free text describing the work>"     # free-text mode
/youtrack-task new [--project KEY] [--title "..."] [--description "..."] [--priority NAME] [--type NAME]
                  [--assignee LOGIN|EMAIL]
```

Create a new YouTrack issue. Two ways to supply the content:

- **Free-text mode** — the first non-flag argument is a prose blob (has spaces
  and isn't a bare project key), or `--from-text "..."` is given. The skill
  generates the title and a structured description from it (see step 0).
- **Field mode** — pass `--title` / `--description` etc.; any missing required
  field (project, title, description) is asked for, one at a time.

Bare `/youtrack-task new` → ask first: *"Paste a free-text description, or fill
the fields one by one?"*

### 0. Free-text mode: generate title + description

Follow `reference/issue-template.md`:
- Produce a `title` (one imperative line, ≤ 70 chars, no type word) in the
  language of the input — never translated to English.
- Produce a `description` in the fixed sections
  (Summary / Context / Goal / Acceptance criteria / Scope / Technical notes? /
  Open questions?), in the language of the input.
- Do not invent facts — gaps go in **Open questions**.
- Field mode counts too: if only one of `--title` / `--description` is given, the
  field you generate or ask for follows the language of the one that was given.
- `--title` / `--description` passed alongside free text override the generated
  value for that field; a given `--title` is used verbatim (no translation).
- If the text **explicitly** names an assignee (*"assign to max.muster"*,
  *"für max.muster"*, *"@max.muster"*), take it as the requested assignee —
  a merely mentioned name is not one. `--assignee` overrides it.

Then continue with steps 1–4 using the generated values. Priority is still only
set if the input explicitly signals urgency (then propose + ask) or `--priority`
is given.

### 1. Resolve the fields

**project** (required)
- `--project KEY` if given.
- Else resolve the current repo's project with "Resolving a project" and offer
  it: *"Create in `ADMIN` (this repo)? or name another project."* Never tell the
  user a project doesn't exist unless that procedure ran to the end.
- Else list **all** projects (paginated, see "Resolving a project" step 3) and ask.
- Validate the key exists (`mcp__youtrack__get_project`) before continuing.

**title** (required) — `--title` or ask.

**description** (required) — `--description` or ask. Multi-line is fine.

**type**
- `--type NAME` → validate against the project's allowed Type values and use it.
- Omitted → **infer** from title + description: pick one of the project's allowed
  Type values (Bug / Cosmetics / Feature / Task / Epic or whatever the schema
  lists), and show it with a one-line rationale for confirmation —
  *"Type: Bug (title mentions 'Fehler' / 'korrigieren'). OK, or pick another?"*
  Never create with an inferred Type unconfirmed. If inference is genuinely
  unclear and `default_new_type` is set in config, propose that instead.

**priority** (optional)
- `--priority NAME` → validate against the schema and use it.
- Omitted → leave unset; YouTrack applies the project default. Do not infer.

**assignee** — always set; defaults to the API-key owner.
- `mcp__youtrack__get_current_user` → the token's owner (the **key owner**).
- No assignee requested (`--assignee` / free text) → the key owner.
- Requested → `mcp__youtrack__find_user` with the given login or email.
  Found → that user's login. Not found → **fall back to the key owner** and flag
  it in step 3: *"Assignee: `<owner>` (⚠ `<requested>` not found → API-key
  owner)"*. Don't stop to ask — the step-3 confirmation is where it's corrected.

### 2. Read the schema

`mcp__youtrack__get_issue_fields_schema` for the project → exact field names and
allowed value spellings for Type and Priority. Match user/inferred values to the
schema's spelling (case-insensitive); if no match, show the allowed values and
ask. If the schema has no `Assignee` field, drop the assignee and say so in
step 3 (*"no Assignee field in `<PROJECT>` — created unassigned"*).

### 3. Confirm, then create

Show the assembled issue — project, title, full description, Type, Priority
(or "project default"), Assignee (with the ⚠ fallback note if step 1 fell back),
and a **Language** line (*"Language: German (from your input) — say so if it
should be English"*) — and get **one confirmation**. If the title and the
description are not in the language named on that line, fix that before showing
anything. The user may edit any field here before
confirming, including the Language and changing or clearing the Assignee; a new assignee login is
checked with `find_user` again. Editing one field does not regenerate the others
(an edited title leaves the generated description as-is) — except the Language:
changing it regenerates title and description in the new language.

Then `mcp__youtrack__create_issue` with project, summary (= title), description,
and the Type / Priority / Assignee custom fields (Assignee = the login). If the
create call can't set a custom field (listed in `failedToUpdateFields`, or
absent from `updatedFields`), follow up on the new issue —
`mcp__youtrack__change_issue_assignee` for Assignee, `mcp__youtrack__update_issue`
for the rest.

### 4. Report and offer pickup

Report the new issue ID, its URL, project, Type, Priority, Assignee (or why it's
unassigned), title. Then offer:
*"Pick it up now? → `/youtrack-task <new-ID>`"* (branch + In Progress + plan).
Don't chain automatically.

Creating is one MCP write; on failure report what failed and stop (nothing half-
created to clean up unless a follow-up `update_issue` / `change_issue_assignee`
failed after `create_issue` — then say the issue exists but that field didn't
stick).

## pr

`/youtrack-task pr [ISSUE-ID] [--no-move] [--base <branch>] [--draft] [--no-review]
                  [--confirm-pr | --no-confirm-pr]`

Push the current feature branch, open a GitHub PR, record it on the issue, and
move the issue to Testing. This is the one place the skill is allowed to push.
Requires `gh` on `PATH` (`gh --version`); if missing, stop and tell the user to
push + open the PR themselves, then run `/youtrack-task link <url>`.

1. Resolve the issue ID (leading arg → branch → ask).
2. Checks, all must pass or stop:
   - inside a git repo, and **not** on the default branch (resolve the default
     the same way as `reference/branching.md`; `--base` overrides).
   - the branch has commits ahead of the base (`git rev-list --count <base>..HEAD`
     > 0), else *"no commits on this branch"*.
   - clean working tree. If dirty, warn that uncommitted changes won't be in the
     PR and ask whether to continue. Recording a waiver (last bullet) needs a clean
     tree, so on that path commit or stash first.
   - **reviewed** (not checked when `review_before_pr = never` or `--no-review`,
     see the last bullet): run
     `scripts/review-stamp check --id <ID>` per `reference/review.md`.
     `PASS` with `INDEPENDENT=yes` → continue. `STALE` / `MISSING` → run the review
     gate now (`fixer = main-session`; it needs a clean tree, so a dirty tree is
     committed or the user is asked first), then continue on `PASS`. `FAILED` →
     stop and show the open findings. `PASS` with `INDEPENDENT=no` → say the review
     was not independent and continue only on explicit confirmation.
   - `--no-review` and `review_before_pr = never` are the only ways past the gate.
     With the flag, ask for explicit confirmation naming the risk (*"this branch
     has no independent review"*); with the standing config no extra question is
     needed. Either way record the waiver (`review-stamp write --verdict SKIPPED
     --independent no`, see `reference/review.md`), and add the line `Review:
     skipped (not independently reviewed)` to the PR body and to the YouTrack PR
     comment. Never skip silently. A `SKIPPED` stamp already on this commit counts
     as that confirmation.
3. Show `git log --oneline <base>..HEAD` and `git diff --stat <base>...HEAD`
   (always), then decide from the step-0 output:

   | `--no-confirm-pr`, or `CONFIRM_PR=false` without `--confirm-pr` | do this |
   | --- | --- |
   | yes | print one line `→ Pushing <branch> and opening a PR (confirm_pr off)` and go on to step 4. **No question.** |
   | no | **ask for confirmation** before pushing. |

   This table gates only the push-and-PR question. The checks in step 2 (default
   branch, commits ahead, dirty tree, review gate, `--no-review` confirmation) are
   unaffected and still stop or ask as written there.
4. `git push -u origin <branch>` (plain push; never `--force`).
5. Open the PR:
   - If `gh pr view <branch> --json url,state` already shows an open PR, reuse its
     URL — don't create a second one.
   - Else `gh pr create --base <base> --head <branch> --title "<ID>: <clean-summary>"
     --body "<body>"` (`--draft` if the flag was passed). `<clean-summary>` is the
     issue title **in English** (translate if the issue isn't), with the
     leading type word stripped — same as the slug rule in `reference/branching.md`
     (`"Bugfix: Hover-Effekt bei markierten Zeilen"` → `"Keep row tint visible on hover"`).
     If the repo has `.github/pull_request_template.md` or
     `.github/PULL_REQUEST_TEMPLATE/`, fill that template and append the lines
     below rather than replacing it.
   - `<body>` is **English** and always includes: a link to the YouTrack issue
     (`<YOUTRACK_MCP_URL without /mcp>/issue/<ID>`), a one-line summary, and a
     short bullet list of the commits. The merge commit inherits this title, so
     it must not carry non-English text.
6. Capture the PR URL from the command output.
7. YouTrack write-back:
   - `add_issue_comment`: the `pr` template from `reference/writeback.md`
     (`🔗 PR opened: <url>` — add `, moved to Testing` when step 8 moves it).
   - Unless `--no-move`: if the issue is before `testing_state` on the ladder,
     `update_issue` → `testing_state`. Skip silently if already at Testing/Done.
8. Run `scripts/sweep-worktrees --exclude <this-branch>` (from this skill's
   `scripts/` dir) to clear worktrees whose PR has already merged/closed. Report
   its `REMOVED` lines. **This** worktree stays — the PR is open, review fixes go
   here; `/youtrack-task done` (or `worktree prune`) removes it once merged.
9. Report: PR URL, whether it was newly created or already existed, the state
   change, what `sweep-worktrees` cleaned up, and that `/youtrack-task done` is
   the step after the PR merges.

## link

`/youtrack-task link [ISSUE-ID] <pr-url>`

Attach an already-existing PR (from `/ship`, `gh`, or the web UI) to the issue.
Does not push and does not change state.

1. Parse args: if the first token is an issue ID, the second is the URL; otherwise
   the first token is the URL and the issue ID comes from the branch (else ask).
2. Sanity-check the URL is `http(s)://…`; warn (don't block) if it isn't a
   `…/pull/<n>` GitHub URL.
3. `mcp__youtrack__add_issue_comment`: `🔗 PR: <url>`.
4. Confirm.

## worktree

`/youtrack-task worktree list|prune|take|remove`  (see `reference/worktrees.md`)

- **`list`** — `git worktree list` filtered to worktrees under `worktree_dir`
  whose name looks like `<ID>-<slug>`; for each, show the branch and the issue's
  current YouTrack state (`get_issue`).
- **`prune`** — run `scripts/sweep-worktrees` (from this skill's `scripts/` dir)
  and report every line. It removes clean worktrees whose PR is merged/closed and
  `git branch -d`s the merged branch, then `git worktree prune`; dirty ones and
  still-open PRs are listed, not touched. Never `--force`, never `git branch -D`.
- **`take <ISSUE-ID>`** — you want that issue's branch in your *current* checkout
  but a worktree still holds it. Run `scripts/worktree-detach --id <ID> --switch`:
  it removes that worktree (branch kept) and `git switch`es to the branch here.
  A dirty worktree is refused (`ERROR=dirty` — commit/stash in it first); the
  switch is skipped if the current checkout has tracked changes. Report `REMOVED`
  / `SWITCHED` / any `NOTE`.
- **`remove <ISSUE-ID>`** — just drop the worktree, don't switch:
  `scripts/worktree-detach --id <ID>`. Same safety; the branch survives.

## all

```
/youtrack-task all [ID ...] [--max N] [--no-review] [--dry-run] [--auto-merge]
```

Work through several issues in one run. The contract — triage rules, briefings,
the review loop, PR and merge conditions — is `reference/batch.md`; follow it,
don't improvise. Needs the plugin's `ticket-worker` and `ticket-reviewer` agents
(without subagent support, see the fallback in `batch.md`).

- `ID ...` — explicit issues (full IDs only; the prefix names the project, so no
  project lookup is needed); without them `batch_query` picks the candidates.
- `--max N` — parallel workers (default `batch_max_parallel`).
- `--no-review` — skip the independent reviewer.
- `--dry-run` — triage table only; no workspace, no write.
- `--auto-merge` — the run may merge the PRs it opened, when review is `PASS`,
  required checks are green and the PR is mergeable. Off by default; never
  implied by anything else.

Flow, in short:

1. **Triage** (read-only): classify issues *ready* / *needs-human* / *blocked*,
   print one table, ask **one** confirmation (it names whether auto-merge is on).
2. **Setup**, serial: `setup-workspace --mode worktree` + pickup write-back.
3. **Work**, parallel and in the background: one `ticket-worker` per issue.
4. **Review**: the shared review gate (`reference/review.md`) per issue with
   `fixer = ticket-worker`: a fresh `ticket-reviewer` that sees only the issue and
   the diff, never the worker's report; up to `review_rounds` fix rounds.
5. **Report** with overlap warnings; completion comments to YouTrack.
6. **PRs** after one confirmation for the whole list (the main session pushes
   each reviewed branch).
7. **Merge** only with `--auto-merge`.

Only the main session writes to YouTrack, pushes and merges; workers commit
locally. Issues tagged with one of
`batch_skip_tags`, or that look like server / network / secret / data-store work,
are never run unattended.

## Notes

- Every YouTrack write is one MCP call; on a 403 report which call/issue failed
  and keep going (in the primary flow the branch already exists).
- Re-resolve the state field per project; field names can differ.
- Do not invent custom-field names — always read the schema first.
