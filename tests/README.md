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
