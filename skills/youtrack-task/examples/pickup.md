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

**2. Workspace** (`scripts/setup-workspace` output, then the agent acts on `MODE=`)

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
has `docs/`, saved as `docs/plans/PROJ-42.md`).
