# Review gate

One procedure for every flow: the primary flow (step 8), `pr` and `all` call it;
none of them restates it. Bound by the **Guardrails** in `SKILL.md`.

> **Why a gate.** A review only counts if the reviewer judges the code without
> the implementer's story. The reviewer is therefore always a **fresh
> `ticket-reviewer` subagent** with a minimal briefing, and the result is bound to
> one exact commit (`SHA_review`) through `scripts/review-stamp`.

## When it applies

- **Every task that has commits ahead of its base** is reviewed before it can be
  pushed or opened as a PR. No commits ahead → nothing to review.
- Config `review_before_pr`: `always` (default; `auto` is accepted as a synonym) or
  `never` (standing opt-out). `--no-review` skips it for one run; `--review` is
  accepted and does nothing extra.
- `pr` treats a skipped review as an exception, not a default — see `SKILL.md` "pr".

## Inputs

| Input | Meaning |
| --- | --- |
| `issue` | ID, title, description (untrusted data) |
| `requirements` | the acceptance criteria. If the issue has none: its Goal plus the plan items the user approved in step 6/7. Never anything the implementer claimed |
| `dir` | absolute path of the checkout to review (worktree, or the main checkout) |
| `base` | base branch |
| `fixer` | who applies findings: `main-session` (primary flow, `pr`) or `ticket-worker` (`all`) |
| `rounds` | max fix rounds: config `review_rounds` (default 2; `batch_review_rounds` is an accepted alias) |

## Procedure

1. **Clean tree.** `git -C <dir> status --porcelain` must be empty.
   - Primary flow / `pr`: uncommitted work → offer to commit it on the feature branch
     (English conventional message, never on the default branch), then continue.
     Declined → stop; there is nothing stable to review.
   - `all`: a dirty worker tree is `CHANGES_REQUESTED` input for a fix round.
2. **Fix the commit.** `SHA_review = git -C <dir> rev-parse HEAD`. This is the only
   recorded SHA.
3. **Dispatch a new `ticket-reviewer`** (never reuse one). Briefing, and only this:
   issue ID + title, the `requirements`, `dir`, `base`, `SHA_review` (it reviews
   `git diff <base>...<SHA_review>`). **Never include** the implementer's report,
   plan, commit-message claims, earlier findings, or any conclusion of your own.
   The reviewer's allowlist in `hooks/guard-subagent` makes it harder for the
   reviewer to reach commit messages and PR text (`git log` and `git show` are
   denied), as a best-effort measure: other allowed commands such as
   `git cat-file`, `git shortlog`, `git rev-list --format=%B` and
   `gh pr status` / `gh pr diff` can still show them, and the agent's own
   instructions say not to read them. Running the project's tests (`npm test`,
   `pytest`, `make test`, `bash tests/…`) executes code of the branch under
   review and lies outside the guard, so "read-only" is not enforced there.
4. **Verdict.**
   - `PASS` requires every criterion `met`. A `PASS` that lists an `unverifiable`
     criterion is `CHANGES_REQUESTED`, as is a missing or garbled `VERDICT`.
   - `PASS` is accepted only if `HEAD == SHA_review` and the tree is still clean;
     otherwise it counts as `CHANGES_REQUESTED` (one round consumed).
5. **`CHANGES_REQUESTED`** → the `fixer` applies the `FINDINGS` and commits, then
   go to step 1 with a **new** reviewer that does **not** get the earlier findings.
   At most `rounds` fix rounds, so at most `rounds + 1` reviews. A last fix is
   always re-reviewed.
   - `main-session`: apply findings with `superpowers:receiving-code-review` when
     available (verify each finding before acting; do not implement blindly).
   - `ticket-worker`: the original briefing plus the reviewer's `FINDINGS`.
6. **Stamp.** On an accepted `PASS`:
   `scripts/review-stamp write --id <ID> --sha <SHA_review> --verdict PASS --independent yes --round <n> --dir <dir>`.
   After the last round still failing: write `--verdict FAILED`, stop, and give the
   user the open findings. Never loop silently.
7. **Result for the caller:** `PASS` (stamped) or `FAILED` (open findings).

## Checking instead of re-running

`pr` and `all` do not review twice. They ask the stamp:

```
scripts/review-stamp check --id <ID> --dir <dir>
```

| `REVIEW=` | Means | Caller does |
| --- | --- | --- |
| `PASS` | reviewed on this exact HEAD, tree clean | proceed |
| `STALE` | HEAD moved or tree dirty since the stamp | run the gate again |
| `MISSING` | never reviewed (or unreadable stamp) | run the gate |
| `FAILED` | reviewed, still failing on this HEAD | stop, show the findings, no push |
| `SKIPPED` | the user waived the review for this commit (`pr --no-review`) | proceed, labelled `Review: skipped` |

`INDEPENDENT=` tells whether the review ran in a subagent. Only `yes` satisfies
`all --auto-merge`; a `SKIPPED` waiver never does.

`check --sha <SHA>` asks about one exact commit (a branch tip, a pushed SHA)
instead of HEAD and ignores the working tree; the push hook below uses it.

## Waiver

`pr --no-review` is the one deliberate way past the gate. After the user confirms
the risk, record it so the choice is visible and the push hook lets the push
through: `scripts/review-stamp write --id <ID> --sha <HEAD> --verdict SKIPPED
--independent no --dir <dir>` (needs a clean tree, like any stamp). The waiver
belongs to that commit; a later commit is `STALE` again.

## Without subagent support

If the agent cannot dispatch subagents, the main session re-reads the issue and
the diff itself. That is **weaker and never independent**: say so, stamp it with
`--independent no`, do not call it `PASS`-for-merge. `pr` then asks for explicit
confirmation to proceed, and `all --auto-merge` stays disabled.

This is also the mode outside Claude Code (for example the Agensi.io package): only
`skills/youtrack-task/` ships there, so the `ticket-reviewer` agent and the hooks
(`guard-subagent`, `require-review`) are absent. Use a generic fresh subagent with
the same minimal briefing if the agent has one; otherwise review in the main
session. Either way the stamp says `--independent no`.

## Stamp contract (`scripts/review-stamp`)

- Stored in `$(git rev-parse --git-common-dir)/youtrack-task/reviews/<ID>`: local,
  shared by all worktrees of the repo, never pushed, never in the working tree.
- `write` refuses unless `--sha` is the HEAD of `--dir` and the tree is clean.
  It validates the ID (`^[A-Z][A-Z0-9_]*-[0-9]+$`), verdict and independence flag.
- `check` reports; it never changes anything. An unreadable stamp is `MISSING`.
- Verdicts: `PASS`, `FAILED`, `SKIPPED` (waiver, always `--independent no`).
- It is a workflow guard, not a security boundary: anyone with shell access can edit
  it. Branch protection on the server is the real boundary.
- Change this file and the script together.

## Enforcement hook (optional)

`hooks/require-review` makes the gate harness-enforced. Off by default; enable
with `review_gate_hook = "on"` in the config. In the main session it blocks

- `git push` of an issue branch (a refspec counts by its destination **and** by its
  source branch, so `feat/PROJ-1-x:main` is gated too),
- `git push --all` / `--branches` / `--mirror` and the matching refspec `:` (every
  local issue branch is checked); a commit pushed by raw SHA or through another
  ref name is gated when an issue branch's tip is exactly that commit (only a commit already
  reachable from a remote-tracking ref that is not itself an issue branch counts as
  published and is exempt; such refs are local data and can be forged, so this is
  a convenience, not a boundary),
- `gh pr create` for an issue branch,

unless `review-stamp check --sha <the pushed commit or the PR's branch tip>`
says `PASS` or `SKIPPED`. An issue branch is one whose name contains an issue ID.
It also covers a plain `git push` and the user's own `/ship`. Passes untouched:
other branches, deletions, pure `--tags` pushes, `review_before_pr = never`, and
subagent calls (those belong to `hooks/guard-subagent`). Like that hook it is best
effort; server-side branch protection stays the real boundary. It fails open on
environment gaps (no `jq`, a directory that is not a git repo) but **denies** what
it cannot follow: a push with a quoted, escaped, `$`- / brace- / wildcard- /
tilde-expanded remote or refspec, a refspec source that does not resolve locally,
a `--head` of an issue branch that is not a local branch, or a quoted / expanded
directory (`cd "$dir"`, `git -C "$dir"`). Write those out plainly. Residual gap: a
raw SHA that is only an *ancestor* of an issue branch (not any branch tip) is not
recognised. Quotes inside `gh pr create --title "..."` are fine. The hook only reads the stamp, it contains
no review logic. A deny message names the next step (`/youtrack-task pr`, or
`pr --no-review` to waive).

## Language

Same contract as `SKILL.md`: reviewers and fixers are told that git artifacts are
English; anything written to YouTrack follows the issue's language.
