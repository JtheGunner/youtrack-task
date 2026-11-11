# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.16.8 — 2026-11-11

- **Refactor: one config parser.** `setup-workspace`, `sweep-worktrees`,
  `worktree-detach` and `hooks/require-review` no longer parse `config.toml` with
  their own `sed`; they call `scripts/read-config <key>`, which prints one resolved
  value (new single-key mode; unknown key → `ERROR=unknown-key`, exit 2). Before,
  a key under `[type_prefix]` was read as a top-level setting by those four
  consumers when the real key was missing, so the model and the scripts could see
  different values (for example `sweep-worktrees` deciding which directory it may
  clean). The hook still never blocks by accident: a missing or failing
  `read-config` lets the push through. Tests cover the single-key mode and, for
  each consumer, a key that exists only in a `[table]`.

## 0.16.7 — 2026-11-11

- **Docs: the reviewer-isolation claim is best effort.** `reference/review.md`,
  `SPEC.md` and `README.md` no longer say the allowlist keeps the reviewer away
  from commit messages and PR text. `git log` / `git show` are denied, but
  `git cat-file`, `git shortlog`, `git rev-list --format`, `gh pr status` and
  `gh pr diff` are allowed. They also state that running the project's tests
  executes code of the reviewed branch and lies outside the guard. The allowlist
  in `hooks/guard-subagent` is unchanged.

## 0.16.6 — 2026-11-11

- **Test: the worktree scripts are covered.** New `tests/sweep-worktrees.sh` (with
  a stub `gh` in `PATH`) and `tests/worktree-detach.sh`, and `tests/setup-workspace.sh`
  gains the cases `ERROR=dirty-tree`, `--allow-dirty`, `existing-worktree`,
  `existing-branch` and the `YOU-1` vs `YOU-12` ID-prefix collision. They check
  that a dirty worktree is kept, that a closed but unmerged branch is never force
  deleted, and that the scripts contain no `--force`, `branch -D` or `push`. The
  manual rows 8t–8ae in `tests/README.md` point to them. No change to the scripts.


## 0.16.5 — 2026-11-11

- **CI: every change is checked before merge and before release.** New workflow
  `.github/workflows/ci.yml` runs on `pull_request` and on pushes to `main`. It
  runs `tests/*.sh`, `shellcheck -S warning` on `hooks/*` and
  `skills/youtrack-task/scripts/*`, `jq empty` on every JSON file, and checks that
  `plugin.json` and `marketplace.json` (`plugins[0].version`) carry the same
  version. `release-package.yml` now depends on that job and compares the tag
  with **both** manifests. No change to the plugin itself.

## 0.16.4 — 2026-11-11

- **Test: `tests/read-config.sh` covers every config key.** The ten keys that had
  no assertion (`in_progress_state`, `testing_state`, `done_state`,
  `local_plan_copy`, `default_new_type`, `review_before_pr`, `review_gate_hook`,
  `worktree_dir`, `worktree_link`, `batch_max_parallel`) are now tested with
  their default and a set value, including values with spaces, a bare value with a
  trailing comment, a multi-entry list with an inline comment, and a same-named
  key in a `[table]` that must not leak. No change to `read-config` itself.

## 0.16.3 — 2026-11-11

- **Chore: ShellCheck is clean on every hook and script.** `shellcheck -S warning`
  (and `-S style`) reports nothing on `hooks/*` (without `hooks.json`) and
  `skills/youtrack-task/scripts/*`. Empty-string assignments use `VAR=''`
  (SC1007), the `A && ! B || C` test in `guard-subagent` is an explicit `if`
  (SC2015), and intentional patterns carry a
  `# shellcheck disable=… # reason` comment. No behaviour change.
- **`setup-workspace` passes `worktree_dir` to awk with `-v`** instead of splicing
  it into the awk program text. Covered by two new cases in
  `tests/setup-workspace.sh` (create and resume with a custom `worktree_dir`).

## 0.16.2 — 2026-11-11

- **Fix: `setup-workspace` silently branched from HEAD when the base had no
  `origin/` ref.** The three creation paths (in place, linked worktree, new
  worktree) ended in `… "origin/$BASE" || … <no start point>`, so a base that
  existed only locally produced a branch at the current HEAD while the output
  still said `BASE=<base>`; review diff and PR base then disagreed with the
  branch. The start point is now resolved once — `origin/<base>`, else the local
  `<base>`, else `ERROR=cannot-resolve-base` (exit 2, nothing created) — and used
  by all three paths. Covered by `tests/setup-workspace.sh`.

## 0.16.1 — 2026-11-08

- **Fix: `/youtrack-task all` without IDs found nothing.** Three causes, all in how
  the candidates were gathered, plus one in how the result was reported:
  - `batch_query` was project-agnostic, so the first 20 results were tickets of
    other projects. `all` now adds the current repo's `project: {KEY}` (resolved
    with "Resolving a project") unless the query has its own `project:` clause.
  - The default query hardcoded `State: Open`, which skips projects whose initial
    state has another name (`Submitted`). The default is now
    `for: me #Unresolved sort by: updated desc`; only issues already in
    `in_progress_state`, `testing_state` or `done_state` are dropped, and the state
    ladder in `writeback.md` counts every other unresolved state as position 0.
  - `search_issues` returns 20 issues per call and was read once. `all` now pages
    with `offset` until a page has fewer than 20 items.
  - The model filtered candidates in its head and ended with a prose question
    instead of the triage table. Every candidate now gets a verdict in the table;
    with no *ready* row the run prints the table and stops without asking.
  Existing configs that set `batch_query` explicitly are unaffected apart from the
  added project clause. Covered by `tests/read-config.sh` and manual tests 73-76.

## 0.16.0 — 2026-11-07

- **New: `confirm_pr` config key and `--confirm-pr` / `--no-confirm-pr` flags for
  `pr`.** `/youtrack-task pr` always asked "push and open a PR?" after showing the
  commits and diffstat. With `confirm_pr = false` in `config.toml`, or
  `--no-confirm-pr` for one run, `pr` still shows them but pushes and opens the PR
  without the question; `--confirm-pr` asks again when the config says `false`.
  Default is `true`, so nothing changes unless you opt in. The setting is a
  standing authorization for that push and PR only: the review gate, the
  default-branch / commits-ahead / dirty-tree checks and the `--no-review`
  confirmation are unaffected, and so is the single batch confirmation in `all`.
  Resolved by `scripts/read-config` (`CONFIRM_PR`); the decision in `pr` step 3 is a
  table over the resolved value. Covered by `tests/read-config.sh` and manual
  tests 66-72.

## 0.15.4 — 2026-11-07

- **Fix: the `ticket-reviewer` could not run Gradle tests.** The reviewer allowlist
  in `hooks/guard-subagent` accepted only `gradle test` / `./gradlew test`, so
  `./gradlew :feature:play:testDebugUnitTest`, `./gradlew testDebugUnitTest lint`
  or `./gradlew --no-daemon test` were blocked and Android / multi-module projects
  could not be reviewed. Gradle is now allowed for check tasks only, matched by
  exact name (`test`, `check`, `lint`, `detekt`, `ktlintCheck`, `spotlessCheck`,
  `lint(Debug|Release|Vital|VitalRelease)`, `test<Variant>UnitTest`), optionally
  with a project path, because Gradle expands camelCase abbreviations (`lintF`
  would run `lintFix`). Options are a fixed harmless set (`--no-daemon`,
  `--offline`, `--tests <pattern>`, `-x <task>`, …). Building, publishing or
  cleaning tasks, tasks that write sources or baselines, `-D` / `-P`, options that
  load other scripts or directories (`-I`, `-b`, `-c`, `-g`, `-p`) and glob
  characters in option values stay denied; a trailing backslash
  (line continuation) is denied for the reviewer, and `GRADLE_*`, `JAVA_*`, `JDK_*`,
  `ANDROID_*`, `KOTLIN_*`, `_JAVA_OPTIONS`, `ORG_GRADLE_*` and `TMPDIR` cannot be set in a
  subagent command. Covered by
  `tests/guard-subagent.sh`.

## 0.15.3 — 2026-11-07

- **Fix: `confirm_branch_name = false` was not applied reliably.** The skill only
  said "read the config if present", no step did, and a session that never read
  the file fell back to the default `true` and asked anyway, sometimes bundling
  the name with "OK to move the issue and post the comment?". New
  `scripts/read-config` resolves every key with its default; step 0 of every
  invocation runs it, and config values are taken from its output only (without
  `scripts/`, from reading the file). The pickup is authorized by the invocation,
  so no extra go-ahead gate is added. Covered by `tests/read-config.sh`.

## 0.15.2 — 2026-11-07

- **Docs: project resolution reference.** New `reference/projects.md` documents the
  20-item cap of `find_projects` and the paging loop behind "Resolving a project".
  No behaviour change.

## 0.15.1 — 2026-11-07

- **Fix: existing projects reported as missing.** The repo → YouTrack project
  lookup could answer *"there is no project named …"* for a project that exists,
  because `find_projects` returns only 20 projects per page and the skill looked
  at the first page only. A single "Resolving a project" procedure now searches by
  repo name first, then pages through all projects, verifies the hit with
  `get_project`, and only then may report a missing project. Used by the
  bare-number pickup, the repo sanity check and `new`.

## 0.15.0 — 2026-11-06

- **Skip the branch-name question.** New config key `confirm_branch_name`
  (default `true`) and flags `--confirm-branch` / `--no-confirm-branch` for the
  primary flow. With `false` / `--no-confirm-branch` the computed branch name is
  accepted automatically and shown as one line; the flag wins over the config.
  Other questions (`dirty-tree`, existing branch, project mismatch) are unchanged,
  and `all` never asked for branch names.

## 0.14.0 — 2026-11-06

- **Agensi / non-Claude-Code agents:** documented that the review gate runs in its
  weaker `independent=no` mode there, because agents and hooks are not part of
  the skill folder.
- **One review gate for every task.** The independent review that only `all`
  had now applies to the primary flow and `pr` too. It is defined once in the new
  `reference/review.md`: a fresh `ticket-reviewer` subagent per review with a
  minimal briefing (issue, requirements, checkout path, base, SHA — never the
  implementer's report), fix rounds, and a verdict bound to the exact commit.
  `all` now just schedules this gate per issue instead of carrying its own copy.
- **`scripts/review-stamp`** records and checks "PASS on this exact commit"
  (`write` / `check`; `PASS`, `STALE`, `MISSING`, `FAILED`) in the git directory:
  local, shared by worktrees, never pushed. Covered by `tests/review-stamp.sh`.
- **`pr` checks the review** before offering a push: `PASS` proceeds, `STALE` /
  `MISSING` runs the gate, `FAILED` stops. `--no-review` (new on `pr`) and
  `review_before_pr = "never"` are the only ways past it and label the PR and the
  issue comment `Review: skipped`.
- **Behaviour change:** `review_before_pr` now defaults to `always` (it was `auto`,
  review only on the architectural path). `auto` is accepted as a synonym of
  `always`. The primary flow no longer uses `superpowers:requesting-code-review`;
  its reviewer shared the implementer's context. Review findings are still applied
  with `superpowers:receiving-code-review`.
- **Config:** new `review_rounds` (default 2); `batch_review_rounds` stays as an
  alias. `--review` is accepted and does nothing.
- Issues without acceptance criteria are reviewed against their goal and the
  plan items the user approved.
- **Optional enforcement hook** `hooks/require-review` (`review_gate_hook = "on"`,
  default `off`): in the main session it blocks `git push` and `gh pr create` of
  an issue branch unless the exact commit has a `PASS` (or a recorded waiver)
  stamp, so the gate also holds for a plain push or `/ship`. It only reads the
  stamp; best effort, fails open without `jq`. It checks refspecs by source and
  destination, `--all` / `--mirror` / `--branches` per issue branch, and denies
  pushes whose quoted, escaped, expanded or wildcard arguments it cannot
  resolve, and gates the matching refspec `:` and a commit pushed by raw SHA when
  it is an issue branch's tip. Covered by
  `tests/require-review.sh`.
- `review-stamp` gained `check --sha <SHA>` (ask about one exact commit) and the
  `SKIPPED` verdict, the recorded waiver behind `pr --no-review`.

## 0.13.0 — 2026-11-06

- **`/youtrack-task all` — many issues, one command.** Triage the candidates
  (`ready` / `needs-human` / `blocked`), then work them in parallel: one
  `ticket-worker` agent per issue in its own worktree, and a fresh
  `ticket-reviewer` per result that sees only the issue and the diff — never the
  worker's report. Failed reviews loop back for up to `batch_review_rounds`
  rounds. PRs are opened after a single confirmation for the whole list.
- **`--auto-merge`** (opt-in per run): the run may merge the PRs it created when
  the head commit is the one the reviewer passed, at least one required check
  exists and is green, the PR is `CLEAN` and shares no file with another issue
  of the run — plain `--merge --match-head-commit`, no admin bypass, no
  remote-branch deletion. Refused with `--no-review` or without subagent
  support. Without the flag nothing is merged.
- **Workers never push.** They commit locally; the main session pushes a branch
  only after an independent `PASS` and the single PR confirmation, so nothing
  unreviewed reaches the remote. Guardrails in `SKILL.md` updated accordingly.
- New plugin agents `agents/ticket-worker.md`, `agents/ticket-reviewer.md`, a
  `PreToolUse` Bash hook `hooks/guard-subagent` that confines them (needs `jq`;
  workers: no push / merge / network tools / hook bypass; reviewer: an allowlist
  of read-only commands and test runners),
  and its test script `tests/guard-subagent.sh`.
- New config keys `batch_query`, `batch_max_parallel`, `batch_skip_tags`,
  `batch_review_rounds`; contract in `reference/batch.md`.

## 0.12.0 — 2026-10-26

- **No more unassigned issues, even without `/youtrack-task new`.** Issues created
  directly in conversation ("leg die Issues an") never loaded the skill, so no
  Assignee was set. A plugin `PreToolUse` hook (`hooks/require-assignee`) now
  rejects a YouTrack `create_issue` without an Assignee; Claude retries with the
  token owner (or `Unassigned` if the user asked for that). The rejection also
  reminds Claude to write title and description in the user's language.
- `SKILL.md`: Assignee guardrail ("creator unless told otherwise") for every
  `create_issue`, and a broader skill description (create / file / log, German
  phrasing) so the skill loads for such requests.

## 0.11.0 — 2026-10-26

- **Language rule is now one explicit contract.** New "Language" section in
  `SKILL.md`: git artifacts are always English; YouTrack text (title, description,
  every comment) follows the user's language, resolved as explicit instruction →
  input language → existing issue text → session language. Global or project
  "English everywhere" rules no longer leak into YouTrack text.
- `new` confirmation shows a `Language:` line; changing it regenerates title and
  description. Field mode generates the missing field in the language of the one
  given. Every YouTrack write is re-checked against the resolved language.
- README troubleshooting: stale plugin (no marketplace auto-update) as the usual
  reason for English output, and how to update.

## 0.10.1 — 2026-10-24

- **Fix: `new` free-text mode now writes the issue title in the input's language**
  (it was always English while the description followed the input). A given
  `--title` is used verbatim. Git artifacts stay English; the guardrail now
  states that only they are translated.

## 0.10.0 — 2026-10-13

- **Portable skill.** `SKILL.md` no longer assumes Claude Code: YouTrack MCP tools
  are matched by base name (`get_issue`, …) with the `mcp__youtrack__` prefix
  documented as the Claude Code spelling, and the "not connected" message covers
  other agents (Cursor, Copilot).
- **Degraded mode without `scripts/`.** If the agent loads the skill without
  writing the bundled scripts to disk, it falls back to plain in-place git — no
  worktrees, nothing forced.
- Skill-level `README.md` (requirements, per-agent MCP setup, what each script
  touches) and `examples/` (pickup, new, pr).
- `tools/package-agensi` builds a marketplace-ready ZIP (one top-level folder,
  text files only, no symlinks) into `dist/agensi/`.
- Project logo (`assets/logo.png`) in the README header.

## 0.9.0 — 2026-09-23

- `/youtrack-task new` now always sets an **Assignee**: the owner of the API
  token by default (`get_current_user`). New `--assignee <login|email>` — or an
  explicit "assign to …" / "für …" in the free text — assigns someone else. A
  user that doesn't exist (`find_user`) falls back to the token owner, flagged
  at the confirm step instead of stopping. If `create_issue` doesn't set the
  field, `change_issue_assignee` follows up; a project without an `Assignee`
  field gets an unassigned issue and a note in the report.

## 0.8.1 — 2026-09-07

- Docs: README brought up to date with everything since 0.6.0 — the `scripts/`
  helpers, `pr` auto-sweeping merged worktrees, `worktree take` / `remove`, the
  worktree config keys, and two new troubleshooting rows. Added a repo `CLAUDE.md`
  with a change checklist so README updates stop getting missed.

## 0.8.0 — 2026-09-07

- `/youtrack-task worktree take <ID>` and `worktree remove <ID>`: free an issue's
  branch that's still checked out in a worktree. `take` removes that worktree
  (branch kept) and `git switch`es to the branch in your current checkout;
  `remove` just drops the worktree. Refuses a dirty worktree; skips the switch if
  the current checkout has tracked changes. New `scripts/worktree-detach`.

## 0.7.0 — 2026-09-07

- **Root fix for "no worktree was used" and "worktrees never cleaned up":** the
  worktree decision and cleanup were long prose in SKILL.md that the model had to
  execute faithfully every run — it regularly skipped it and did a plain
  `git switch -c`, and nothing swept worktrees after `pr`. Moved both to bundled
  scripts the skill now just *runs*:
  - `scripts/setup-workspace` — step 4: reads `config` `worktree`, checks dirty
    (tracked only) / branch / existing worktree, then resumes, switches in place,
    or creates + bootstraps a worktree; prints `MODE=`/`BRANCH=`/`DIR=`/… The
    model acts on that instead of improvising. `--allow-dirty` carries a dirty
    tree onto the new branch when the user chooses; `ERROR=dirty-tree` otherwise.
  - `scripts/sweep-worktrees` — removes clean worktrees whose PR is merged/closed
    (`git worktree remove` + `git branch -d` + `git worktree prune`); dirty ones
    and open PRs are listed, not touched. `pr` runs it (excluding the just-opened
    branch) so worktrees stop piling up; `done` and `worktree prune` run it too.
  - Merged step 3b (resume) into the script — a resume can no longer bypass the
    worktree decision, whatever the issue's state.

## 0.6.3 — 2026-09-07

- Fix: re-running `/youtrack-task <id>` on an issue that's already In Progress had
  no defined behaviour, so the model improvised a "re-implement" path that
  skipped step 4 entirely — no worktree decision, no base resolution, no branch
  name confirmation. Real symptom: with a prior worktree already open for another
  task, a second pickup landed as a plain in-place branch off main instead of its
  own worktree. New **step 3b (resume check)**: on an already-In-Progress issue,
  find the existing work first — enter its worktree, or switch/`git worktree add`
  its local branch, or (branch gone) run step 4 **in full, worktree decision
  included** and skip only the state change. A resume never bypasses the
  worktree-vs-in-place decision; an existing plan comment is reused, not
  regenerated.

## 0.6.2 — 2026-09-06

- Worktree fixes from the 8n–8u dry run:
  - Ignore guard uses `.git/info/exclude` (per-repo, untracked) instead of a
    `.gitignore` commit — no surprise `chore: ignore …` on the user's branch,
    works when the tree is dirty.
  - `worktree = auto` also triggers when a plugin worktree already exists, and
    the docs now state plainly that parallel work wants `worktree = always` /
    `--worktree` (under `auto` the first pickup in a clean repo is in-place).
  - Concurrency: a racing `git worktree add` retries once on `index.lock`.
  - A dirty worktree is never removed and never prompted about — reported only
    (aligns `done` cleanup and `worktree prune` with the guardrail).
  - `worktree prune` now also `git branch -d`s the merged branch, matching
    `done` cleanup.

## 0.6.1 — 2026-09-06

- Fix: on the superpowers architectural path, `writing-plans` already writes a
  local plan document — step 7's `local_plan_copy` no longer writes a second
  overlapping `docs/plans/<ID>.md`; it names the existing file instead.
- Docs: `new` confirm step spells out that editing one field doesn't regenerate
  the others; test row 8i narrowed to the bounded case.

## 0.6.0 — 2026-09-06

- Isolated **git worktrees** for parallel tasks. `worktree = auto` (default): a
  pickup drops into `<repo>/.worktrees/<ID>-<slug>` on its own branch when the
  current checkout is dirty or on a non-default branch, so several pickups in
  separate terminals don't collide. Bootstrap: copy-on-write clone of
  `node_modules` / `vendor` (`+ storage` for Laravel) via `cp -c` on APFS,
  symlinked `.env`, optional `.claude/youtrack-worktree-setup.sh`. New
  `--worktree` / `--no-worktree` flags; new config `worktree`, `worktree_dir`,
  `worktree_clone`, `worktree_link`. New `/youtrack-task worktree list|prune`;
  `done` offers to remove a merged task's worktree. Never `--force` /
  `git branch -D` / touches a dirty worktree. `reference/worktrees.md`.

## 0.5.0 — 2026-09-06

- Git artifacts are always English now — branch slugs, commit messages, PR title
  and body — regardless of the issue's language; the skill translates the
  summary. YouTrack comments still follow the issue's language. Fixes non-English
  text leaking into merge commits via the PR title.

## 0.4.2 — 2026-09-06

- Docs: link the changelog from the README; Keep a Changelog / SemVer preamble.

## 0.4.1 — 2026-09-06

- Docs: README rewritten intro (create / pick up / ship), `--checkpoints` /
  `--review` / `--no-review` flags documented, install command fixed to
  `youtrack-task@youtrack-task`. SPEC brought in line with shipped behaviour
  (issue-ID resolution, 40-char slug + type-word strip, guardrails).

## 0.4.0 — 2026-09-06

- Route planning + implementation through the `superpowers` plugin when it is
  installed (`use_superpowers = auto`): `brainstorming` /
  `systematic-debugging` → `writing-plans` for the plan;
  `subagent-driven-development` / `executing-plans` + `test-driven-development` +
  `requesting-code-review` + `verification-before-completion` for the build. The
  issue description's sections map onto each skill's inputs. Unchanged fallback
  when superpowers is absent.
- New flags `--checkpoints`, `--review`, `--no-review`.
- New config `use_superpowers`, `review_before_pr`.
- `reference/superpowers.md`.

## 0.3.0 — 2026-09-06

- `/youtrack-task new "<free text>"` — generate the title and a structured
  description (Summary / Context / Goal / Acceptance criteria / Scope /
  Technical notes / Open questions) from one blob of text. `reference/issue-template.md`.

## 0.2.0 — 2026-09-06

- `/youtrack-task new` — create an issue (project / title / description required,
  type inferred + confirmed, priority optional).

## 0.1.0 — 2026-09-06

- Initial plugin: `/youtrack-task [ID]` pickup flow (fetch → branch → In Progress
  → plan → write-back), sub-commands `comment` / `log` / `pr` / `link` /
  `testing` / `done`, bundled YouTrack MCP server, guardrails.
