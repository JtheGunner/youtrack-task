# youtrack-task

A Claude Code plugin. From inside any project repo, run one command to pick up a
[JetBrains YouTrack](https://www.jetbrains.com/youtrack/) issue: Claude fetches
it, creates a correctly named git branch, moves the issue to **In Progress**,
plans the work with you, and writes the plan back to the issue as a comment.

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
/plugin install youtrack-task
```

Restart Claude Code. Verify the MCP server connected: you should see `youtrack`
tools available (`/mcp` lists them).

### 4. (Optional) Config overrides

Only if your workflow differs from the defaults. Copy
[`config.example.toml`](./config.example.toml) to
`~/.config/youtrack-task/config.toml` and uncomment what you need — custom state
names, a different issue-list query, branch-prefix mapping, or where the plan
copy goes.

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
   already exists.
4. **In Progress** — moves the issue to *In Progress* (unless it's already there
   or further) and adds a comment: *📌 Picked up in Claude Code — branch `…`*.
5. **Plan** — Claude explores the repo and drafts an implementation plan. You
   review and iterate until it's right.
6. **Write back the plan** — once you approve, the plan is posted to the issue as
   a Markdown comment (*📝 Implementation plan (Claude Code)*). If the repo has a
   `docs/` directory, a copy is also saved to `docs/plans/‹ID›.md`.

Flags:

| Flag | Effect |
| --- | --- |
| `--no-move` | don't change the issue state; still add the pickup comment |
| `--no-writeback` | don't change state and don't add the pickup comment |
| `--base ‹branch›` | branch from `‹branch›` instead of the detected default |

### During and after the work

```
/youtrack-task comment <text>          # add a comment to the current branch's issue
/youtrack-task log 1h30m <what>         # log time on the current branch's issue
/youtrack-task log INFRA-42 45m <what>  # ...or on a specific issue
/youtrack-task pr                       # push branch + open PR + link it + move to Testing
/youtrack-task link <pr-url>            # attach an already-open PR to the issue
/youtrack-task testing                  # move the issue to Testing
/youtrack-task done                     # move the issue to Done
```

`comment` / `log` / `pr` / `link` / `testing` / `done` figure out the issue ID
from your current branch name; pass an explicit `ID` as the first argument to
override. State moves are forward-only along `Open → In Progress → Testing → Done`
— asking to move an issue to a state it's already at or past does nothing.

### The full lifecycle

```
/youtrack-task ADMIN-6   →  branch, In Progress, plan, (optional) implement
/youtrack-task pr        →  push + GitHub PR + PR link on the issue + → Testing
      … PR review + merge …
/youtrack-task done      →  → Done
```

`pr` is the only command that pushes, and it asks first (shows the commits and
diffstat). It needs the [`gh` CLI](https://cli.github.com/). It never
force-pushes, merges, or deletes anything. If you'd rather run your own richer
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
| State names, list query, prefix map | defaults in the skill; overrides in `~/.config/youtrack-task/config.toml` | defaults only |
| The skill logic | `skills/youtrack-task/` | yes |

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "YouTrack MCP server isn't connected" | `YOUTRACK_MCP_URL` / `YOUTRACK_TOKEN` not set in the shell that launched Claude Code, or `/mcp` blocked by your proxy. Check `curl -H "Authorization: Bearer $YOUTRACK_TOKEN" "$YOUTRACK_MCP_URL"`. |
| MCP connects but writes fail with 403 | The token's user lacks permission on that project, or the token scope is wrong. |
| State change skipped with a warning | The skill couldn't identify the state field from the project schema. Set `in_progress_state` / `testing_state` / `done_state` in the config to match your project's field values. |
| Branch name too long | Slugs are capped; if it's still awkward, rename with `git branch -m`. |

## MCP tools used

`get_current_user`, `search_issues`, `get_issue`, `get_issue_fields_schema`,
`get_issue_comments`, `get_project`, `update_issue`, `add_issue_comment`,
`log_work` — all from YouTrack's predefined MCP tool set.

## License

MIT — see [LICENSE](./LICENSE).
