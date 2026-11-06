# Design: one review gate for every task

## Problem

Review is only guaranteed in `/youtrack-task all`. The primary flow reviews on the
architectural path only (`review_before_pr = auto`), and does so through
`superpowers:requesting-code-review`, whose reviewer shares the implementer's
session context. `pr` has no review check, so an unreviewed branch can be pushed.
The independent-review contract (fresh `ticket-reviewer`, no worker claims, exact
reviewed SHA) lives only in `reference/batch.md`.

## Goals

- **a)** Every task with code changes is reviewed before it can be pushed or opened as a PR.
- **b)** Every review runs in a fresh subagent that never sees the implementer's reasoning.
- **c)** The review procedure is defined **once** and called by the primary flow, `pr` and `all`.

## Non-goals

- No change to what the reviewer judges (`agents/ticket-reviewer.md` rules stay).
- No server-side enforcement. Branch protection remains the real boundary.
- The user's own `/ship` is outside the plugin; it is only covered by the optional hook (phase 3).

## Design

### 1. `reference/review.md` — the single source

Moves out of `batch.md` §4 and generalises it. Parameters, no flow-specific text:

| Input | Meaning |
| --- | --- |
| `issue` | ID, title, description with acceptance criteria (untrusted data) |
| `dir` | absolute path of the checkout to review (worktree or main checkout) |
| `base` | base branch |
| `fixer` | who applies findings: `main-session` (primary flow) or `ticket-worker` (`all`) |
| `rounds` | max fix rounds (`review_rounds`) |

Procedure (verbatim today's batch.md §4 rules, now generic):

1. Require a clean tree (`git -C <dir> status --porcelain` empty). Dirty tree: the
   caller commits first (primary flow: offer to commit on the feature branch) or,
   for `all`, it is `CHANGES_REQUESTED` input.
2. Record `SHA_review = git -C <dir> rev-parse HEAD`.
3. Dispatch a **new** `ticket-reviewer` with: issue ID + title, description with
   acceptance criteria, `dir`, `base`, `SHA_review`. Never the implementer's report,
   plan comments, commit-message claims or conclusions.
4. Verdict handling: `PASS` only if every criterion is `met`; `unverifiable`, no
   clear verdict, or any finding that blocks a merge is `CHANGES_REQUESTED`.
5. `CHANGES_REQUESTED`: the `fixer` applies the `FINDINGS`, commits, and a **new**
   reviewer runs without the earlier findings. At most `rounds` fix rounds, so at
   most `rounds + 1` reviews. A last fix is always re-reviewed.
6. `PASS` is valid only while `HEAD == SHA_review` and the tree is clean. Write the stamp.
7. Still failing after the last round: stop, report open findings, no stamp. Never loop silently.

No subagent support: a same-session re-read is allowed but stamped
`independent=no`. It never satisfies `--auto-merge`, and `pr` asks for explicit
confirmation to proceed with it.

### 2. Review stamp — the durable "PASS on this SHA"

`pr` and `all` need to know a review happened, across sessions and commands.

- Location: `$(git rev-parse --git-common-dir)/youtrack-task/reviews/<ID>` — local,
  shared by worktrees, never pushed, not in the working tree.
- Content (`KEY=VALUE`): `SHA`, `VERDICT`, `INDEPENDENT`, `ROUND`, `DATE`.
- New `scripts/review-stamp` (bash, no extension, `KEY=VALUE` output, safe by
  construction):
  - `review-stamp write --id <ID> --sha <SHA> --verdict PASS|FAILED --independent yes|no`
  - `review-stamp check --id <ID> [--dir <path>]` prints
    `REVIEW=PASS|STALE|MISSING|FAILED`, `SHA=`, `HEAD=`, `INDEPENDENT=`.
    `STALE` = stamped SHA differs from the current HEAD.
- Contract documented in `reference/review.md` (same rule as `worktrees.md` for its scripts).

### 3. Callers become thin

| Caller | Change |
| --- | --- |
| Primary flow, step 8 | Both paths (bounded and architectural) call the gate after implementation, `fixer = main-session`. `superpowers:requesting-code-review` is no longer used; `superpowers:receiving-code-review` still guides how findings are applied. `verification-before-completion` stays and runs before the gate. |
| `pr` | New check after the existing ones: `review-stamp check`. `PASS` + `INDEPENDENT=yes` proceeds. `STALE` / `MISSING` runs the gate (needs a clean tree), then continues. `FAILED` stops. `--no-review` skips only after an explicit confirmation and puts an **Unreviewed** line into the PR body and the YouTrack comment. |
| `all` | §4 collapses to "run the gate with `fixer = ticket-worker`, `rounds = review_rounds`". §6 step 1 and §7's SHA condition use `review-stamp check` instead of an in-memory `SHA_review`. Everything else in batch.md (triage, workers, report, merge conditions) is unchanged. |

### 4. Config and flags

- `review_before_pr`: default `auto` → `always`. `auto` is accepted and treated as
  `always` (documented). `never` stays as the standing opt-out.
- `review_rounds` (default `2`) is the generic key; `batch_review_rounds` stays as an alias.
- `--review` becomes a no-op alias; `--no-review` stays, and on `pr` requires confirmation.

### 5. Agent text

`agents/ticket-reviewer.md` and `ticket-worker.md` drop "batch flow" wording from
descriptions. The briefing says `dir` instead of "worktree". `guard-subagent` needs
no change (it keys on agent name, and the reviewer allowlist is unchanged).

### 6. Optional enforcement (phase 3)

A `PreToolUse` Bash hook `hooks/require-review` denies `gh pr create` and `git push`
of an issue branch in the **main session** unless `review-stamp check` is `PASS`
for the current HEAD. This makes (a) harness-enforced instead of prose-enforced and
also covers `/ship`. Cost: it must parse `git push <sha>:refs/heads/<branch>` from
`all`, and it blocks manual pushes on issue branches. Ship it behind a config key
(`review_gate_hook`, default `off`) and decide after phases 1-2.

## Phases

1. `reference/review.md` + `scripts/review-stamp` + `tests/review-stamp.sh`.
2. Wire callers: SKILL.md (flags, config, step 8, `pr`, `all`), `superpowers.md`,
   `batch.md`, agent descriptions.
3. Optional `hooks/require-review`.
4. Checklist from CLAUDE.md: README, CHANGELOG (0.14.0), SPEC, `config.example.toml`,
   `tests/README.md`, `plugin.json` + `marketplace.json`, tag.

## Risks and open points

- **Cost and latency:** every bounded fix now spawns a reviewer. Mitigation: `never` as a standing config and `--no-review` per run.
- **Uncommitted work:** the gate needs a clean tree and a fixed SHA. The primary flow must offer to commit; never commit on the default branch.
- **Issues without acceptance criteria:** the reviewer would mark everything `unverifiable`. Proposal: fall back to the description's Goal plus the user-approved plan items as requirements (approved by the user, not implementer claims). Decided.
- **Behaviour change:** default flips from `auto` to `always`, so a minor bump (0.14.0) with a prominent changelog note.
- **Agensi/skill-only packaging:** if agents or hooks are not delivered there, the gate runs in the weaker `independent=no` mode. Verify against `tools/package-agensi` before release.
- **Stamp is local state:** it can be forged or deleted by anyone with shell access. It is a workflow guard, not a security boundary.

## Tests

- `tests/review-stamp.sh`: write/check round trip, `STALE` after a new commit, `MISSING`, `FAILED`, worktree shares the stamp, refuses to write on a dirty tree or a SHA that is not HEAD.
- `tests/README.md` manual rows: bounded task gets reviewed; `pr` blocks on `STALE`; `--no-review` asks and marks the PR; `all` still reaches `PASS` through the shared gate; reviewer briefing contains no worker report.
