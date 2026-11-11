# Example: pick up an issue

Illustrative run. Project key, issue and branch are placeholders.

```text
> /youtrack-task PROJ-42
```

**1. Brief** (from `get_issue` + `get_issue_comments`)

```text
PROJ-42 — Rotate expired API tokens
Type: Task · Priority: Major · State: Open · Subsystem: —
Gist: Tokens created before 2026 expire silently; add a rotation job and an
expiry warning. Decisive comment: "keep the old token valid for 24h".
```

**2. Workspace.** With `confirm_branch_name = true` the computed name is shown for
accept / rename; with `false` (or `--no-confirm-branch`) one line and no question:

```text
→ Branch: chore/PROJ-42-rotate-expired-api-tokens
```

`scripts/setup-workspace` output, then the agent acts on `MODE=`:

```text
MODE=inplace
BRANCH=chore/PROJ-42-rotate-expired-api-tokens
BASE=main
DIR=/home/dev/projects/api
```

The branch name is always English (`<prefix>/<ID>-<slug>`), whatever language the
issue is written in. Type → prefix: Bug `fix`, Feature `feat`, Task `chore`.

**3. Write-back on pickup**

- State: `Open` → `In Progress` (`update_issue`).
- Comment on the issue:

```markdown
📌 Picked up in Claude Code

Branch `chore/PROJ-42-rotate-expired-api-tokens` off `main`.
```

**4. Plan** — the agent explores the repo, drafts a plan, and waits for approval.
Only after approval is the plan posted to the issue as a comment (and, if the repo
has `docs/`, saved as `docs/plans/PROJ-42.md`):

```markdown
## 📝 Implementation plan (Claude Code)

_Generated 2026-11-11_

1. Add a nightly rotation job …
2. Warn 7 days before expiry …
```

Without `--implement` the flow stops here: *"Plan is on `PROJ-42`. Run
`/youtrack-task PROJ-42 --implement` to implement it."*

**5. Implement (`--implement`)** — the work is verified against the acceptance
criteria, then the review gate runs: a fresh `ticket-reviewer` judges the diff and
the result is stamped on the exact commit. The completion comment reports it:

```markdown
## ✅ Implemented (Claude Code)

Branch `chore/PROJ-42-rotate-expired-api-tokens`. Files touched:
- src/tokens/rotate.ts

Review: PASS @ abc1234 (1 round).

Not pushed; no PR.
```

Next is `/youtrack-task pr`.
