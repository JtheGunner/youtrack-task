# What the reviewer may run, and when it is blocked

Detail of the review gate (`reference/review.md`, step 3 and 4). Bound by the
**Guardrails** in `SKILL.md`. The hook behind it is `hooks/guard-subagent`; the
config key is `reviewer_commands`.

## What the reviewer may run

The allowlist in `hooks/guard-subagent` is assembled from three layers; the
reviewer stays read-only whichever one allowed a command.

| Layer | Source | Use it for |
| --- | --- | --- |
| 1 | built-in patterns: common test, build and lint runners (`npm test`, `pytest`, `go test`, `go build ./...`, `swift test`, `golangci-lint run` without `--fix`, `scripts/*test*`, …) | the usual toolchains |
| 2 | `reviewer_commands` in the user config (resolved by `<skill-dir>/scripts/read-config`) | commands only this machine needs |
| 3 | `.youtrack-task/reviewer-commands` **as committed on the base branch**: one command per line, `#` starts a full-line comment | commands the whole team's reviewer needs, e.g. `ddev exec vendor/bin/pest` |

Layers 2 and 3 match **exactly**: the whole command, word for word, no regex and no
prefix, so `make verify` does not allow `make verify-all`. Redirections, heredocs,
`;`, `&&` and `|` stay rejected, and so do the path-traversal and write-option
rules. The repo file is read with `git show <base>:.youtrack-task/reviewer-commands`
and never from the working tree: a branch cannot add commands for its own review,
a change to the list takes effect once it is merged into the base branch. The
path is fixed and not configurable. Without the file (or without a repo) only layers
1 and 2 apply.

## Blocked by the guard

A command the hook rejects carries the marker `[blocked-by-guard]`. The reviewer
reports it as `blocked-by-guard` under `BLOCKED:` and does not turn it into a
finding. For `BLOCKED_BY_GUARD` the gate:

- does **not** run a fix round and does **not** count it against `rounds`; there
  is no code to fix;
- writes **no** stamp;
- returns `BLOCKED` with the rejected commands to the caller, who tells the user
  the options: add the exact command to `.youtrack-task/reviewer-commands` (merge it
  into the base branch first), add it to `reviewer_commands` in the user config, or
  `pr --no-review` as a recorded waiver. After the user allowed it, the gate runs
  again with a new reviewer.

In `all` an issue with a `BLOCKED` result goes to the user as *needs-human*, with
the commands in the report.
