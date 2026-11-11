# `pr` — push, open a PR, record it on the issue

Loaded by the `pr` dispatch row of `SKILL.md`. Bound by the **Guardrails** there:
no push or PR without a review, never a force-push. The review gate itself is
`reference/review.md`; comment templates are in `reference/writeback.md`.

`/youtrack-task pr [ISSUE-ID] [--no-move] [--base <branch>] [--draft] [--no-review]
                  [--confirm-pr | --no-confirm-pr]`

Push the current feature branch, open a GitHub PR, record it on the issue, and
move the issue to Testing. This is the one place the skill is allowed to push.
Requires `gh` on `PATH` (`gh --version`); if missing, stop and tell the user to
push + open the PR themselves, then run `/youtrack-task link <url>`.

1. Resolve the issue ID (leading ID argument → branch → ask; see "Issue IDs").
2. **Checks**, all must pass or stop:
   - inside a git repo, and **not** on the default branch (resolve the default
     the same way as `reference/branching.md`; `--base` overrides).
   - the branch has commits ahead of the base (`git rev-list --count <base>..HEAD`
     > 0), else *"no commits on this branch"*.
3. **Clean tree, then review**, in this order (the review may add fix commits,
   which is why the diffstat comes only after it):
   1. **Working tree.** `git status --porcelain` empty → go on. Otherwise ask
      **once**: commit (English conventional message, never on the default
      branch), stash (`git stash push -u -m "<unique-tag>"`), or stop.
      Uncommitted changes would not be in the PR, and every review stamp — the
      waiver included — needs a clean tree.
   2. **Review gate**, decided from the step-0 output and the flags:

      | `--no-review`, or `REVIEW_BEFORE_PR=never` | do this |
      | --- | --- |
      | neither | run `<skill-dir>/scripts/review-stamp check --id <ID>` per `reference/review.md`. `PASS` with `INDEPENDENT=yes` → continue. `STALE` / `MISSING` → run the review gate now (`fixer = main-session`), then continue on `PASS`. `FAILED` → stop and show the open findings. `PASS` with `INDEPENDENT=no` → say the review was not independent and continue only on explicit confirmation. `SKIPPED` → continue, labelled skipped (below) |
      | `--no-review` | ask for explicit confirmation naming the risk (*"this branch has no independent review"*), then record the waiver. A `SKIPPED` stamp already on this commit counts as that confirmation |
      | `REVIEW_BEFORE_PR=never`, no flag | no question; record the waiver |

      Recording the waiver: `review-stamp write --verdict SKIPPED --independent no`
      (see `reference/review.md`). Then add the line `Review: skipped (not
      independently reviewed)` to the PR body and to the YouTrack PR comment.
      Never skip silently.
4. Show `git log --oneline <base>..HEAD` and `git diff --stat <base>...HEAD`
   (always), then decide from the step-0 output:

   | `--no-confirm-pr`, or `CONFIRM_PR=false` without `--confirm-pr` | do this |
   | --- | --- |
   | yes | print one line `→ Pushing <branch> and opening a PR (confirm_pr off)` and go on to step 5. **No question.** |
   | no | **ask for confirmation** before pushing. |

   This table gates only the push-and-PR question. The checks in steps 2–3 are
   unaffected and still stop or ask as written there.
5. `git push -u origin <branch>` (plain push; never `--force`).
6. Open the PR and capture its URL:
   - If `gh pr view <branch> --json url,state` already shows an open PR, reuse its
     URL — don't create a second one.
   - Else `gh pr create --base <base> --head <branch> --title "<ID>: <clean-summary>"
     --body "<body>"` (`--draft` if the flag was passed). `<clean-summary>` is the
     issue title **in English** (translate if the issue isn't), with the
     leading type word stripped — same as the slug rule in `reference/branching.md`
     (`"Bugfix: Hover-Effekt bei markierten Zeilen"` → `"Keep row tint visible on hover"`).
     If the repo has `.github/pull_request_template.md` or
     `.github/PULL_REQUEST_TEMPLATE/`, fill that template and append the lines
     below rather than replacing it.
   - `<body>` is **English** and always includes: a link to the YouTrack issue
     (`<YOUTRACK_MCP_URL without /mcp>/issue/<ID>`), a one-line summary, and a
     short bullet list of the commits. The merge commit inherits this title, so
     it must not carry non-English text.
7. **YouTrack write-back**, in this order:
   1. Unless `--no-move`: if the issue is before `testing_state` on the ladder,
      `update_issue` → `testing_state`. Skip silently if already at Testing/Done.
      Note whether the state actually changed.
   2. `add_issue_comment` with the `pr` template from `reference/writeback.md`,
      its suffix chosen from that result:

      | State change in 7.1 | Comment |
      | --- | --- |
      | done | `🔗 PR opened: <url>, moved to Testing.` |
      | skipped (`--no-move`, already Testing/Done) or failed | `🔗 PR opened: <url>` (`🔗 PR: <url>` if the PR already existed) |
8. Run `<skill-dir>/scripts/sweep-worktrees --exclude <this-branch>` to clear
   worktrees whose PR has already merged/closed. Report its `REMOVED` lines.
   **This** worktree stays — the PR is open, review fixes go here;
   `/youtrack-task done` (or `worktree prune`) removes it once merged.
9. Report: PR URL, whether it was newly created or already existed, the state
   change, what `sweep-worktrees` cleaned up, and that `/youtrack-task done` is
   the step after the PR merges.
