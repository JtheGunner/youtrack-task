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
├── hooks/
│   ├── hooks.json           # PreToolUse: YouTrack `create_issue`; Bash, Edit, Write, MultiEdit from `all` subagents (timeout 10 s)
│   ├── require-assignee     # rejects a create_issue without Assignee (Claude Code only)
│   ├── guard-subagent       # confines ticket-worker / ticket-reviewer (push, merge, read-only; worker file writes only inside its worktree)
│   └── require-review       # opt-in (review_gate_hook): no push / gh pr create of an issue branch without a review stamp
├── agents/
│   ├── ticket-worker.md     # `all`: implements one issue in its worktree, headless
│   └── ticket-reviewer.md   # review gate: read-only, independent review of one branch
├── skills/
│   └── youtrack-task/
│       ├── SKILL.md         # guardrails, language, config, dispatch table and the primary flow; user-invocable as /youtrack-task. Per-command detail is loaded from reference/ on demand
│       ├── README.md        # skill-level readme: requirements, per-agent MCP setup, script ops
│       ├── examples/        # sample runs: pickup.md, new.md, pr.md, full-lifecycle.md
│       ├── scripts/
│       │   ├── read-config       # step 0 of every invocation: resolve config.toml + defaults as KEY=VALUE; `read-config <key>` prints one value (the only config parser: scripts and hooks call it)
│       │   ├── setup-workspace   # step 4: worktree-vs-in-place decision + create + bootstrap
│       │   ├── sweep-worktrees   # pr / done / prune: remove finished worktrees safely
│       │   ├── worktree-detach   # worktree take|remove: free one issue's branch
│       │   └── review-stamp      # review gate: write|check "PASS on this exact commit"
│       └── reference/
│           ├── branching.md      # branch-name + type→prefix rules
│           ├── pickup.md         # primary flow step 4: setup-workspace call, MODE handling, resume check
│           ├── new.md            # `new`: fields, confirmation, create (structure of the text: issue-template.md)
│           ├── pr.md             # `pr`: checks, review gate, push, PR, write-back
│           ├── subcommands.md    # `testing`, `done`, `log`, `comment`, `link`, `worktree`
│           ├── scripts-fallback.md # what to do when `scripts/` is not on disk
│           ├── writeback.md      # state-transition + comment rules
│           ├── issue-template.md # structure for `new` free-text generation
│           ├── projects.md       # project resolution: the procedure, the 20-item `find_projects` cap + paging loop
│           ├── superpowers.md    # routing for the superpowers plan/impl path
│           ├── review.md         # the review gate: one procedure for primary flow, `pr` and `all` (stamp contract and hook internals: this file)
│           ├── reviewer-allowlist.md # what the reviewer may run (built-in, `reviewer_commands`, `.youtrack-task/reviewer-commands` on the base branch) and the `BLOCKED` result
│           ├── batch.md          # contract for `all`: triage, workers, scheduling the review gate, PRs, merge
│           └── worktrees.md      # contract for the two scripts
├── .github/workflows/
│   ├── ci.yml               # PR / main / release: tests, shellcheck, JSON + version consistency
│   └── release-package.yml  # on a v* tag: needs ci, tag == both manifests, builds + attaches the ZIP
├── tools/
│   └── package-agensi       # builds dist/agensi/youtrack-task.zip (marketplace upload)
├── assets/
│   ├── logo.svg             # logo source: dark metallic tile, pink shapes, transparent background
│   └── logo.png             # 512 px RGBA export of logo.svg, shown in the README header
├── config.example.toml      # documents every optional override, dummy values only
├── README.md                # short entry point: what it does, quick start (2 env vars + token, then /plugin install), cheat sheet, links to docs/
├── docs/
│   ├── usage.md             # pickup steps, flags, `new`, parallel worktrees, sub-commands, lifecycle
│   ├── batch.md             # `all`: triage, workers, review loop, --auto-merge, guard hook
│   ├── configuration.md     # config keys with defaults, what lives where, MCP tools used
│   ├── other-agents.md      # Cursor / Copilot / Codex / Agensi: MCP setup, what differs
│   └── troubleshooting.md   # symptoms and fixes, grouped by topic
├── LICENSE                  # MIT
└── SPEC.md                  # this file
```

### Portability (other agents, marketplace)

`skills/youtrack-task/` is a self-contained `SKILL.md` skill and is also
distributed outside Claude Code (Agensi.io, Cursor, Copilot). Contract:

- YouTrack MCP tools are referred to by base name (`get_issue`, …); the
  `mcp__youtrack__` prefix is only the Claude Code spelling.
- The plugin's `.mcp.json` is Claude Code only; other agents configure the same
  HTTP server and `Authorization: Bearer` header in their own MCP settings.
- `scripts/` are an optimisation, not a requirement: without them on disk the
  skill degrades to plain in-place git (no worktrees, nothing forced).
- The ZIP is one top-level `youtrack-task/` folder, text files only, no symlinks,
  no OS metadata (`tools/package-agensi` enforces this).

### Language

Git artifacts — branch names, commit messages, PR titles and bodies, locally
written plan / design docs — are **always English**, whatever language the issue
is in (the skill translates the title for these). YouTrack-side text follows the
issue's language: comments mirror it, and `/youtrack-task new` writes both the
title and the description in the input's language (a given `--title` is verbatim).
The language is resolved explicitly (user instruction → input → issue text →
session language), is shown as a `Language:` line in the `new` confirmation, is
re-checked before every YouTrack write, and global "English everywhere" rules do
not apply to YouTrack text (SKILL.md "Language" is the contract).

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
| `get_current_user` | resolve "me" for the issue list; default assignee for `new` |
| `find_user` | validate `new`'s requested assignee |
| `search_issues` | list candidate issues when no ID is given |
| `get_issue` | fetch summary, description, fields, state, type |
| `get_issue_fields_schema` | learn the project's state/type field names + allowed values before writing |
| `get_issue_comments` | read existing context on the issue |
| `update_issue` | move state to *In Progress* (and later *Testing*/*Done*) |
| `add_issue_comment` | post the pickup note and the plan |
| `log_work` | `/youtrack-task log` sub-command |
| `find_projects` | resolve / list projects for `/youtrack-task new` |
| `create_issue` | `/youtrack-task new` |
| `change_issue_assignee` | `new`: fallback when `create_issue` didn't set Assignee |
| `link_issues` | future: link the GitHub PR / sub-tasks |

The skill never hardcodes custom-field names. It calls `get_issue_fields_schema`
first and matches the state field by role (the field whose allowed values include
something like *In Progress*), so it works across projects with slightly
different field setups.

## Command surface

Primary:

```
/youtrack-task [ISSUE-ID | N] [--no-move] [--no-writeback] [--base <branch>]
               [--worktree | --no-worktree] [--checkpoints] [--review | --no-review]
               [--confirm-branch | --no-confirm-branch] [--implement]
```

`--worktree` / `--no-worktree` force / skip an isolated git worktree (default
`worktree` config = `auto`). `--confirm-branch` / `--no-confirm-branch` ask /
skip the "is this branch name OK?" question (default `confirm_branch_name`
config = `true`; flag wins; the name is still printed when skipped).
`--implement` runs step 8 (implement + review) after the plan is written back;
without it the flow ends after step 7 and prints the command to continue — no
question is asked. `--checkpoints` runs an architectural plan's
execution with review stops (`superpowers:executing-plans`). `--no-review`
skips the review gate for this run (`pr` then asks before pushing); `--review`
is accepted and changes nothing.

Sub-commands (same skill, dispatched on first arg). All ship in v1.

```
/youtrack-task new "<free text>"   |   new [--project KEY] [--title …] [--description …] [--priority N] [--type N]
                                        [--assignee LOGIN|EMAIL]   # both modes
/youtrack-task comment [ISSUE-ID] <text>                # add_issue_comment; issue = leading ID token, else the current branch's
/youtrack-task log [ISSUE-ID] <duration> [description]  # log_work; issue inferred from branch if omitted
/youtrack-task pr [ISSUE-ID] [--no-move] [--base <b>] [--draft] [--no-review] [--confirm-pr | --no-confirm-pr]  # review check + push + gh PR + link on issue + → Testing
/youtrack-task link [ISSUE-ID] <pr-url>                 # attach an existing PR URL as a comment
/youtrack-task testing [ISSUE-ID]                       # move state → Testing
/youtrack-task done [ISSUE-ID]                          # move state → Done
/youtrack-task worktree list|prune|take <ID>|remove <ID>  # manage this plugin's worktrees
/youtrack-task all [ID ...] [--max N] [--no-review] [--dry-run] [--auto-merge]
                                                        # many issues in parallel + independent review
```

State ladder: `Open → In Progress → Testing → Done` (fixed; only the state names are configurable). Pickup moves `Open → In
Progress` automatically. `pr` is the only command that pushes (plus `all`, where the main session pushes reviewed branches) — it needs `gh`,
prompts before pushing (unless `confirm_pr = false` / `--no-confirm-pr`), never force-pushes/deletes, merges only under `all --auto-merge`, and moves the issue to
Testing. `pr` runs in this order: checks (repo, not the default branch, commits
ahead) → clean tree (commit / stash, asked once) → review gate or waiver →
commits + diffstat and the confirmation → push → PR → state change → comment (its
`, moved to Testing.` suffix reflects whether the state really changed) → sweep.
`confirm_pr` applies to `pr` only; `all` always asks its one batch confirmation.
`testing` / `done` are pure state transitions (no git). `done` is always
last: it means "merged and accepted". When `ISSUE-ID` is omitted for any
sub-command it is taken from the current branch name; if that fails, the skill
asks.

Lifecycle: `/youtrack-task new` (optional) → `/youtrack-task <id>` → (implement) →
`/youtrack-task pr` → *review + merge* → `/youtrack-task done`. Users who prefer
their own ship flow run that instead of `pr`, then `/youtrack-task link <url>`.

### `all` — batch with independent review

Full contract: `skills/youtrack-task/reference/batch.md`. Without IDs the candidates
come from `batch_query`, scoped to the repo's project and read page by page (20 per
page); the initial state of a project need not be `Open`. Triage (one table; one
confirmation, none when nothing is *ready*) → serial setup (worktree + pickup write-back) → parallel
`ticket-worker`s → the shared review gate per result (a fresh `ticket-reviewer`
that sees only the issue and the diff) → report with overlap warnings → PRs after one confirmation listing
them → merge **only** with `--auto-merge`.

- Only the main session writes to YouTrack and merges (subagents cannot spawn
  subagents; one writer keeps the language and assignee rules in one place).
- Workers commit locally and never push; the main session pushes a branch only
  after a `PASS` and the single PR confirmation. Reviewers are confined to a
  read-only allowlist as a best-effort measure (test runners such as Gradle check
  tasks are allowed; the code they run is outside the guard) and are instructed
  not to read commit messages or PR text — `git log` / `git show` are denied, but
  a few other allowed commands can still show them. The allowlist has three layers:
  built-in patterns (test, build and lint runners; no write or steering options such
  as `--fix`, `-o`, `-toolexec`), the exact commands of `reviewer_commands` in the
  user config, and the exact commands of `.youtrack-task/reviewer-commands` as
  committed on the base branch (read with `git show <commit>` from a base resolved by
  full ref name, so neither the branch under review nor a same-named tag can allow
  commands for its own review; lookups ignore replace refs, and the worker may not
  repoint `origin/HEAD`, move or reset a branch, fetch / pull into refs or use `git replace`).
  Like the rest of the guard this is a denylist and best effort: the list only counts once
  merged into the base branch, and branch protection stays the real boundary. A rejected command
  carries `[blocked-by-guard]`; the reviewer reports it as `BLOCKED_BY_GUARD`
  instead of a code finding and the gate returns `BLOCKED` without a fix round or a
  stamp (`reference/reviewer-allowlist.md`).
  `hooks/guard-subagent` enforces this via the hook input's `agent_type` — a
  best-effort layer; branch protection and a limited token are the real
  boundary. For the worker it also denies history rewriting (`git commit
  --amend`, `reset --hard`, `clean`, `rebase`, `update-ref`, `filter-branch`,
  `worktree remove --force`) and the `gh` verbs `repo`, `release`, `secret`,
  `pr create`. For the worker's `Edit` / `Write` / `MultiEdit` calls (matcher
  `Edit|Write|MultiEdit`) it rejects any `file_path` outside the worktree derived
  from the hook input's `cwd` and any path with a `.git` component (paths are
  collapsed and symlinks resolved first); with `cwd` in the main checkout only
  the repo's linked worktrees are writable. Known limit, documented rather than
  blocked: interpreter one-liners and package installs. All hooks need `jq`;
  without it they pass every call and warn on stderr. Every hook entry has
  `timeout: 10`.
- `--auto-merge`: PR created by this run (a reused PR is never auto-merged), head
  commit equal to the SHA the reviewer passed, at least one required check and
  all green, `CLEAN`, no file overlap with another issue of the run, plain
  `gh pr merge --merge --match-head-commit`, no admin bypass, no remote-branch
  deletion, sequential with a full re-check before each. Refused with
  `--no-review` or without subagent support.
- Subagents have no working-directory option and a `cd` does not persist between
  Bash calls, so workers prefix each command with `cd <worktree> &&`.
- Without subagent support the flow degrades to sequential work in the main
  session with a same-session (never independent) review.

### Review gate (every flow)

Procedure: `skills/youtrack-task/reference/review.md`; contract below; helper:
`<skill-dir>/scripts/review-stamp` (`<skill-dir>` = the directory of `SKILL.md`,
called by absolute path with the target repo as working directory). One procedure, three callers: the primary flow's
step 8 (`fixer = main-session`), `pr` (checks the stamp, runs the gate when it
is `STALE` / `MISSING`, stops on `FAILED`) and `all` step 4
(`fixer = ticket-worker`). A fresh `ticket-reviewer` per review gets only the
issue, its requirements, the checkout path, the base and the SHA — never the
implementer's report. `PASS` is stamped on that exact SHA in
`<git-common-dir>/youtrack-task/reviews/<ID>` (local, shared by worktrees, never
pushed). `--no-review` / `review_before_pr = never` are the only ways to push
without it; `pr` records a `SKIPPED` waiver stamp and the PR is labelled
`Review: skipped`.

#### Stamp contract (`<skill-dir>/scripts/review-stamp`)

- Stored in `$(git rev-parse --git-common-dir)/youtrack-task/reviews/<ID>`: local,
  shared by all worktrees of the repo, never pushed, never in the working tree.
- `write` refuses unless `--sha` is the HEAD of `--dir` and the tree is clean.
  It validates the ID (`^[A-Z][A-Z0-9_]*-[0-9]+$`), verdict and independence flag.
- `check` reports; it never changes anything. An unreadable stamp is `MISSING`.
  `check --sha <SHA>` asks about one exact commit (a branch tip, a pushed SHA)
  instead of HEAD and ignores the working tree; the push hook uses it.
- Verdicts: `PASS`, `FAILED`, `SKIPPED` (waiver, always `--independent no`).
- It is a workflow guard, not a security boundary: anyone with shell access can
  edit it. Branch protection on the server is the real boundary.
- Change `reference/review.md` and the script together.

#### Enforcement hook (`hooks/require-review`, optional)

Off by default; `review_gate_hook = "on"` enables it. In the main session it blocks

- `git push` of an issue branch (a refspec counts by its destination **and** by its
  source branch, so `feat/PROJ-1-x:main` is gated too),
- `git push --all` / `--branches` / `--mirror` and the matching refspec `:` (every
  local issue branch is checked); a commit pushed by raw SHA or through another
  ref name is gated when an issue branch's tip is exactly that commit (only a
  commit already reachable from a remote-tracking ref that is not itself an issue
  branch counts as published and is exempt; such refs are local data and can be
  forged, so this is a convenience, not a boundary),
- `gh pr create` for an issue branch,

unless `review-stamp check --sha <the pushed commit or the PR's branch tip>` says
`PASS` or `SKIPPED`. An issue branch is one whose name contains an issue ID. It
also covers a plain `git push` and the user's own `/ship`. Passes untouched: other
branches, deletions, pure `--tags` pushes, `review_before_pr = never`, and subagent
calls (those belong to `hooks/guard-subagent`). Like that hook it is best effort.
It fails open on environment gaps (no `jq`, a directory that is not a git repo) but
**denies** what it cannot follow: a push with a quoted, escaped, `$`- / brace- /
wildcard- / tilde-expanded remote or refspec, a refspec source that does not
resolve locally, a `--head` of an issue branch that is not a local branch, or a
quoted / expanded directory (`cd "$dir"`, `git -C "$dir"`). Residual gap: a raw
SHA that is only an *ancestor* of an issue branch (not any branch tip) is not
recognised. Quotes inside `gh pr create --title "..."` are fine. The hook only
reads the stamp and contains no review logic; a deny message names the next step
(`/youtrack-task pr`, or `pr --no-review` to waive).

### Worktrees (parallel tasks)

Contract: `reference/worktrees.md`; implementation:
`skills/youtrack-task/scripts/setup-workspace` (step 4) and `sweep-worktrees`
(`pr` step 8, `done`, `worktree prune`). The skill **runs the scripts** rather
than following prose — this is the durable fix for the model skipping the
worktree decision or a `git switch -c` sneaking in.

`setup-workspace` reads config `worktree` (`auto` default / `off` / `always`),
detects dirty (tracked changes only) / current branch / existing plugin worktree
/ existing branch for this issue, then either resumes an existing
worktree/branch, switches in place, or creates
`<repo>/<worktree_dir>/<ID>-<slug>` (dir ignored via `.git/info/exclude` — no
commit; `git worktree add` retried once on `index.lock`) and bootstraps it
(`cp -c` CoW-clone `worktree_clone` `+ storage` for Laravel, symlink
`worktree_link`, run `.claude/youtrack-worktree-setup.sh`). It prints
`MODE=inplace|worktree|existing-worktree|existing-branch` + `BRANCH` / `BASE` /
`DIR` / `NEXT_CD` / `CLONED` / `LINKED` / `NOTE`, or `ERROR=dirty-tree` (exit 2)
for the caller to resolve stash-or-carry. A new branch starts at `origin/<base>`,
else the local `<base>`, else `ERROR=cannot-resolve-base` (exit 2) — never at HEAD.

`worktree = always` (or `--worktree`) for genuinely parallel work; under `auto`
the first pickup in a clean, on-default repo stays in place. `comment` / `log` /
`pr` / `testing` / `done` work unchanged from inside a worktree (issue ID from
the branch name).

`sweep-worktrees [--exclude <branch>]` removes every `<worktree_dir>` worktree
that is **clean** and whose PR (`gh pr view`) is MERGED or CLOSED — `git worktree
remove` then `git branch -d` then `git worktree prune`. Dirty ones and open PRs
are listed, not touched. `pr` runs it excluding the just-opened branch; `done`
and `worktree prune` run it plain. Never `--force`, never `git branch -D`.

`worktree-detach --id <ID> [--switch]` (behind `worktree take` / `worktree
remove`) removes the single worktree holding that issue's branch so the branch is
checkout-able elsewhere — **branch kept**, refuses a dirty worktree, `--switch`
also `git switch`es to it in the current checkout (skipped if that checkout has
tracked changes).

### `new` — create an issue

Required: `project`, `title`, `description`. Two input modes:

- **Free-text**: `/youtrack-task new "<blob>"` (or `--from-text`). The skill
  generates `title` + a structured `description` per `reference/issue-template.md`
  — fixed sections Summary / Context / Goal / Acceptance criteria / Scope /
  Technical notes? / Open questions?, title and description in the input's
  language, no invented facts
  (gaps → Open questions). This is the same structure `/youtrack-task <id>` reads
  back when planning, so capture → work loses nothing.
- **Field**: `--title` / `--description` etc.; missing required fields prompted
  one at a time. Bare `new` asks free-text-or-fields first.

Field resolution:
- **project**: `--project` → repo-derived default (see *Project resolution*) →
  full paginated `find_projects` list. Validated with `get_project`.
- **type**: `--type` (validated against the project schema) → else inferred from
  the (generated or given) title + description and shown for confirmation; never
  created unconfirmed. `default_new_type` (config) is the fallback when unsure.
- **priority**: `--priority` (validated) → else unset (project default). Not
  inferred, except: free text that explicitly signals urgency → propose + ask.
- **assignee**: always set. `--assignee` / an explicit "assign to …" in the free
  text → `find_user`; found → that login, not found → the API-key owner
  (`get_current_user`) with a ⚠ note at the confirm step. Nothing requested →
  the API-key owner. No `Assignee` field in the project schema → unassigned,
  reported. No config key.

  **Direct creation (no `new`).** The same default holds for any `create_issue`
  call made in conversation without the skill — that is how issues ended up
  unassigned (and in the wrong language). A plugin `PreToolUse` hook
  (`hooks/require-assignee`, matcher `mcp__.*youtrack.*__create_issue`) rejects a
  call whose `customFields` has no `Assignee` (exit 2 + reason on stderr); the
  model retries with `get_current_user`'s login, or `Unassigned` when the user
  asked for that. It fails open without `jq` (with a stderr warning). The skill description is a list of
  triggers only (a pasted issue URL or ID, create / file, book time, status, attach a
  PR, batch — incl. German) so the skill loads for such requests and for nothing else;
  it carries no summary of the workflow, which models would read instead of the body.

Flow: resolve/generate fields → `get_issue_fields_schema` for exact spellings →
show the assembled issue, editable, one confirmation → `create_issue` (Type /
Priority / Assignee as custom fields; `change_issue_assignee` / `update_issue`
fallback) → report ID + URL + assignee → offer
pickup (`/youtrack-task <new-ID>`), no auto-chain.

## Project resolution

Used wherever the repo's YouTrack project is needed (bare issue number, repo
sanity check, `new`). `find_projects` returns at most 20 projects per page, so a
single unpaged call can miss an existing project; names also differ from keys
(repo `intelli-key-port` ↔ key `IKP`), so matching is by **name**.

1. Candidates: repo name from the `origin` remote (no `.git`, no owner) and the
   cwd basename, each also with `-` / `_` removed.
2. Targeted `find_projects(query=<candidate>)`; exact case-insensitive name match
   wins, a single substring match is confirmed, several → ask.
3. Only if nothing matched: page through `find_projects(query="")` with
   `offset += 20` until a page has fewer than 20 items; match against all names.
4. Verify with `get_project`.
5. "No project named …" is allowed only after steps 2 and 3; a partial list is
   never presented as complete. `--project KEY` skips 1–3; an issue ID's prefix is
   authoritative for that issue.

## Primary flow

### 1. Resolve the issue ID

- `ISSUE_ID_RE` is `[A-Z][A-Z0-9_]*-[0-9]+`, the one form in the skill, scripts
  and hooks (`tests/skill-text.sh` keeps them identical). A leading token that
  matches `^ISSUE_ID_RE$` is an ID; otherwise the ID is the first match in the
  branch name (`fix/P2X-5-foo` → `P2X-5`).
- Arg is a full ID (`^ISSUE_ID_RE$`) → use it.
- Arg is a bare number `N` → qualify with the current repo's project key
  (*Project resolution* only, no other heuristic) → `<PROJECT>-N`, read it with
  `get_issue`, echo it with its title, proceed on yes.
- No arg → `git branch --show-current`; an `ISSUE_ID_RE` match in it → extract, confirm.
- Still nothing → `search_issues` with `list_query` (config-overridable), list
  candidates as `<ID> — <summary> — <state>` (no row numbers). Reply is an issue
  ID; a bare number there is `<PROJECT>-N`, never a list position.
- Nothing found / ambiguous → stop and ask.
- A full ID or `<PROJECT>-N` that `get_issue` does not find → stop: print the ID and,
  if it exists, the repo project's `<PROJECT>-<number>` as the likely intended one.
  No pickup, no go-ahead question, no automatic substitution.

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

### 4. Set up the workspace

Compute `<prefix>` / `<slug>` per `reference/branching.md` (English, type word
stripped, 40-char cap), print `→ Branch: <name>` and, with `CONFIRM_BRANCH_NAME=true`, ask accept/rename (no question when
`CONFIRM_BRANCH_NAME=false` from `<skill-dir>/scripts/read-config`, or `--no-confirm-branch`; no other go-ahead gate
is added, the invocation authorizes the pickup), then **run
`<skill-dir>/scripts/setup-workspace --id <ID> --slug <slug> --prefix <prefix> [--base …]
[--mode worktree|inplace]`** and act on its `KEY=VALUE` output (see the Worktrees
section and `reference/worktrees.md`):

| `MODE=` | caller action |
| --- | --- |
| `inplace` | on `BRANCH` in the repo root; report `BRANCH` / `BASE` |
| `worktree` | enter `NEXT_CD` (`EnterWorktree`, else per-call working directory — a `cd` does not persist); report `BRANCH` `BASE` `DIR` `CLONED` `LINKED` `NOTE`; steps 5–8 run there |
| `existing-worktree` | resume: enter `NEXT_CD`, then the resume check below |
| `existing-branch` | branch exists but isn't checked out → ask the user `git switch` vs `git worktree add`; then the resume check below |

Resume check: the comments read in step 2 are searched for the pickup heading
(`📌 Picked up in Claude Code`) and the plan heading (`## 📝 Implementation plan`).
Pickup found → skip step 5, else run it. Plan found → reuse it in step 6 and skip
step 7, else run both.

`ERROR=dirty-tree` (exit 2) → resolve stash-or-carry per `reference/branching.md`,
re-run. Never commit on the base branch. The script owns base resolution,
`git fetch`, the ignore guard, `index.lock` retry, and bootstrap.

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
  Markdown, prefixed `## Implementation plan (Claude Code)` and dated, in the
  issue's language.
- If — and only if — the repo already contains a `docs/` directory, also write
  `docs/plans/<ID>.md` with the same content. No `docs/` → no local file, no
  directory creation. Controlled by config `local_plan_copy` (`auto` default /
  `always` / `never`). The local copy is a git artifact: always English.
  superpowers architectural plans prefer an existing
  `docs/superpowers/specs/` convention when the repo has one.

### 8. Implement (`--implement`)

Without `--implement` the flow ends after step 7 with one line naming the command
to continue (`/youtrack-task <ID> --implement`); no question. With it, no
go-ahead question either. Bound by the Guardrails. superpowers path (`reference/superpowers.md`):
bounded → `test-driven-development` directly; architectural → execute the plan
with `subagent-driven-development` (or `executing-plans` under `--checkpoints`),
TDD per task. Both paths → `verification-before-completion` on the acceptance
criteria, then the **review gate** (`reference/review.md`): a fresh
`ticket-reviewer` subagent with a minimal briefing, result stamped on the exact
commit by `<skill-dir>/scripts/review-stamp` (`--no-review` / `review_before_pr = never`
skip it), then the completion comment. No superpowers → the normal dev workflow
+ a manual verification pass. Never pushes / PRs / moves state — that's `pr` /
the user.

## Configuration file

`~/.config/youtrack-task/config.toml`, all keys optional:

```toml
# use_superpowers   = "auto"          # auto | always | never
# review_before_pr  = "always"        # always ("auto" is a synonym) | never
# review_rounds     = 2               # fix + re-review rounds per issue (review gate and `all`)
# review_gate_hook  = "off"           # on: hooks/require-review blocks unreviewed pushes / PRs
# reviewer_commands = ["ddev exec vendor/bin/pest"]  # extra whole commands the read-only reviewer may run (default: none)
# confirm_branch_name = true          # false: accept the computed branch name without asking
# confirm_pr        = true            # false: `pr` pushes + opens the PR without the confirmation question
# worktree          = "auto"          # auto (checkout busy) | off | always
# worktree_dir      = ".worktrees"    # gitignored dir under the repo root
# worktree_clone    = ["node_modules", "vendor"]   # CoW-copied (isolated)
# worktree_link     = [".env"]        # symlinked from the main checkout (shared)
# default_new_type  = "Task"          # fallback Type for `new` when inference is unsure
# list_query        = "for: me #Unresolved State: {In Progress}, {Open} sort by: updated desc"
# in_progress_state = "In Progress"   # state name used on pickup
# testing_state     = "Testing"       # target of `/youtrack-task testing`
# done_state        = "Done"          # target of `/youtrack-task done`
# local_plan_copy   = "auto"          # auto | always | never
# batch_query         = "for: me #Unresolved sort by: updated desc"  # `all` candidates; `project: {KEY}` of the repo is added unless the query has a `project:` clause
# batch_max_parallel  = 3             # parallel workers in `all`
# batch_skip_tags     = ["manual"]    # `all` never runs issues with these tags
# batch_review_rounds = 2             # deprecated alias of review_rounds
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
- No unlisted confirmation questions: only the questions the spec lists are asked; a
  wrong input stops with an explanation, never a "Shall I continue?" gate.
- No push or PR without a stamped review `PASS` on the exact HEAD (only the labelled
  `--no-review` / `review_before_pr = never` paths bypass it).
- Push + PR only in the explicit `pr` sub-command (or the user's own ship flow),
  after a confirmation prompt (skippable via `confirm_pr = false` / `--no-confirm-pr` — a standing authorization; review gate unaffected). Never as part of the primary flow or `done`. Never
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
