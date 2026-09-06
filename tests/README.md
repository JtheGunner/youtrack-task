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
| 10 | `/youtrack-task log 15m tried X` | 15m work item logged on the branch's issue |
| 11 | `/youtrack-task testing` | issue → Testing; 🧪 comment |
| 12 | `/youtrack-task done` | issue → Done; ✅ comment |
| 13 | `/youtrack-task testing` on an already-Done issue | no change; reports current state |
| 14 | Unset `YOUTRACK_TOKEN`, restart, run anything | setup message, no stack trace |
