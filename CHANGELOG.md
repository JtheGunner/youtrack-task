# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
