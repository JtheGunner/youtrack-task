# Example: open a PR and write it back

Illustrative run. Branch, issue and URL are placeholders.

```text
> /youtrack-task pr
```

**1. Checks** — inside a git repo, not on the default branch, commits ahead of the
base, clean tree (a dirty tree only produces a warning).

**2. Confirmation before pushing**

```text
abc1234 Rotate expired API tokens nightly
def5678 Warn 7 days before token expiry

 src/tokens/rotate.ts | 54 ++++++++++++++
 src/tokens/warn.ts   | 31 +++++++++
 2 files changed, 85 insertions(+)

Push chore/PROJ-42-rotate-expired-api-tokens and open a PR? (yes/no)
```

**3. After yes**

- `git push -u origin <branch>` — a plain push, never `--force`.
- `gh pr create` with an English title `PROJ-42: Rotate expired API tokens` and an
  English body that links the issue and lists the commits. An already open PR for
  the branch is reused, not duplicated.
- Comment on the issue and state change `In Progress` → `Testing`:

```markdown
🔗 PR opened: https://github.com/example-org/api/pull/17 — moved to Testing
```

- `scripts/sweep-worktrees --exclude <this-branch>` removes other worktrees whose
  PR is already merged or closed. The current worktree stays until the PR merges
  and `/youtrack-task done` runs.

`--no-move` keeps the issue state, `--draft` opens a draft PR. Without `gh`, the
skill stops and asks you to push and open the PR yourself, then run
`/youtrack-task link <url>`.
