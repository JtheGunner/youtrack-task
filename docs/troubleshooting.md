# 🩺 Troubleshooting

Find your symptom, apply the fix. Back to the [README](../README.md).

**Jump to:** [Setup and connection](#-setup-and-connection) ·
[Pickup](#-pickup) · [Issues and comments](#-issues-and-comments) ·
[Pull requests and review](#-pull-requests-and-review) ·
[Worktrees](#-worktrees) · [Batch (`all`)](#-batch-all) ·
[Hooks](#-hooks) · [Other agents](#-other-agents)

---

## 🔌 Setup and connection

| Symptom | Fix |
|---------|-----|
| "YouTrack MCP server isn't connected" | `YOUTRACK_MCP_URL` / `YOUTRACK_TOKEN` are not set in the shell that launched Claude Code, or your proxy blocks `/mcp`. Check `curl -H "Authorization: Bearer $YOUTRACK_TOKEN" "$YOUTRACK_MCP_URL"`. |
| MCP connects but writes fail with 403 | The token's user lacks permission on that project, or the token scope is wrong. |
| "There is no project named …" although the project exists | Fixed in 0.15.1: the skill searches by repo name first and, if needed, pages through *all* projects (the YouTrack MCP server returns only 20 per page) before claiming a project is missing. Update the plugin (`/plugin marketplace update youtrack-task`, then `/plugin update youtrack-task@youtrack-task`) and restart Claude Code. A project whose name differs from the repo name can always be named with `--project KEY`. |
| Scripts reported as missing (`SCRIPTS=missing`) | The skill was loaded without its `scripts/` directory, so it falls back to plain git in place. Install it as a plugin (or copy the whole skill directory) so `‹skill-dir›/scripts/read-config` exists. |
| Issues still come out in English although you write German | Almost always a stale plugin: third-party marketplaces don't auto-update. Run `/plugin marketplace update youtrack-task` then `/plugin update youtrack-task@youtrack-task`, restart Claude Code, and check the version under `/plugin`. Enable *Auto-update* for the marketplace in `/plugin` → Marketplaces to stop it recurring. If it persists, name the language in your input ("auf Deutsch"): an explicit instruction always wins. |

## 🌿 Pickup

| Symptom | Fix |
|---------|-----|
| The flow stops after the plan and nothing is implemented | By design: implementing needs the `--implement` flag (`/youtrack-task ‹ID› --implement`; on an existing worktree it continues from the plan comment on the issue). There is no go-ahead question. |
| "Shall I continue with `<ID>`?" before the pickup although `confirm_branch_name = false` | There is no such question. If an ID does not exist (typo in the project key, say) the skill stops, names the ID and the likely intended one, and you run it again with the right ID. Anything else that asks before the pickup is a bug: report it with the transcript. |
| Asked every time whether the branch name is OK | Set `confirm_branch_name = false` in the config, or pass `--no-confirm-branch` for one run. `--confirm-branch` asks again when the config says no. Still asked with `false` set? Check that the transcript shows `scripts/read-config` running first, and that the key sits at the top level of the file, not under a `[table]`. |
| Branch name too long | Slugs are capped; if it's still awkward, rename with `git branch -m`. |
| `ERROR=cannot-resolve-base` from the workspace step | Neither `origin/<base>` nor a local `<base>` branch exists (typically a typo in `--base`, or a repo with no remote default branch). Fix the name or create/fetch the branch and run again. Before 0.16.2 the branch silently started at the current HEAD instead. |
| State change skipped with a warning | The skill couldn't identify the state field from the project schema. Set `in_progress_state` / `testing_state` / `done_state` in the config to match your project's field values. |

## 📝 Issues and comments

| Symptom | Fix |
|---------|-----|
| `comment` / `testing` / `done` picked the wrong issue | A leading token that looks like an issue ID (`PROJ-12`, `P2X-5`) is taken as the issue; anything else is text and the issue comes from the branch name (its first ID match). Pass the ID explicitly when the branch name has several. |
| New issue assigned to you instead of the requested user | The `--assignee` login / email wasn't found in YouTrack, so `new` fell back to the token's owner (flagged at the confirm step). Check the exact login under YouTrack → Users. |
| New issue created unassigned | The project has no `Assignee` field, or setting it failed (e.g. the user isn't allowed as assignee in that project). The report says which; assign it in YouTrack. |
| Issue created in conversation (not via `new`) ended up unassigned or English | The plugin's `create_issue` hook now rejects a call without an Assignee and tells Claude to retry with you as assignee (needs `jq` on your `PATH`; Claude Code only). Update the plugin and restart if you still see it. |

## 🚀 Pull requests and review

| Symptom | Fix |
|---------|-----|
| Asked every time "push and open a PR?" by `pr` | Set `confirm_pr = false` in the config, or pass `--no-confirm-pr` for one run. `--confirm-pr` asks again when the config says `false`. The review gate and the other `pr` checks are not affected. |
| `pr` refuses with `FAILED` / asks for a review | The review gate is mandatory before a push: the stamped `PASS` must match the current HEAD, so any commit after the review (or uncommitted changes) makes it `STALE` and `pr` reviews again. Open findings (`FAILED`) must be fixed first. To push without a review on purpose use `--no-review`; the PR is then labelled *Review: skipped*. |
| A push or `gh pr create` is blocked with "Blocked by the youtrack-task review gate" | `review_gate_hook = "on"` is set and the exact commit has no review stamp. Run `/youtrack-task pr` (it reviews, then pushes), or waive on purpose with `/youtrack-task pr --no-review`, or set `review_gate_hook = "off"`. |

## 🌲 Worktrees

| Symptom | Fix |
|---------|-----|
| "cannot checkout `<branch>` — already checked out at `.worktrees/…`" | The branch lives in a worktree. `/youtrack-task worktree take <ID>` frees it and switches you to it; or just `cd` into that worktree. |
| Worktrees piling up | `/youtrack-task pr` clears merged ones automatically; `/youtrack-task worktree prune` sweeps on demand. |

## 🤖 Batch (`all`)

| Symptom | Fix |
|---------|-----|
| `all` finds nothing although the repo's project has open tickets | Fixed in 0.16.1: without IDs, `all` now limits `batch_query` to this repo's project (before, other projects' tickets filled the first 20 results), reads every result page, and treats a project's initial state (e.g. `Submitted`) like `Open`. Update the plugin and restart Claude Code. A `batch_query` with its own `project:` clause is used as written. |
| `all` says no issue is ready | Every candidate failed triage; the table names the reason per issue (tag in `batch_skip_tags`, no acceptance criteria, open questions, architectural size, unresolved dependency). Fix the issue, drop the tag, or run `/youtrack-task <ID>` interactively. |
| A worker reports `BLOCKED` / `ESCALATE` | It hit ambiguity or architectural scope and stopped on purpose; its question is posted on the issue. Answer it and re-run `all <ID>` (the existing worktree is resumed), or take the issue interactively. |
| `all` unavailable when installed as a skill only (e.g. the marketplace ZIP) | The `ticket-worker` / `ticket-reviewer` agents and the guard hook ship with the **plugin**. Without them `all` falls back to sequential work in the main session with a weaker, same-session review. |

## 🛡️ Hooks

| Symptom | Fix |
|---------|-----|
| A reviewer command is rejected by the hook (e.g. a Gradle task) | The reviewer is read-only and runs an allowlist. Gradle is allowed for check tasks by exact name only (`test`, `check`, `lint`, `detekt`, `ktlintCheck`, `spotlessCheck`, `lint(Debug\|Release\|Vital\|VitalRelease)`, `test<Variant>UnitTest`, optionally with a `:module:` path) and the options `--no-daemon`, `--offline`, `--tests <pattern>`, `-x <task>` and a few logging flags. Build, publish and clean tasks, `-D` / `-P`, `-I` / `-b` / `-c`, and globs in option values are denied. Task abbreviations such as `lintF` are denied on purpose (Gradle would expand them to `lintFix`). Needs plugin 0.15.4 or newer. |
| A worker command or file write is rejected by the hook | Working as intended: workers never push or merge, use no network tools and write only inside their worktree; the main session pushes after review. Needs `jq`; if you see no guard at all, check that the plugin (not just the skill) is installed and up to date. |

## 🧩 Other agents

| Symptom | Fix |
|---------|-----|
| Skill runs in Cursor / Copilot but no YouTrack tools are found | Add the YouTrack MCP server to that agent's MCP settings (see [Other agents](./other-agents.md)); the skill matches tool names by base name, so any prefix works. |
