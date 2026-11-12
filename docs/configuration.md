# ⚙️ Configuration

Back to the [README](../README.md).

## Environment variables

| Variable | Value |
|----------|-------|
| `YOUTRACK_MCP_URL` | `https://<your-host>/mcp` |
| `YOUTRACK_TOKEN` | Permanent API token (`perm:…`) with scope **YouTrack** |

The plugin's bundled MCP definition (`.mcp.json`) references `${YOUTRACK_MCP_URL}`
and `${YOUTRACK_TOKEN}`. Nothing instance-specific is stored in this repo.

## Config overrides

Optional and only needed if your workflow differs from the defaults. Copy
[`config.example.toml`](../config.example.toml) to
`~/.config/youtrack-task/config.toml` and uncomment what you need.

> [!NOTE]
> Arrays such as `worktree_clone` must be written on a **single line**. A multi-line
> array is ignored and the default applies. Keys under a `[table]` (such as
> `[type_prefix]`) are read only for the branch-prefix mapping.

### States and queries

| Key | Default | Purpose |
|-----|---------|---------|
| `in_progress_state` | `In Progress` | State set on pickup. |
| `testing_state` | `Testing` | State set by `pr` / `testing`. |
| `done_state` | `Done` | State set by `done`. |
| `list_query` | `for: me #Unresolved State: {In Progress}, {Open} sort by: updated desc` | Issue list shown when you run the command without an ID. |
| `default_new_type` | *(unset)* | Fallback Type for `new` when it can't infer one. |

The ladder order `Open → In Progress → Testing → Done` is fixed. Only the state
names are configurable.

### Planning, review and confirmations

| Key | Default | Purpose |
|-----|---------|---------|
| `use_superpowers` | `auto` | `auto` \| `always` \| `never`: run planning and implementation through the `superpowers` plugin. |
| `local_plan_copy` | `auto` | Where the plan copy goes (`docs/plans/‹ID›.md`): `auto` \| `always` \| `never`. |
| `review_before_pr` | `always` | `always`: every task with commits is reviewed before push/PR. `never`: skip. |
| `review_gate_hook` | `off` | `on` makes the `require-review` hook block pushes and `gh pr create` without a review stamp. |
| `review_rounds` | `2` | Max fix / re-review rounds per issue. `batch_review_rounds` still works as an alias. |
| `reviewer_commands` | *(none)* | Extra commands the read-only reviewer may run, e.g. `["ddev exec vendor/bin/pest", "npm run build"]`. Each entry is a whole command, matched exactly. See [Letting the reviewer run more](#letting-the-reviewer-run-more). |
| `confirm_branch_name` | `true` | `false` accepts the computed branch name without asking (it is still shown). |
| `confirm_pr` | `true` | `false` makes `pr` push and open the PR without the question. Applies to `pr` only. |
| `[type_prefix]` table | see `reference/branching.md` | Per-Type branch prefix mapping. |

### Worktrees

| Key | Default | Purpose |
|-----|---------|---------|
| `worktree` | `auto` | `auto` \| `always` \| `off` (see [Usage](./usage.md#-work-several-tasks-in-parallel)). |
| `worktree_dir` | `.worktrees` | Directory under the repo root that holds worktrees. |
| `worktree_clone` | `["node_modules", "vendor"]` | Directories copied (copy-on-write) into a new worktree. Add `"storage"` for Laravel repos. |
| `worktree_link` | `[".env"]` | Paths symlinked from the main checkout into a new worktree. |

### Batch (`all`)

| Key | Default | Purpose |
|-----|---------|---------|
| `batch_query` | `for: me #Unresolved sort by: updated desc` | Candidates when no IDs are given. The repo's `project:` clause is added unless the query has its own. |
| `batch_max_parallel` | `3` | Parallel workers. |
| `batch_skip_tags` | `["manual"]` | Issues with one of these tags are never worked on by `all`. |

Flags override config for one run. See [Usage](./usage.md#flags) for the flag list.

### Letting the reviewer run more

The reviewer is read-only and runs only an allowlist: common test, build and lint
runners (`npm test`, `pytest`, `go test`, `go build ./...`, `swift test`,
`golangci-lint run`, `scripts/*test*`, …). Anything else is rejected by the hook and
reported as *blocked by the guard*, not as a code problem. Two places add commands:

| Where | Use it for |
|-------|-----------|
| `reviewer_commands` in `~/.config/youtrack-task/config.toml` | Commands only your machine needs |
| `.youtrack-task/reviewer-commands` in the repository | Commands the whole team's reviews need, one per line, `#` starts a comment line |

Both match **exactly**: the whole command, word for word. `make verify` does not allow
`make verify-all`, and redirections, heredocs, `;`, `&&` and `|` stay rejected.
The repository file is read from the **base branch** (`git show`), never from the
branch under review: a branch cannot allow commands for its own review, and a change
to the file takes effect once it is merged.

```text
# .youtrack-task/reviewer-commands
ddev exec vendor/bin/pest
make verify
```

## How config is resolved

`scripts/read-config` is step 0 of every invocation. It reads your `config.toml`,
applies all defaults and prints `KEY=VALUE` lines. Claude, the other scripts and the
review-gate hook all read their settings through it, so a setting such as
`confirm_branch_name = false` applies every time, not only when Claude happens to
read the file.

---

## 🗂️ What lives where

| | Thing | Location | In this public repo? |
|:-:|-------|----------|:--------------------:|
| 🔐 | YouTrack URL | `YOUTRACK_MCP_URL` env var | 🚫 |
| 🔐 | API token | `YOUTRACK_TOKEN` env var | 🚫 |
| 🔐 | Which project an issue is in | Encoded in the issue ID (`INFRA-42`) | 🚫 |
| ⚙️ | State names, list query, prefix map, branch-name and PR confirmation, superpowers / review / worktree settings | Defaults in the skill; overrides in `~/.config/youtrack-task/config.toml` | ✅ defaults only |
| ⚙️ | Extra reviewer commands (`reviewer_commands`; per project: `.youtrack-task/reviewer-commands`, read from the base branch) | `~/.config/youtrack-task/config.toml`; the project file in the repository | ✅ defaults only |
| ⚙️ | `all` settings (`batch_query`, `batch_max_parallel`, `batch_skip_tags`; review rounds via `review_rounds`) | Defaults in the skill; overrides in `~/.config/youtrack-task/config.toml` | ✅ defaults only |
| 🧩 | The skill and its bundled `scripts/` (workspace setup, worktree sweep/detach, review stamp). `SKILL.md` holds the guardrails and the primary flow; each sub-command's detail sits in `reference/` and is read only when that command runs | `skills/youtrack-task/` | ✅ |
| 🤖 | Review agent (`ticket-reviewer`, used by every flow), `all` worker (`ticket-worker`) and the guard hook | `agents/`, `hooks/guard-subagent` (plugin install only) | ✅ |
| 🎨 | Logo (`logo.svg` source, transparent `logo.png` export used in the header) | `assets/` | ✅ |
| 📦 | Marketplace upload ZIP (built, not committed) | `dist/agensi/youtrack-task.zip` via `tools/package-agensi` | 🚫 |

---

## 🔌 MCP tools used

`get_current_user`, `find_user`, `find_projects`, `get_project`, `search_issues`,
`get_issue`, `get_issue_fields_schema`, `get_issue_comments`, `create_issue`,
`update_issue`, `change_issue_assignee`, `add_issue_comment`, `log_work`.

All of them come from YouTrack's predefined MCP tool set.
