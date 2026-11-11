# Write-back rules

All writes go through the YouTrack MCP server (`mcp__youtrack__*`). Never call the
REST API directly.

**Language:** every comment (pickup, plan, completion, state changes) is written
in the language resolved by SKILL.md "Language" — a German issue gets German
comments, and never silently English because a global rule says "English
everywhere". Template headings and emoji stay as written below; the text after
them is the resolved language. Git artifacts — branch names, commit messages,
PR title/body — are always English (see `reference/branching.md`). Don't mix the
two up.

## Finding the state field (do this before any state change)

1. Call `get_issue_fields_schema` for the issue's project.
2. Find the single-value enum/state field whose allowed values include the
   configured `in_progress_state` (default `In Progress`). That field is "the
   state field" for this project — its name may be `State`, `Stage`, etc.
3. If no field matches, skip the state change, warn the user, and continue. Do
   not guess.

Cache the resolved field name for the rest of the session; re-resolve per project.

## State ladder

`Open → In Progress → Testing → Done`

| Trigger | Target state | Skip when |
| --- | --- | --- |
| pickup (primary flow, unless `--no-move`) | `in_progress_state` | issue already at In Progress, Testing, or Done |
| `/youtrack-task pr` (unless `--no-move`) | `testing_state` | issue already at Testing or Done |
| `/youtrack-task testing` | `testing_state` | issue already at Testing or Done |
| `/youtrack-task done` | `done_state` | issue already at Done |

"Already at a later state" is decided by ladder position, not string equality.
Ladder order: Open=0, In Progress=1, Testing=2, Done=3. Any other unresolved state
that is not `in_progress_state` / `testing_state` / `done_state` — a project's
initial state such as `Submitted`, `Reopened`, `To be discussed` — counts as
position 0. Only move forward; never
move an issue backward automatically — if the user asks for `testing` on an issue
that is already `Done`, tell them and do nothing.

The ladder itself is fixed; only the state names are configurable. State names are overridable in `~/.config/youtrack-task/config.toml`
(`in_progress_state`, `testing_state`, `done_state`).

Perform the change with `update_issue`, setting the resolved state field to the
target value.

## Comments

Use `add_issue_comment`. Markdown body. One comment per event.

| Event | Body template |
| --- | --- |
| pickup | `📌 Picked up in Claude Code\n\nBranch `<branch>` off `<base>`.` |
| plan | `## 📝 Implementation plan (Claude Code)\n\n_Generated <ISO-date>_\n\n<plan markdown>` |
| completion | `## ✅ Implemented (Claude Code)\n\nBranch `<branch>`. Files touched:\n<bullet list>\n\nReview: <PASS @ <short-sha> (<n> round(s)) \| skipped \| not independent>.\n\nNot pushed; no PR.` — one comment, only when step 8 (`--implement`) actually implemented something and the review gate did not end `FAILED` |
| worker plan (`all`) | `## 📝 Worker plan (summary, Claude Code)\n\n<PLAN lines>` — a post-hoc summary for audit; in `all` the triage confirmation replaces per-issue plan approval |
| completion (`all`, `PASS` only) | `## ✅ Implemented and reviewed (Claude Code)\n\nBranch `<branch>`. Independent review: PASS (<n> round(s)). Files touched:\n<bullet list>\n\nNot yet pushed or merged.` — the wording follows what actually happened (after `pr`: *PR opened*; after an auto-merge: *merged*) |
| status (`all`, not `PASS`) | `## ⏸ Needs attention (Claude Code)\n\n<reason: question / architectural / open review findings>` — never claims anything was implemented |
| `log` | handled by `log_work`; add a comment only if the user passed a description |
| `pr` | `🔗 PR opened: <url>` — written **after** the state change; append `, moved to Testing.` only when that change actually happened (not with `--no-move`, not when the issue was already at Testing/Done, not when it failed); if the PR already existed, `🔗 PR: <url>`; when the review was skipped add a second line `Review: skipped (not independently reviewed)` |
| `link` | `🔗 PR: <url>` |
| `testing` | `🧪 Moved to Testing by Claude Code.` + optional user note |
| `done` | `✅ Moved to Done by Claude Code.` + optional user note |

`--no-writeback` on the primary flow suppresses both the pickup state change and
the pickup comment. It does not affect the later plan comment (that one is always
gated on explicit user approval of the plan — except in `all`, where the single
triage confirmation stands in for it) or the sub-commands.

## Time logging

`/youtrack-task log [ISSUE-ID] <duration> [description]`

- `<duration>` is passed straight to `log_work` in YouTrack's period format
  (`1h`, `30m`, `1h30m`, `2d`).
- `[description]` becomes the work item's text.
- If `ISSUE-ID` is omitted, extract it from the current branch name; if that
  fails, ask.

## Failure handling

- Any MCP write returning 403 / permission denied: report exactly which call
  failed and on which issue, then continue. In the primary flow the branch is
  already created, so planning proceeds regardless.
- `get_issue` 404: stop, show the ID that was tried.
