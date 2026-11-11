# Sub-commands: `testing`, `done`, `log`, `comment`, `link`, `worktree`

Loaded by the matching dispatch rows of `SKILL.md`. Bound by the **Guardrails**
and the **Language** rules there; comment templates are in
`reference/writeback.md`, the worktree scripts' contract in
`reference/worktrees.md`. Step 0 (`read-config`) has already run.

## State sub-commands (`testing`, `done`)

1. Resolve the issue ID (leading ID argument → branch → ask; see "Issue IDs").
2. Resolve the state field via `get_issue_fields_schema`.
3. Determine ladder positions. Target: `testing_state` for `testing`,
   `done_state` for `done`.
4. If the issue is already at or past the target on the ladder
   (`Open<In Progress<Testing<Done`), report its current state and do nothing.
5. Otherwise `update_issue` to the target, then `add_issue_comment` with the
   matching template. If the user appended text after the sub-command, include it
   in the comment as a note.
6. After `done`:
   - if a local branch for this issue still exists and `gh pr view <branch>`
     shows no merged PR, add one line — *"Branch `<branch>` isn't merged yet —
     `/youtrack-task pr` or `/ship` to integrate it."* No git action.
   - otherwise run `<skill-dir>/scripts/sweep-worktrees` and report its `REMOVED` / `KEPT_DIRTY` / `KEPT_OPEN` lines. It removes only
     clean worktrees whose PR is merged/closed (limits: Guardrails).

Never move an issue backward. `testing` / `done` change YouTrack state and, via
`sweep-worktrees`, only ever *remove* finished worktrees — they never create or
switch branches.

## log

`/youtrack-task log [ISSUE-ID] <duration> [description...]`

1. Resolve issue ID (a leading ID token, else from branch, else ask; see "Issue IDs").
2. `<duration>` is the next token, in YouTrack period format (`1h`, `30m`,
   `1h30m`, `2d`). If it doesn't parse as a period, stop and show the format.
3. Everything after `<duration>` is the work description (optional).
4. Call `mcp__youtrack__log_work` with issue, duration, and description.
5. Confirm what was logged.

## comment

`/youtrack-task comment [ISSUE-ID] <text...>`

1. Resolve the issue ID per "Issue IDs": a first token that is an ID is the issue
   and the rest is the text; otherwise the ID comes from the current branch (else
   ask) and everything after `comment` is the text.
2. `mcp__youtrack__add_issue_comment` with the verbatim text (no emoji prefix
   added — the user's words stand as-is).
3. Confirm.

## link

`/youtrack-task link [ISSUE-ID] <pr-url>`

Attach an already-existing PR (from `/ship`, `gh`, or the web UI) to the issue.
Does not push and does not change state.

1. Parse args: if the first token is an issue ID (`^ISSUE_ID_RE$`), the second is the URL; otherwise
   the first token is the URL and the issue ID comes from the branch (else ask).
2. Sanity-check the URL is `http(s)://…`; warn (don't block) if it isn't a
   `…/pull/<n>` GitHub URL.
3. `mcp__youtrack__add_issue_comment`: `🔗 PR: <url>`.
4. Confirm.

## worktree

`/youtrack-task worktree list|prune|take|remove`  (see `reference/worktrees.md`)

- **`list`** — `git worktree list` filtered to worktrees under `worktree_dir`
  whose name looks like `<ID>-<slug>`; for each, show the branch and the issue's
  current YouTrack state (`get_issue`).
- **`prune`** — run `<skill-dir>/scripts/sweep-worktrees` and report every line. It removes clean worktrees whose PR is merged/closed and
  `git branch -d`s the merged branch, then `git worktree prune`; dirty ones and
  still-open PRs are listed, not touched.
- **`take <ISSUE-ID>`** — you want that issue's branch in your *current* checkout
  but a worktree still holds it. Run `<skill-dir>/scripts/worktree-detach --id <ID> --switch`:
  it removes that worktree (branch kept) and `git switch`es to the branch here.
  A dirty worktree is refused (`ERROR=dirty` — commit/stash in it first); the
  switch is skipped if the current checkout has tracked changes. Report `REMOVED`
  / `SWITCHED` / any `NOTE`.
- **`remove <ISSUE-ID>`** — just drop the worktree, don't switch:
  `<skill-dir>/scripts/worktree-detach --id <ID>`. Same safety; the branch survives.
