# youtrack-task — Design Spec

Status: **approved 2026-09-06 — in implementation**
Date: 2026-09-06

## Purpose

Start work on a JetBrains YouTrack issue from inside any project directory with a
single command. Claude fetches the issue, creates a correctly named git branch,
moves the issue to *In Progress*, builds an implementation plan, and writes that
plan back to the issue as a comment.

Replaces the manual loop of: open PhpStorm YouTrack plugin → read issue → think of
a branch name → create branch → copy the description into Claude.

## Non-goals

- No dependency on the PhpStorm YouTrack plugin or the JetBrains MCP server. The
  plugin exposes no "active task" over MCP, so this tool is self-contained.
- No local mirror of YouTrack state, no caching, no sync daemon.
- Not a general YouTrack client. It does exactly the "pick up an issue and plan
  it" flow, plus a few explicit follow-up sub-commands.

## Distribution

A **public** Claude Code plugin repo: `github.com/JtheGunner/youtrack-task`.

```
youtrack-task/
├── .claude-plugin/
│   ├── plugin.json          # name, version, metadata
│   └── marketplace.json     # so `/plugin marketplace add JtheGunner/youtrack-task` works
├── .mcp.json                # YouTrack HTTP MCP server, values from env vars
├── skills/
│   └── youtrack-task/
│       ├── SKILL.md         # the workflow, user-invocable as /youtrack-task
│       └── reference/
│           ├── branching.md # branch-name + type→prefix rules
│           └── writeback.md # state-transition + comment rules
├── config.example.toml      # documents every optional override, dummy values only
├── README.md                # setup: 2 env vars + token, then /plugin install
├── LICENSE                  # MIT
└── SPEC.md                  # this file
```

### Nothing instance-specific in the repo

The repo is public and must leak neither the YouTrack URL nor any
project↔repo mapping.

| Concern | Where it lives |
| --- | --- |
| YouTrack MCP endpoint URL | env var `YOUTRACK_MCP_URL` (e.g. `https://…/mcp`) |
| Permanent API token | env var `YOUTRACK_TOKEN` |
| Which YT project an issue belongs to | encoded in the issue ID itself (`INFRA-42` → `INFRA`) — never stored |
| Saved-search name, state labels, prefix map | defaults in `SKILL.md`; overridable in `~/.config/youtrack-task/config.toml` (outside the repo) |

`.mcp.json`:

```json
{
  "mcpServers": {
    "youtrack": {
      "url": "${YOUTRACK_MCP_URL}",
      "headers": { "Authorization": "Bearer ${YOUTRACK_TOKEN}" }
    }
  }
}
```

`${ENV_VAR}` expansion in `url` and `headers` is supported for plugin-bundled MCP
servers, so the repo ships only placeholders.

## Prerequisites (one-time, user)

1. YouTrack ≥ 2025.3 with the remote MCP server reachable (user runs 2026.2;
   Authelia bypass for `/mcp` already in place).
2. Create a permanent token: YouTrack → Profile → Account Security → New token,
   scope *YouTrack*.
3. Set in the shell environment (omnishell / zshrc):
   - `export YOUTRACK_MCP_URL="https://<host>/mcp"`
   - `export YOUTRACK_TOKEN="perm:…"`
4. `/plugin marketplace add JtheGunner/youtrack-task` then `/plugin install youtrack-task`.

## MCP tools used

From the YouTrack predefined MCP tool set, namespaced by Claude Code as
`mcp__youtrack__<name>`:

| Tool | Used for |
| --- | --- |
| `get_current_user` | resolve "me" for the issue list |
| `search_issues` | list candidate issues when no ID is given |
| `get_issue` | fetch summary, description, fields, state, type |
| `get_issue_fields_schema` | learn the project's state/type field names + allowed values before writing |
| `get_issue_comments` | read existing context on the issue |
| `update_issue` | move state to *In Progress* (and later *Testing*/*Done*) |
| `add_issue_comment` | post the pickup note and the plan |
| `log_work` | `/youtrack-task log` sub-command |
| `link_issues` | future: link the GitHub PR / sub-tasks |

The skill never hardcodes custom-field names. It calls `get_issue_fields_schema`
first and matches the state field by role (the field whose allowed values include
something like *In Progress*), so it works across projects with slightly
different field setups.

## Command surface

Primary:

```
/youtrack-task [ISSUE-ID] [--no-move] [--no-writeback] [--base <branch>]
```

Sub-commands (same skill, dispatched on first arg). All ship in v1.

```
/youtrack-task comment <text>                           # add_issue_comment to the current branch's issue
/youtrack-task log [ISSUE-ID] <duration> [description]  # log_work; issue inferred from branch if omitted
/youtrack-task testing [ISSUE-ID]                       # move state → Testing
/youtrack-task done [ISSUE-ID]                          # move state → Done
```

State ladder: `Open → In Progress → Testing → Done`. Pickup moves `Open → In
Progress` automatically; `testing` and `done` are explicit steps the user runs.
When `ISSUE-ID` is omitted for `comment` / `log` / `testing` / `done`, it is
extracted from the current git branch name; if that fails, the skill asks.

## Primary flow

### 1. Resolve the issue ID

- Arg matches `^[A-Z][A-Z0-9_]+-\d+$` → use it.
- Else read `git branch --show-current`; if it contains `[A-Z]+-\d+`, extract and
  ask the user to confirm ("Continue on INFRA-42 from branch `feat/INFRA-42-…`?").
- Else `search_issues` with `for: me #Unresolved State: {In Progress}, {Open}
  sort by: updated desc` (query overridable via config `list_query`), show a
  numbered list (ID — summary — state), user picks one.
- Nothing found / ambiguous → stop and ask.

### 2. Fetch context

`get_issue` + `get_issue_comments`. Present a 3–6 line summary: ID, title, type,
priority, state, subsystem if present, and the gist of the description.

### 3. Repo sanity check

- `git rev-parse --is-inside-work-tree` must succeed, else stop.
- `git remote get-url origin` → derive repo slug. Compare loosely to the issue's
  project (short name / project name from `get_project`). On mismatch: warn once
  and ask whether to continue ("Issue is in project PORT but this repo looks like
  `admin-dashboard-vue` — continue anyway?"). Never hard-block; the user may have
  a legitimate reason.

### 4. Create the branch

- Base: `--base` if given, else the repo default branch resolved via
  `git symbolic-ref refs/remotes/origin/HEAD` (fallback `main`, then `master`).
- `git fetch origin <base>` then branch from `origin/<base>`.
- Name: `<prefix>/<ID>-<slug>`
  - `<prefix>` from the issue Type via `reference/branching.md`
    (Bug→`fix`, Feature→`feat`, Task→`chore`, Epic→`feat`, Cosmetics→`style`;
    default `chore`; overridable in config `type_prefix`).
  - `<slug>` = summary → lowercase, non-alphanumeric to `-`, collapsed, trimmed,
    max 50 chars.
  - Full name capped at 60 chars.
- Guards: refuse if working tree is dirty (ask to stash/commit first); if the
  target branch already exists, offer to switch to it instead of recreating.
- `git switch -c <branch> origin/<base>`.

### 5. Write-back on pickup (default on)

- `get_issue_fields_schema` → find the state field and its "in progress" value.
- If the issue's state is not already *In Progress* (or a later state), call
  `update_issue` to set it. Skip silently if already there or later.
- `add_issue_comment`: `🤖 Picked up in Claude Code — branch \`<branch>\` off \`<base>\`.`
- `--no-move` skips the state change; `--no-writeback` skips both the state change
  and the pickup comment.

### 6. Build the plan

- Hand the issue (title + description + relevant comments) to the normal planning
  workflow (`superpowers:brainstorming` / plan mode), exploring the current repo
  for affected files.
- Output: a plan the user reviews in chat.

### 7. Write-back the plan (on user confirmation)

- After the user approves the plan, `add_issue_comment` with the plan rendered as
  Markdown, prefixed `## Implementation plan (Claude Code)` and dated.
- If — and only if — the repo already contains a `docs/` directory, also write
  `docs/plans/<ID>.md` with the same content. No `docs/` → no local file, no
  directory creation. Controlled by config `local_plan_copy` (`auto` default /
  `always` / `never`).

## Configuration file

`~/.config/youtrack-task/config.toml`, all keys optional:

```toml
# list_query        = "for: me #Unresolved State: {In Progress}, {Open} sort by: updated desc"
# in_progress_state = "In Progress"   # state name used on pickup
# testing_state     = "Testing"       # target of `/youtrack-task testing`
# done_state        = "Done"          # target of `/youtrack-task done`
# local_plan_copy   = "auto"          # auto | always | never
#
# [type_prefix]
# Bug = "fix"
# Feature = "feat"
# Task = "chore"
```

`config.example.toml` in the repo is this block with every line commented and
dummy values — no real query, no real state names beyond YouTrack defaults.

## Error handling

| Situation | Behavior |
| --- | --- |
| `YOUTRACK_MCP_URL` / `YOUTRACK_TOKEN` unset | MCP server fails to start; skill detects no `mcp__youtrack__*` tools and prints the 3-line setup instructions from the README. |
| Issue ID not found (`get_issue` 404) | Stop, show the ID tried, suggest `/youtrack-task` with no arg to pick from the list. |
| Not in a git repo | Stop before any MCP call. |
| Dirty working tree | Stop before branching; offer `git stash`. |
| State field not identifiable from schema | Skip the state change, warn, still post the pickup comment and continue to planning. |
| MCP write fails (403 / permission) | Report which call failed; branch is already created, so continue to planning and tell the user the write-back did not land. |

## Testing

Manual, against the user's real YouTrack (no mock server in v1):

1. `/youtrack-task` with no arg in a repo → list appears, pick one, branch
   created, issue moves to *In Progress*, pickup comment visible in PhpStorm.
2. `/youtrack-task INFRA-<n>` explicit ID → same, no list.
3. Run from a branch already named `…INFRA-<n>…` → prompts to continue on that
   issue, no list.
4. `--no-move --no-writeback` → branch only, YouTrack untouched.
5. Dirty tree → refused with stash hint.
6. Wrong repo for the issue's project → mismatch warning, can override.
7. Plan approval → plan comment lands on the issue; `docs/plans/<ID>.md` created
   only in a repo that has `docs/`.
8. Unset one env var → helpful setup message, no stack trace.

A short `tests/README.md` records this checklist for re-runs after changes.

## Guardrails (added 2026-09-06 after first live run)

The skill drives setup + planning and may continue into implementation once the
plan is approved, but never crosses these without explicit per-action approval:

- No commits on the repo's default branch (pre-existing dirty changes → stash or
  carry onto the feature branch).
- No `git commit --no-verify`, no amend / history rewrite. A failing hook stops
  the flow and is reported.
- No writes to databases / seed data / fixtures / credentials — including for QA.
- No servers/daemons started without asking.
- No `git push`, no PR, no force-push — that is `/ship` or the user's call.
- Branch slug: leading type word stripped ("Bugfix:", "Feature/Refactoring:"),
  40-char cap, name shown for accept/rename before use.

## Resolved decisions (2026-09-06)

1. State ladder is `Open → In Progress → Testing → Done`. `/youtrack-task testing`
   and `/youtrack-task done` are both provided; `done` moves to *Done*.
2. v1 ships the full surface: primary flow + `comment` + `log` + `testing` + `done`.
3. Emoji in write-back comments is fine (📌 pickup, 📝 plan, ⏱️ log, ✅ done).
4. After implementation: a written "how it works" walkthrough, then a joint test
   run against real YouTrack issues.

---

Attribution: implementation commits will carry
`Claude-Session: https://claude.ai/code/session_016V1ZNsh7y2kFyqW7A7FHsu`.
