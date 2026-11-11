# Review gate

One procedure for every flow: the primary flow (step 8), `pr` and `all` call it;
none of them restates it. Bound by the **Guardrails** in `SKILL.md`.

> **Why a gate.** A review only counts if the reviewer judges the code without
> the implementer's story. The reviewer is therefore always a **fresh
> `ticket-reviewer` subagent** with a minimal briefing, and the result is bound to
> one exact commit (`SHA_review`) through `<skill-dir>/scripts/review-stamp`.

## When it applies

- **Every task that has commits ahead of its base** is reviewed before it can be
  pushed or opened as a PR. No commits ahead → nothing to review.
- Config `review_before_pr`: `always` (default; `auto` is accepted as a synonym) or
  `never` (standing opt-out). `--no-review` skips it for one run; `--review` is
  accepted and does nothing extra.
- `pr` treats a skipped review as an exception, not a default — see `reference/pr.md`.
  Both ways of skipping (the flag and `never`) leave the same trace: a `SKIPPED`
  stamp on the commit and the label `Review: skipped` — see "Waiver".

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
   `<skill-dir>/scripts/review-stamp write --id <ID> --sha <SHA_review> --verdict PASS --independent yes --round <n> --dir <dir>`.
   After the last round still failing: write `--verdict FAILED`, stop, and give the
   user the open findings. Never loop silently.
7. **Result for the caller:** `PASS` (stamped) or `FAILED` (open findings).

## Checking instead of re-running

`pr` and `all` do not review twice. They ask the stamp:

```
<skill-dir>/scripts/review-stamp check --id <ID> --dir <dir>
```

| `REVIEW=` | Means | Caller does |
| --- | --- | --- |
| `PASS` | reviewed on this exact HEAD, tree clean | proceed |
| `STALE` | HEAD moved or tree dirty since the stamp | run the gate again |
| `MISSING` | never reviewed (or unreadable stamp) | run the gate |
| `FAILED` | reviewed, still failing on this HEAD | stop, show the findings, no push |
| `SKIPPED` | the review was waived for this commit (`pr --no-review`, or `review_before_pr = never`) | proceed, labelled `Review: skipped` |

`INDEPENDENT=` tells whether the review ran in a subagent. Only `yes` satisfies
`all --auto-merge`; a `SKIPPED` waiver never does.

## Waiver

Skipping the review is recorded, never silent. Two ways lead there, and both end
the same way — `pr` writes
`<skill-dir>/scripts/review-stamp write --id <ID> --sha <HEAD> --verdict SKIPPED
--independent no --dir <dir>` (needs a clean tree, like any stamp) and labels the
PR and the issue comment `Review: skipped (not independently reviewed)`:

| Way | Question first? |
| --- | --- |
| `pr --no-review` (one run) | yes — explicit confirmation naming the risk; a `SKIPPED` stamp already on this commit counts as that confirmation |
| `review_before_pr = never` (standing config) | no |

The waiver belongs to that commit; a later commit is `STALE` again. The push hook
accepts a `SKIPPED` stamp; under `review_before_pr = never` it does not check at
all.

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

## Stamp and hook

The stamp is a local workflow guard, not a security boundary: server-side branch
protection is the real one. With `review_gate_hook = "on"`, `hooks/require-review`
blocks an unreviewed push or `gh pr create` and names the next step in its deny
message. The stamp contract and the hook's internals are in `SPEC.md`
(change them together with the `review-stamp` script and the `require-review` hook).
