---
name: youtrack-task
description: Use when the user runs /youtrack-task, or asks to pick up / start / work on / plan a JetBrains YouTrack issue. Fetches the issue over the YouTrack MCP server, creates a git branch, moves the issue to In Progress, drives planning, and writes results back to the issue. Also handles /youtrack-task comment|log|testing|done.
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
| *(none)* or looks like an issue ID (`^[A-Z][A-Z0-9_]+-\d+$`) | **Primary flow** (below) |
| `comment` | `add_issue_comment` with the rest of the line, to the current branch's issue |
| `log` | time logging — see "log" below |
| `testing` | move the issue to `testing_state` — see "state sub-commands" |
| `done` | move the issue to `done_state` — see "state sub-commands" |

For `comment` / `log` / `testing` / `done`, resolve the issue ID from an explicit
argument if given, else extract `[A-Z]+-\d+` from `git branch --show-current`,
else ask the user.

---

## Primary flow

### 1. Resolve the issue ID

- Arg matches `^[A-Z][A-Z0-9_]+-\d+$` → use it.
- Else `git branch --show-current`; if it contains `[A-Z]+-\d+`, extract it and
  ask: *"Continue on `<ID>` (from branch `<branch>`)?"* — proceed only on yes.
- Else `mcp__youtrack__search_issues` with `list_query`. Show a numbered list:
  `<ID> — <summary> — <state>`. Let the user pick one. If the list is empty, say
  so and ask for an explicit ID.

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
- compute `<prefix>/<ID>-<slug>`
- guard on dirty tree (offer `git stash push -u`) and on an existing branch
  (offer `git switch` instead of recreating)
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

Never move an issue backward.

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

## Notes

- Every YouTrack write is one MCP call; on a 403 report which call/issue failed
  and keep going (in the primary flow the branch already exists).
- Re-resolve the state field per project; field names can differ.
- Do not invent custom-field names — always read the schema first.
