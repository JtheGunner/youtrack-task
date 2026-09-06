---
name: youtrack-task
description: Use when the user runs /youtrack-task, or asks to pick up / start / work on / plan a JetBrains YouTrack issue. Fetches the issue over the YouTrack MCP server, creates a git branch, moves the issue to In Progress, drives planning, and writes results back to the issue. Also handles /youtrack-task comment|log|pr|link|testing|done.
---

# youtrack-task

Pick up a YouTrack issue and turn it into a running branch + a reviewed plan,
with state and comments written back to YouTrack.

## Preconditions

Before doing anything, confirm the YouTrack MCP server is available: the tools
`mcp__youtrack__get_issue`, `mcp__youtrack__search_issues`, etc. must exist.

If they do **not** exist, stop and print:

> The YouTrack MCP server isn't connected. Set these in your shell env and restart Claude Code:
> - `export YOUTRACK_MCP_URL="https://<your-youtrack-host>/mcp"`
> - `export YOUTRACK_TOKEN="<permanent token from YouTrack → Profile → Account Security>"`
> Then reinstall/enable the plugin. See the plugin README.

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
  the user's own `/ship`), after a confirmation prompt. Never as an implicit part
  of the primary flow, `done`, or anything else. **Never force-push**, never
  merge a PR, never delete a branch.
- The only YouTrack writes are: the pickup state change + comment, the plan
  comment, an optional one-line completion comment, and the explicit
  `comment` / `log` / `pr` / `link` / `testing` / `done` sub-commands.

## Config

Optional file `~/.config/youtrack-task/config.toml`. Read it if present; every key
is optional. Defaults:

| Key | Default |
| --- | --- |
| `list_query` | `for: me #Unresolved State: {In Progress}, {Open} sort by: updated desc` |
| `in_progress_state` | `In Progress` |
| `testing_state` | `Testing` |
| `done_state` | `Done` |
| `local_plan_copy` | `auto` |
| `[type_prefix]` table | see `reference/branching.md` |

## Dispatch on the first argument

| First arg | Action |
| --- | --- |
| *(none)*, an issue ID (`^[A-Z][A-Z0-9_]+-\d+$`), or a bare number | **Primary flow** (below) |
| `comment` | `add_issue_comment` with the rest of the line, to the current branch's issue |
| `log` | time logging — see "log" below |
| `pr` | push the branch, open a PR, link it on the issue, move to Testing — see "pr" below |
| `link` | attach an existing PR URL to the issue as a comment — see "link" below |
| `testing` | move the issue to `testing_state` — see "state sub-commands" |
| `done` | move the issue to `done_state` — see "state sub-commands" |

For `comment` / `log` / `pr` / `link` / `testing` / `done`, resolve the issue ID
from an explicit leading `ISSUE-ID` argument if given, else extract `[A-Z]+-\d+`
from `git branch --show-current`, else ask the user.

---

## Primary flow

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

**Current repo's project key:** derive it from the git remote / cwd and match it
against YouTrack projects (`mcp__youtrack__find_projects` / `get_project`), or take
the dominant project prefix among the issues returned by `list_query` for this
repo. This is the same project used for the sanity check in step 3.

### 2. Fetch context

- `mcp__youtrack__get_issue` for full detail.
- `mcp__youtrack__get_issue_comments` for existing discussion.

Show the user a short brief: ID, title, Type, Priority, State, Subsystem (if the
issue has one), and a 2–4 sentence gist of the description + any decisive comment.

### 3. Repo sanity check

- `git rev-parse --is-inside-work-tree` must succeed. If not, stop: *"Not inside a
  git repository — cd into the project first."*
- `git remote get-url origin` → repo slug. Compare loosely to the issue's project
  (use `mcp__youtrack__get_project` for its name / short name). On a clear
  mismatch, warn once: *"`<ID>` is in project `<PROJ>` but this repo looks like
  `<slug>` — continue anyway?"* Continue only on yes. Never hard-block.

### 4. Create the branch

Follow `reference/branching.md` exactly:
- resolve base branch, `git fetch origin <base>`
- compute `<prefix>/<ID>-<slug>` (leading type word stripped, 40-char slug cap),
  show it, let the user accept or rename
- dirty tree → stash or carry onto the feature branch per `branching.md`; **never
  commit on the base branch**
- existing branch → `git switch` instead of recreating
- `git switch -c <branch> origin/<base>`

Report the branch created and the base it started from.

### 5. Write-back on pickup

Skip this whole step if `--no-writeback` was passed.

Follow `reference/writeback.md`:
- resolve the state field via `get_issue_fields_schema`
- if the issue is before `In Progress` on the ladder, `update_issue` → `in_progress_state`
  (skip silently if already at In Progress / Testing / Done)
- `add_issue_comment` with the pickup template

`--no-move` skips only the state change, keeps the pickup comment.

### 6. Plan the work

Hand the issue (title + description + relevant comments) into the normal planning
workflow — invoke `superpowers:brainstorming` if available, otherwise enter plan
mode. Explore the current repo for the files the change touches. Produce a plan
and present it to the user for review. Iterate until they approve it.

### 7. Write-back the plan

Only after the user approves the plan:
- `mcp__youtrack__add_issue_comment` with the plan rendered as Markdown, using the
  plan template from `reference/writeback.md`.
- `local_plan_copy`:
  - `auto` (default): if the repo already has a `docs/` directory, also write
    `docs/plans/<ID>.md` with the same content. No `docs/` → skip, don't create it.
  - `always`: always write `docs/plans/<ID>.md` (create `docs/plans/` if needed).
  - `never`: never write a local file.

Then summarise what landed where (branch, YouTrack state, comment URL if the MCP
result includes one, local file if written).

### 8. Implement (optional)

If the user wants to proceed with the implementation now, continue in the normal
development workflow (TDD where it applies) — bound by the **Guardrails** above.
When the implementation is done, post one short completion comment to the issue
(`add_issue_comment`, template in `reference/writeback.md`) listing the branch and
the files touched. Do not push, open a PR, or move the issue here — tell the user
the branch is ready and that `/youtrack-task pr` (push + PR + link + move to
Testing) or their own `/ship` is the next step.

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
6. After `done`: if a local branch for this issue still exists and `gh pr view
   <branch>` shows no merged PR, add one line — *"Branch `<branch>` isn't merged
   yet — `/youtrack-task pr` or `/ship` to integrate it."* No git action.

Never move an issue backward. These commands never touch git.

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

## pr

`/youtrack-task pr [ISSUE-ID] [--no-move] [--base <branch>] [--draft]`

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
     PR and ask whether to continue.
3. Show `git log --oneline <base>..HEAD` and `git diff --stat <base>...HEAD`, then
   **ask for confirmation** before pushing.
4. `git push -u origin <branch>` (plain push; never `--force`).
5. Open the PR:
   - If `gh pr view <branch> --json url,state` already shows an open PR, reuse its
     URL — don't create a second one.
   - Else `gh pr create --base <base> --head <branch> --title "<ID>: <summary>"
     --body "<body>"` (`--draft` if the flag was passed). If the repo has
     `.github/pull_request_template.md` or `.github/PULL_REQUEST_TEMPLATE/`,
     fill that template and append the lines below rather than replacing it.
   - `<body>` always includes: a link to the YouTrack issue
     (`<YOUTRACK_MCP_URL without /mcp>/issue/<ID>`), a one-line summary, and a
     short bullet list of the commits.
6. Capture the PR URL from the command output.
7. YouTrack write-back:
   - `add_issue_comment`: the `pr` template from `reference/writeback.md`
     (`🔗 PR opened: <url>` — add `, moved to Testing` when step 8 moves it).
   - Unless `--no-move`: if the issue is before `testing_state` on the ladder,
     `update_issue` → `testing_state`. Skip silently if already at Testing/Done.
8. Report: PR URL, whether it was newly created or already existed, the state
   change, and that `/youtrack-task done` is the step after the PR merges.

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

## Notes

- Every YouTrack write is one MCP call; on a 403 report which call/issue failed
  and keep going (in the primary flow the branch already exists).
- Re-resolve the state field per project; field names can differ.
- Do not invent custom-field names — always read the schema first.
