# Manual test checklist

No mock server. Run these against real YouTrack after any change to the skill.
Use a throwaway or low-stakes issue.

| # | Steps | Expect |
| --- | --- | --- |
| 1 | `/youtrack-task` with no arg, inside a repo | numbered list of your Open / In Progress issues |
| 2 | Pick one from the list | branch `‹prefix›/‹ID›-‹slug›` created off `origin/‹default›`; issue → In Progress; 📌 pickup comment visible in PhpStorm |
| 3 | `/youtrack-task ‹ID›` with explicit ID | same as #2, no list shown |
| 4 | Run from a branch already named `…‹ID›…` | prompts "continue on ‹ID›?"; no list |
| 5 | `/youtrack-task ‹ID› --no-move --no-writeback` | branch only; YouTrack untouched |
| 6 | Run with a dirty working tree | refused before branching; offers `git stash push -u` |
| 7 | Run against an issue whose project ≠ current repo | mismatch warning; can override |
| 8 | Approve a plan | 📝 plan comment on the issue; `docs/plans/‹ID›.md` created only if repo has `docs/` |
| 8i | pickup with `superpowers` installed, non-Bug issue that brainstorming rates **bounded** | step 6 runs `superpowers:brainstorming` seeded from the description sections; step 8 (on go) uses TDD + `verification-before-completion` against the acceptance criteria; no plan doc, no auto code review |
| 8j | pickup a Bug-type issue with `superpowers` | step 6 starts with `superpowers:systematic-debugging` |
| 8k | architectural plan, then implement | plan doc written (prefers `docs/superpowers/specs/`); executed via `subagent-driven-development`; auto `requesting-code-review` runs; `--checkpoints` switches to `executing-plans` |
| 8l | `use_superpowers = "never"` in config | plain plan mode, no superpowers skills invoked |
| 8m | `--no-review` on an architectural task | code review skipped, verification still runs |
| 8n | `/youtrack-task ADMIN-x` while the checkout is clean and on the default branch (`worktree = auto`) | in-place `git switch -c`, no worktree |
| 8o | same, but checkout is on another `feat/…` branch | worktree at `.worktrees/ADMIN-x-…`; `.worktrees/` appended to `.git/info/exclude` if not already ignored — **no commit on the user's branch** |
| 8p | worktree pickup in a Laravel repo | `node_modules`, `vendor`, `storage` CoW-cloned (`cp -c`), `.env` symlinked; `.claude/youtrack-worktree-setup.sh` run if present; report lists what was linked + any `npm run build` hint |
| 8q | `worktree = always`, run `/youtrack-task ADMIN-a` and `/youtrack-task ADMIN-b` in two terminals | two independent worktrees + branches; `pr` from each resolves the right issue; a racing `git worktree add` retries once on `index.lock` |
| 8q2 | `worktree = auto`, same two-terminal run from a clean on-default repo | first pickup is **in-place**, only the second becomes a worktree (documented asymmetry) |
| 8r | `--no-worktree` while on a feat branch | forced in-place (stash/carry prompt), no worktree |
| 8s | `/youtrack-task worktree list` | lists only `.worktrees/<ID>-<slug>` entries with branch + YouTrack state |
| 8t | `/youtrack-task done` for an issue whose worktree's PR is merged | clean → offers `git worktree remove` + `git branch -d`; **dirty → reports it and removes nothing, no prompt** |
| 8u | `/youtrack-task worktree prune` with one dirty worktree among Done ones | removes the clean Done ones + their merged branches (`git branch -d`), reports the dirty one, never `--force` |
| 8v | `/youtrack-task ADMIN-x` where the issue is already In Progress **and** a worktree for it exists | resumes into that worktree (`EnterWorktree`/cd), no new branch, no state change, no pickup comment; goes straight to plan/implement reusing the existing plan comment |
| 8w | same, but the previous session's branch was deleted (no branch/worktree for the issue) | announces "already In Progress but has no branch — starting a fresh one", runs step 4 **in full incl. the worktree decision** (so under `worktree = always` it lands in `.worktrees/…`, not an in-place branch), skips only the state change |
| 8x | resume where a local `*ADMIN-x*` branch exists but isn't checked out | offers `git switch` or `git worktree add <path> <that-branch>` per the worktree decision; doesn't recreate the branch |
| 8b | `/youtrack-task new` (bare) inside a repo | asks free-text-or-fields; field path → prompts project (repo default offered), title, description; infers Type + confirm; one confirm → created; reports ID + URL; offers pickup |
| 8c | `/youtrack-task new --project ADMIN --title "X" --description "Y" --priority Major --type Bug` | no prompts except the final confirm; issue created with Bug + Major |
| 8d | `/youtrack-task new --title "Fix broken login redirect" --description "..."` (no --type) | Type inferred as Bug/Fix with a rationale line, asked to confirm |
| 8e | `/youtrack-task new --project NOPE ...` | rejects the unknown project key, lists / asks for a valid one; nothing created |
| 8f | `/youtrack-task new "hover on tinted rows loses the colour on mouseover; want a same-hue hover instead"` | generates a ≤70-char imperative title + a description with Summary/Context/Goal/Acceptance criteria/Scope sections in the input language; no invented facts; Type inferred; editable; one confirm → created |
| 8g | free-text blob that says "prod is down, blocker" | Priority proposal surfaced and asked, not silently set |
| 8h | free-text mode, then edit the generated title at the confirm step | edited title used; description unchanged |
| 9 | `/youtrack-task comment hello world` | comment "hello world" on the branch's issue, no emoji prefix |
| 10 | `/youtrack-task log 15m tried X` | 15m work item logged (or graceful "time tracking not enabled" message) |
| 11 | `/youtrack-task pr` on a branch with commits | shows commits + diffstat, asks before push; then `git push`, `gh pr create`, `🔗 PR opened` comment, issue → Testing |
| 12 | `/youtrack-task pr` again on the same branch | reuses the existing PR URL, no second PR; comment + state still consistent |
| 13 | `/youtrack-task pr` with `gh` not on PATH | stops with instructions to push + open PR manually, then use `link` |
| 14 | `/youtrack-task pr --no-move` | PR opened + linked, issue state unchanged |
| 15 | `/youtrack-task link https://github.com/o/r/pull/1` | `🔗 PR: <url>` comment; no push, no state change |
| 16 | `/youtrack-task testing` | issue → Testing; 🧪 comment |
| 17 | `/youtrack-task done` | issue → Done; ✅ comment; if branch unmerged, one-line `/youtrack-task pr` reminder |
| 18 | `/youtrack-task testing` on an already-Done issue | no change; reports current state |
| 19 | Unset `YOUTRACK_TOKEN`, restart, run anything | setup message, no stack trace |
