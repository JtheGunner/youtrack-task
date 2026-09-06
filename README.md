# youtrack-task

A Claude Code plugin for working [JetBrains YouTrack](https://www.jetbrains.com/youtrack/)
issues from inside any project repo:

- **`/youtrack-task new "<free text>"`** — capture an issue; Claude turns your
  text into a titled, structured issue.
- **`/youtrack-task <ID>`** — pick one up: fetch it, branch, move it to
  **In Progress**, plan the work (through the [`superpowers`](https://github.com/obra/superpowers)
  plugin when present), write the plan back as a comment, and optionally implement it.
- **`/youtrack-task pr` / `testing` / `done`** — open the PR (and link it on the
  issue), then walk the state ladder as the work lands.

No PhpStorm YouTrack plugin required — it talks to YouTrack's own remote MCP
server.

---

## Requirements

- Claude Code with plugin support.
- YouTrack **2025.3 or newer** (Cloud or Server) with the remote MCP server
  reachable at `https://<your-host>/mcp`. If YouTrack sits behind a reverse proxy
  / SSO (Authelia, Authentik, oauth2-proxy…), allow the `/mcp` path through with
  bearer-token auth.
- `git` on your `PATH`.
- The [`gh` CLI](https://cli.github.com/) on your `PATH` if you want to use
  `/youtrack-task pr`. Not needed for anything else.
- *(optional)* the [`superpowers`](https://github.com/obra/superpowers) plugin —
  when present, planning and implementation run through its skills. Everything
  works without it.

## Setup (one time)

### 1. Create a YouTrack API token

YouTrack → your avatar → **Profile** → **Account Security** → **New token**.
Scope: **YouTrack**. Copy the `perm:...` value.

### 2. Export two environment variables

Put these in your shell startup (`~/.zshrc`, omnishell module, etc.):

```sh
export YOUTRACK_MCP_URL="https://youtrack.example.com/mcp"
export YOUTRACK_TOKEN="perm:xxxxxxxxxxxxxxxxxxxx"
```

Open a new shell so they're loaded, then start Claude Code from there.

> The plugin's bundled MCP definition (`.mcp.json`) references these two
> variables — `${YOUTRACK_MCP_URL}` and `${YOUTRACK_TOKEN}`. Nothing
> instance-specific is stored in this repo.

### 3. Install the plugin

```
/plugin marketplace add JtheGunner/youtrack-task
/plugin install youtrack-task@youtrack-task
```

Restart Claude Code. Verify the MCP server connected: you should see `youtrack`
tools available (`/mcp` lists them).

### 4. (Optional) Config overrides

Only if your workflow differs from the defaults. Copy
[`config.example.toml`](./config.example.toml) to
`~/.config/youtrack-task/config.toml` and uncomment what you need — custom state
names, a different issue-list query, branch-prefix mapping, where the plan copy
goes, or the `use_superpowers` / `review_before_pr` toggles.

---

## Usage

### Pick up an issue

```
/youtrack-task                 # lists your Open / In Progress issues, you pick one
/youtrack-task INFRA-42        # go straight to that issue
```

What happens:

1. **Fetch** — Claude pulls the issue (summary, description, type, priority,
   state, subsystem) and its comments, and shows you a short brief.
2. **Sanity check** — verifies you're in a git repo and that the repo roughly
   matches the issue's YouTrack project (warns, never blocks).
3. **Branch** — creates `‹prefix›/‹ID›-‹slug›` from the current tip of your
   default branch. Prefix comes from the issue Type: `Bug→fix`, `Feature→feat`,
   `Task→chore`, `Epic→feat`, `Cosmetics→style`, else `chore`.
   Example: `chore/INFRA-42-rotate-vault-unseal-keys`.
   Refuses on a dirty tree (offers to stash); switches to the branch if it
   already exists. The slug is always English even when the issue isn't.
4. **In Progress** — moves the issue to *In Progress* (unless it's already there
   or further) and adds a comment: *📌 Picked up in Claude Code — branch `…`*.
5. **Plan** — Claude explores the repo and drafts an implementation plan. If the
   [`superpowers`](https://github.com/obra/superpowers) plugin is installed,
   planning runs through it (`brainstorming`, or `systematic-debugging` for bugs,
   then `writing-plans` for larger work); otherwise a plain plan-mode pass. You
   review and iterate until it's right.
6. **Write back the plan** — once you approve, the plan is posted to the issue as
   a Markdown comment (*📝 Implementation plan (Claude Code)*). If the repo has a
   `docs/` directory, a copy is also saved to `docs/plans/‹ID›.md`.
7. **Implement** *(optional, if you say go)* — with `superpowers` present:
   `test-driven-development` throughout, `subagent-driven-development` (or
   `executing-plans` with `--checkpoints`) for a written plan, an automatic
   `requesting-code-review` on larger work, and `verification-before-completion`
   against the issue's acceptance criteria before the completion comment. Without
   it: the normal dev workflow. Either way it stops before push — `/youtrack-task
   pr` is next.

Flags:

| Flag | Effect |
| --- | --- |
| `--no-move` | don't change the issue state; still add the pickup comment |
| `--no-writeback` | don't change state and don't add the pickup comment |
| `--base ‹branch›` | branch from `‹branch›` instead of the detected default |
| `--worktree` / `--no-worktree` | force / skip an isolated git worktree for this pickup (default: `worktree` config, itself `auto`) |
| `--checkpoints` | execute an architectural plan with review stops after each phase (`superpowers:executing-plans`) instead of one continuous run |
| `--review` / `--no-review` | force / skip the automatic code review in the implement step (default: review only when a written plan was executed) |

### Create an issue

```
/youtrack-task new "hover on tinted rows loses the colour, needs a same-hue hover instead"
/youtrack-task new                     # interactive: free text, or field by field
/youtrack-task new --project ADMIN --title "..." --description "..." --priority Major --type Bug
```

**Free-text mode** (first form): give one blob of text and Claude generates the
title and a **structured description** — Summary / Context / Goal / Acceptance
criteria / Scope / Technical notes / Open questions. That structure is the same
one a later `/youtrack-task <id>` reads back to build its plan, so nothing is
lost between capturing the task and working it. You review and edit the
generated issue before it's created.

Required either way: project, title, description. `--project` defaults to the
YouTrack project matching the current repo. `--priority` is optional (project
default otherwise; only proposed automatically if the text says "blocker" /
"asap" / etc.). `--type` is inferred from the content and shown for confirmation
when you don't pass it. After creating, Claude offers to pick the issue up.

### Working several tasks in parallel

By default (`worktree = auto`) a pickup drops into an **isolated git worktree**
when your current checkout is busy — dirty, or already on another task's branch.
So you can:

```
# terminal 1
cd ~/projects/admin-dashboard-vue && claude
> /youtrack-task ADMIN-1        # → .worktrees/ADMIN-1-…  on feat/ADMIN-1-…

# terminal 2, at the same time
cd ~/projects/admin-dashboard-vue && claude
> /youtrack-task ADMIN-6        # → .worktrees/ADMIN-6-…  on fix/ADMIN-6-…
```

Each worktree gets its own `node_modules` / `vendor` (copy-on-write clone on
APFS — instant, no extra disk until changed) and a symlinked `.env`. Drop a
`.claude/youtrack-worktree-setup.sh` in the repo for anything project-specific
(per-worktree DB, asset build). `/youtrack-task done` offers to remove a
worktree once its PR is merged; `/youtrack-task worktree list|prune` manages them.

Force it per run with `--worktree` / `--no-worktree`; set `worktree = off`
(pre-0.6 behaviour: switch the current checkout) or `always` in the config.

### During and after the work

```
/youtrack-task comment <text>          # add a comment to the current branch's issue
/youtrack-task log 1h30m <what>         # log time on the current branch's issue
/youtrack-task log INFRA-42 45m <what>  # ...or on a specific issue
/youtrack-task pr                       # push branch + open PR + link it + move to Testing
/youtrack-task link <pr-url>            # attach an already-open PR to the issue
/youtrack-task testing                  # move the issue to Testing
/youtrack-task done                     # move the issue to Done
/youtrack-task worktree list|prune      # manage the plugin's worktrees
```

`comment` / `log` / `pr` / `link` / `testing` / `done` figure out the issue ID
from your current branch name; pass an explicit `ID` as the first argument to
override. State moves are forward-only along `Open → In Progress → Testing → Done`
— asking to move an issue to a state it's already at or past does nothing.

### The full lifecycle

```
/youtrack-task new …     →  (optional) create the issue first
/youtrack-task ADMIN-6   →  branch, In Progress, plan, (optional) implement
/youtrack-task pr        →  push + GitHub PR + PR link on the issue + → Testing
      … PR review + merge …
/youtrack-task done      →  → Done
```

`pr` is the only command that pushes, and it asks first (shows the commits and
diffstat). It needs the [`gh` CLI](https://cli.github.com/). It never
force-pushes, merges, or deletes anything. Branch names, commit messages and the
PR title/body are always English — even for a German (or other non-English)
issue; only the YouTrack comments follow the issue's language. If you'd rather run your own richer
ship flow (tests, version bump, changelog), do that instead and then
`/youtrack-task link <pr-url>` to record the PR on the issue. `done` is always
last — it means "merged and accepted", so run it after the PR lands, not before.

---

## What lives where

| Thing | Location | In this public repo? |
| --- | --- | --- |
| YouTrack URL | `YOUTRACK_MCP_URL` env var | no |
| API token | `YOUTRACK_TOKEN` env var | no |
| Which project an issue is in | encoded in the issue ID (`INFRA-42`) | no |
| State names, list query, prefix map, superpowers / review toggles | defaults in the skill; overrides in `~/.config/youtrack-task/config.toml` | defaults only |
| The skill logic | `skills/youtrack-task/` | yes |

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "YouTrack MCP server isn't connected" | `YOUTRACK_MCP_URL` / `YOUTRACK_TOKEN` not set in the shell that launched Claude Code, or `/mcp` blocked by your proxy. Check `curl -H "Authorization: Bearer $YOUTRACK_TOKEN" "$YOUTRACK_MCP_URL"`. |
| MCP connects but writes fail with 403 | The token's user lacks permission on that project, or the token scope is wrong. |
| State change skipped with a warning | The skill couldn't identify the state field from the project schema. Set `in_progress_state` / `testing_state` / `done_state` in the config to match your project's field values. |
| Branch name too long | Slugs are capped; if it's still awkward, rename with `git branch -m`. |

## MCP tools used

`get_current_user`, `find_projects`, `get_project`, `search_issues`, `get_issue`,
`get_issue_fields_schema`, `get_issue_comments`, `create_issue`, `update_issue`,
`add_issue_comment`, `log_work` — all from YouTrack's predefined MCP tool set.

## Changelog

See [CHANGELOG.md](./CHANGELOG.md). Versioning follows [SemVer](https://semver.org/);
each release is also a git tag (`vMAJOR.MINOR.PATCH`).

## License

MIT — see [LICENSE](./LICENSE).
