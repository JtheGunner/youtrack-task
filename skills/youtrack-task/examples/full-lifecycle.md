# Example: one issue from idea to done

Illustrative run. Project key, issue, branch, user and URLs are placeholders. Each
step links to the detailed example for that command.

```text
/youtrack-task new …      →  /youtrack-task PROJ-42  →  /youtrack-task pr  →  … merge …  →  /youtrack-task done
```

## 1. Capture — `new`

```text
> /youtrack-task new "Expired API tokens are never rotated; add a nightly rotation job and a warning 7 days before expiry"
```

The skill drafts a title and a structured description (Summary, Context, Goal,
Acceptance criteria, Scope), infers the Type, and asks for **one** confirmation.

```text
Project:   PROJ (this repo)
Title:     Rotate expired API tokens nightly
Type:      Task                      ← inferred, please confirm
Assignee:  dev.user (API-key owner)
Create it? (edit any field, or confirm)
```

After **yes**: `Created PROJ-42` and the offer to pick it up.
Detail: `examples/new.md`.

## 2. Pick up — `PROJ-42`

```text
> /youtrack-task PROJ-42
→ Branch: chore/PROJ-42-rotate-expired-api-tokens
```

What happens on the way, with no extra question:

- an isolated worktree is created from the up-to-date default branch;
- the issue moves **Open → In Progress**;
- the issue gets a pickup comment:

```markdown
📌 Picked up in Claude Code

Branch `chore/PROJ-42-rotate-expired-api-tokens` off `main`.
```

Detail: `examples/pickup.md`.

## 3. Plan

The skill explores the repo and presents a plan. You iterate on it; only after you
approve it is it written back to the issue:

```markdown
## 📝 Implementation plan (Claude Code)

_Generated 2026-01-15_

1. Add a nightly rotation job for tokens older than their expiry.
2. Send a warning 7 days before expiry.
3. Cover both with tests.
```

The plan comment follows the issue's language; branch names and commits are always
English.

## 4. Implement — `PROJ-42 --implement`

```text
> /youtrack-task PROJ-42 --implement
```

The plan is carried out (tests first when the superpowers plugin is present), then an
independent reviewer reads the branch against the issue's acceptance criteria:

```text
Review: PASS @ abc1234 (1 round)
```

A completion comment lists the branch, the files touched and the review result. Nothing
is pushed yet.

## 5. Ship — `pr`

```text
> /youtrack-task pr
REVIEW=PASS   INDEPENDENT=yes   (stamped on this exact HEAD)

abc1234 Rotate expired API tokens nightly
def5678 Warn 7 days before token expiry
 2 files changed, 85 insertions(+)

Push chore/PROJ-42-rotate-expired-api-tokens and open a PR? (yes/no)
```

After **yes** the branch is pushed (plain push, never forced), the PR is opened with an
English title and body, the issue moves **In Progress → Testing**, and it gets:

```markdown
🔗 PR opened: https://github.com/example-org/api/pull/17, moved to Testing.
```

`pr` is the only command that pushes. Detail: `examples/pr.md`.

## 6. Close — `done`

After the PR is reviewed and merged:

```text
> /youtrack-task done
```

The issue moves **Testing → Done**, gets `✅ Moved to Done by Claude Code.`, and the
finished worktree is removed safely (never forced, never with uncommitted changes).

## What each step wrote to YouTrack

| Step | State | Comment |
| --- | --- | --- |
| `new` | created, assigned to you | — |
| pickup | Open → In Progress | `📌 Picked up in Claude Code` |
| plan | — | `## 📝 Implementation plan (Claude Code)` |
| `--implement` | — | `## ✅ Implemented (Claude Code)` |
| `pr` | In Progress → Testing | `🔗 PR opened: <url>, moved to Testing.` |
| `done` | Testing → Done | `✅ Moved to Done by Claude Code.` |
