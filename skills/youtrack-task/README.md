# youtrack-task (skill)

Pick up a JetBrains YouTrack issue from any git repository: create a branch (or an
isolated worktree), move the issue to *In Progress*, plan the work, and write the
plan, the PR and the state changes back to the issue.

This folder is the complete skill. It works in Claude Code and in any agent that
supports the `SKILL.md` format and can talk to a YouTrack MCP server.

## Requirements

| Need | Why |
| --- | --- |
| A YouTrack instance with the MCP server enabled | All issue reads and writes go through MCP tools (`get_issue`, `update_issue`, `add_issue_comment`, …). No REST calls, no `curl`. |
| The YouTrack MCP server added to your agent | HTTP server at `https://<your-youtrack-host>/mcp`, header `Authorization: Bearer <permanent token>`. |
| A git repository | The skill creates branches and, optionally, worktrees. |
| `gh` CLI *(optional)* | Only for `pr` and for sweeping merged worktrees. |

Create the token in YouTrack under *Profile → Account Security*. Never commit it;
put it in your agent's MCP configuration or an environment variable.

## Connecting the YouTrack MCP server

| Agent | Where |
| --- | --- |
| Claude Code (plugin) | `export YOUTRACK_MCP_URL=…` and `export YOUTRACK_TOKEN=…`, then enable the plugin. The bundled `.mcp.json` does the rest. |
| Claude Code (standalone skill) | `claude mcp add --transport http youtrack <URL> --header "Authorization: Bearer <token>"` |
| Cursor | `.cursor/mcp.json` → an HTTP server named `youtrack` with `url` and `headers.Authorization`. |
| GitHub Copilot / VS Code | `.vscode/mcp.json` → an HTTP server named `youtrack` with the same URL and header. |

Tool names differ per agent (`mcp__youtrack__get_issue` in Claude Code); the skill
matches on the base name (`get_issue`).

## Usage

```text
/youtrack-task PROJ-123            # pick up an issue: branch, In Progress, plan
/youtrack-task new "free text"     # create an issue from a description
/youtrack-task pr                  # push, open a PR, link it, move to Testing
/youtrack-task done                # move to Done, clean up finished worktrees
```

More sub-commands: `comment`, `log`, `link`, `testing`, `worktree`. See `SKILL.md`
for the full reference and `examples/` for sample runs.

## What the bundled scripts do

Every script is plain `bash`, readable, and operates on the current git repository.
None of them install packages or use `sudo`. The only network access is the
`gh pr view` call in `sweep-worktrees`.

| Script | Does | Touches |
| --- | --- | --- |
| `scripts/setup-workspace` | Decides worktree vs. in-place, creates the branch or worktree, bootstraps a new worktree. | `git switch -c` / `git worktree add` in the repo; adds the worktree dir to `.git/info/exclude` (no commit); under `<repo>/.worktrees/` it copies the dirs listed in `worktree_clone` (default `node_modules`, `vendor`) with `cp -c -R`, symlinks the paths in `worktree_link` (default `.env`) from the main checkout, and runs `.claude/youtrack-worktree-setup.sh` if the repo ships one. |
| `scripts/sweep-worktrees` | Removes this skill's worktrees whose PR is merged or closed and whose tree is clean. | `gh pr view` (reads PR state from GitHub), `git worktree remove` (never `--force`), `git branch -d` (never `-D`). |
| `scripts/worktree-detach` | Frees one issue's branch from a worktree (`worktree take` / `remove`). | `git worktree remove` of that single clean worktree, optional `git switch`. |

Config is read from `~/.config/youtrack-task/config.toml` (override the path with
`YOUTRACK_TASK_CONFIG`). Every key is optional; see the table in `SKILL.md`.

If the agent loads the skill without writing `scripts/` to disk, the skill falls
back to plain in-place git (no worktrees). Nothing else changes.

## Safety

The skill never commits to the default branch, never force-pushes, never merges,
never deletes a branch with `-D`, never uses `--no-verify`, and pushes only in the
explicit `pr` sub-command after a confirmation. The full list is in the
*Guardrails* section of `SKILL.md`.

## License

MIT. Source and changelog: <https://github.com/JtheGunner/youtrack-task>.
