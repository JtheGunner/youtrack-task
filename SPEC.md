# youtrack-task — Design Spec

Status: **shipped — v0.4.0** (this doc tracks the design; see git tags for what landed when)
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
│           ├── branching.md      # branch-name + type→prefix rules
│           ├── writeback.md      # state-transition + comment rules
│           ├── issue-template.md # structure for `new` free-text generation
│           └── superpowers.md    # routing for the superpowers plan/impl path
├── config.example.toml      # documents every optional override, dummy values only
├── README.md                # setup: 2 env vars + token, then /plugin install
├── LICENSE                  # MIT
└── SPEC.md                  # this file
```

### Language

Git artifacts — branch names, commit messages, PR titles and bodies, locally
written plan / design docs — are **always English**, whatever language the issue
is in (the skill translates the summary). YouTrack-side text follows the issue's
language: comments mirror it, and `/youtrack-task new` writes the issue in the
input's language.

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
| `find_projects` | resolve / list projects for `/youtrack-task new` |
| `create_issue` | `/youtrack-task new` |
| `link_issues` | future: link the GitHub PR / sub-tasks |

The skill never hardcodes custom-field names. It calls `get_issue_fields_schema`
first and matches the state field by role (the field whose allowed values include
something like *In Progress*), so it works across projects with slightly
different field setups.

## Command surface

Primary:

```
/youtrack-task [ISSUE-ID | N] [--no-move] [--no-writeback] [--base <branch>]
               [--checkpoints] [--review | --no-review]
```

`--checkpoints` runs an architectural plan's execution with review stops
(`superpowers:executing-plans`). `--review` / `--no-review` force / skip the
automatic code review in the implement step.

Sub-commands (same skill, dispatched on first arg). All ship in v1.

```
/youtrack-task new "<free text>"   |   new [--project KEY] [--title …] [--description …] [--priority N] [--type N]
/youtrack-task comment <text>                           # add_issue_comment to the current branch's issue
/youtrack-task log [ISSUE-ID] <duration> [description]  # log_work; issue inferred from branch if omitted
/youtrack-task pr [ISSUE-ID] [--no-move] [--base <b>] [--draft]  # push + gh PR + link on issue + → Testing
/youtrack-task link [ISSUE-ID] <pr-url>                 # attach an existing PR URL as a comment
/youtrack-task testing [ISSUE-ID]                       # move state → Testing
/youtrack-task done [ISSUE-ID]                          # move state → Done
```

State ladder: `Open → In Progress → Testing → Done`. Pickup moves `Open → In
Progress` automatically. `pr` is the only command that pushes — it needs `gh`,
prompts before pushing, never force-pushes/merges/deletes, and moves the issue to
Testing. `testing` / `done` are pure state transitions (no git). `done` is always
last: it means "merged and accepted". When `ISSUE-ID` is omitted for any
sub-command it is taken from the current branch name; if that fails, the skill
asks.

Lifecycle: `/youtrack-task new` (optional) → `/youtrack-task <id>` → (implement) →
`/youtrack-task pr` → *review + merge* → `/youtrack-task done`. Users who prefer
their own ship flow run that instead of `pr`, then `/youtrack-task link <url>`.

### `new` — create an issue

Required: `project`, `title`, `description`. Two input modes:

- **Free-text**: `/youtrack-task new "<blob>"` (or `--from-text`). The skill
  generates `title` + a structured `description` per `reference/issue-template.md`
  — fixed sections Summary / Context / Goal / Acceptance criteria / Scope /
  Technical notes? / Open questions?, in the input's language, no invented facts
  (gaps → Open questions). This is the same structure `/youtrack-task <id>` reads
  back when planning, so capture → work loses nothing.
- **Field**: `--title` / `--description` etc.; missing required fields prompted
  one at a time. Bare `new` asks free-text-or-fields first.

Field resolution:
- **project**: `--project` → repo-derived default → `find_projects` list. Validated.
- **type**: `--type` (validated against the project schema) → else inferred from
  the (generated or given) title + description and shown for confirmation; never
  created unconfirmed. `default_new_type` (config) is the fallback when unsure.
- **priority**: `--priority` (validated) → else unset (project default). Not
  inferred, except: free text that explicitly signals urgency → propose + ask.

Flow: resolve/generate fields → `get_issue_fields_schema` for exact spellings →
show the assembled issue, editable, one confirmation → `create_issue` (Type /
Priority as custom fields; `update_issue` fallback) → report ID + URL → offer
pickup (`/youtrack-task <new-ID>`), no auto-chain.

## Primary flow

### 1. Resolve the issue ID

- Arg is a full ID (`^[A-Z][A-Z0-9_]+-\d+$`) → use it.
- Arg is a bare number `N` → qualify with the current repo's project key →
  `<PROJECT>-N`, echo it, proceed on yes.
- No arg → `git branch --show-current`; a `[A-Z]+-\d+` in it → extract, confirm.
- Still nothing → `search_issues` with `list_query` (config-overridable), list
  candidates as `<ID> — <summary> — <state>` (no row numbers). Reply is an issue
  ID; a bare number there is `<PROJECT>-N`, never a list position.
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
- Name: `<prefix>/<ID>-<slug>` per `reference/branching.md`
  - `<prefix>` from the issue Type (Bug→`fix`, Feature→`feat`, Task→`chore`,
    Epic→`feat`, Cosmetics→`style`; default `chore`; config `type_prefix`).
  - `<slug>` = summary with a leading type word stripped ("Bugfix:",
    "Feature/Refactoring:"), lowercased, non-alphanumeric → `-`, 40-char cap.
  - Full name capped at 60 chars. The computed name is shown for accept/rename.
- Guards: never commit on the base branch — a dirty tree is stash-or-carry only
  (`reference/branching.md`); if the target branch exists, offer `git switch`
  instead of recreating.
- `git switch -c <branch> origin/<base>`.

### 5. Write-back on pickup (default on)

- `get_issue_fields_schema` → find the state field and its "in progress" value.
- If the issue's state is not already *In Progress* (or a later state), call
  `update_issue` to set it. Skip silently if already there or later.
- `add_issue_comment`: `🤖 Picked up in Claude Code — branch \`<branch>\` off \`<base>\`.`
- `--no-move` skips the state change; `--no-writeback` skips both the state change
  and the pickup comment.

### 6. Build the plan

- If `superpowers` is available and `use_superpowers` ≠ `never`, route planning
  through it (`reference/superpowers.md`): Bug → `systematic-debugging` then
  design; else `brainstorming`; architectural → also `writing-plans`. The issue
  description's fixed sections map directly onto each skill's inputs (Summary +
  Context + Goal = problem; Acceptance criteria = success criteria; Scope = YAGNI
  boundary; Technical notes = constraints; Open questions = clarifying questions).
- Else: plain plan mode.
- Explore the repo for affected files. Output: a plan the user reviews. Record
  **bounded** vs **architectural** — it decides step 8.

### 7. Write-back the plan (on user confirmation)

- After the user approves the plan, `add_issue_comment` with the plan rendered as
  Markdown, prefixed `## Implementation plan (Claude Code)` and dated.
- If — and only if — the repo already contains a `docs/` directory, also write
  `docs/plans/<ID>.md` with the same content. No `docs/` → no local file, no
  directory creation. Controlled by config `local_plan_copy` (`auto` default /
  `always` / `never`). superpowers architectural plans prefer an existing
  `docs/superpowers/specs/` convention when the repo has one.

### 8. Implement (optional, on user go)

Bound by the Guardrails. superpowers path (`reference/superpowers.md`):
bounded → `test-driven-development` directly; architectural → execute the plan
with `subagent-driven-development` (or `executing-plans` under `--checkpoints`),
TDD per task, then automatic `requesting-code-review` against the acceptance
criteria (`--no-review` skips, `--review` forces, config `review_before_pr`).
Both paths → `verification-before-completion` on the acceptance criteria before
the completion comment. No superpowers → the normal dev workflow + a manual
verification pass. Never pushes / PRs / moves state — that's `pr` / the user.

## Configuration file

`~/.config/youtrack-task/config.toml`, all keys optional:

```toml
# use_superpowers   = "auto"          # auto | always | never
# review_before_pr  = "auto"          # auto (architectural only) | always | never
# default_new_type  = "Task"          # fallback Type for `new` when inference is unsure
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
- Push + PR only in the explicit `pr` sub-command (or the user's own ship flow),
  after a confirmation prompt. Never as part of the primary flow or `done`. Never
  force-push, merge a PR, or delete a branch.
- Branch slug: leading type word stripped ("Bugfix:", "Feature/Refactoring:"),
  40-char cap, name shown for accept/rename before use.

## Resolved decisions (2026-09-06)

1. State ladder is `Open → In Progress → Testing → Done`. `/youtrack-task testing`
   and `/youtrack-task done` are both provided; `done` moves to *Done*.
2. v1 ships the full surface: primary flow + `comment` + `log` + `testing` + `done`.
3. Emoji in write-back comments is fine (📌 pickup, 📝 plan, ⏱️ log, ✅ done).
4. After implementation: a written "how it works" walkthrough, then a joint test
   run against real YouTrack issues.
