# Worktrees — running tasks in parallel

Instead of `git switch`-ing the current checkout (which clobbers another task's
work in progress), a pickup can create the branch in its own **git worktree**, so
several `/youtrack-task <id>` runs — in different terminals / sessions — each get
an isolated working directory.

> **This document is the behavioural contract for `scripts/setup-workspace` and
> `scripts/sweep-worktrees`.** The skill runs those scripts; it does not perform
> these steps by hand. Change the scripts and this file together.

## When a worktree is used

Config `worktree`:

| value | behaviour |
| --- | --- |
| `auto` *(default)* | worktree when the current checkout is **dirty**, already on a **non-default branch**, or **another plugin worktree already exists** for this repo; otherwise switch in place |
| `off` | always switch in place (`git switch -c`) — the pre-0.6 behaviour |
| `always` | every pickup gets a worktree |

Flags override for one run: `--worktree` forces one, `--no-worktree` forces
in-place.

**For genuinely parallel work, set `worktree = always` (or pass `--worktree`
each time).** Under `auto`, the *first* pickup in a clean, on-default repo goes
in-place by design — only once that checkout is on a task branch (or a worktree
exists) do later pickups branch off into worktrees. That asymmetry is fine for
"pick up one thing"; it is not what you want when you plan to run two tasks at
once.

**Concurrency.** Two pickups racing `git worktree add` in the same repo can hit
`fatal: Unable to create '…/index.lock'`. On that error, wait ~2 s and retry
once; if it still fails, tell the user another git/worktree operation is in
progress. The ignore guard below is idempotent, so a second concurrent pickup
that finds `<worktree_dir>` already excluded just skips it.

## Step 0 — detect existing isolation

Before creating anything:

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
```

- `GIT_DIR != GIT_COMMON` **and** `git rev-parse --show-superproject-working-tree`
  is empty → already inside a linked worktree. Do **not** nest another. Just
  create/switch the branch here (`git switch -c <branch> origin/<base>`) and
  continue.
- otherwise → a normal checkout; proceed below.

## Step 1 — locate and create

**Directory:** `<repo-root>/<worktree_dir>/<ID>-<slug>` where `worktree_dir`
defaults to `.worktrees`. The directory name is the flat `<ID>-<slug>`; the
branch keeps the full `<prefix>/<ID>-<slug>`.

**Ignore guard (required):** `git check-ignore -q <worktree_dir>` must pass so a
worktree is never accidentally committed. If it doesn't, append
`/<worktree_dir>/` to **`.git/info/exclude`** — not the tracked `.gitignore`.
`.git/info/exclude` is per-repo, untracked, and needs no commit, so this never
lands a surprise `chore: ignore …` commit on whatever branch the user happens to
be on, and it works even when the tree is dirty. (If the repo already ignores
`<worktree_dir>` via a committed `.gitignore`, leave it — the guard just passes.)

**Create:**
```bash
git fetch origin <base>
git worktree add "<repo-root>/<worktree_dir>/<ID>-<slug>" -b "<prefix>/<ID>-<slug>" "origin/<base>"
```
If the branch already exists, attach it instead: `git worktree add <path> <branch>`
(no `-b`). If the target path exists, stop and ask.

## Step 2 — bootstrap the worktree

A fresh worktree has none of the gitignored runtime dirs. Restore them from the
main checkout (`$MAIN` = `git rev-parse --git-common-dir`'s parent):

1. **Clone (isolated copy)** — `worktree_clone`, default `["node_modules",
   "vendor"]`; add `"storage"` automatically when the repo has an `artisan` file
   (Laravel). For each entry that exists in `$MAIN`:
   - macOS/APFS: `cp -c -R "$MAIN/<dir>" "<worktree>/<dir>"` (copy-on-write —
     instant, no extra disk until modified).
   - else: `cp -R` (warn it may be slow) — or skip and note it if the source is
     huge and `cp -c` is unavailable.
   Isolated so parallel tasks can't break each other's dependencies.
2. **Link (shared)** — `worktree_link`, default `[".env"]`. `ln -s
   "$MAIN/<path>" "<worktree>/<path>"` for each that exists. Shared config / DB —
   same as switching branches in place, no regression.
3. **Setup hook** — if `<repo-root>/.claude/youtrack-worktree-setup.sh` exists,
   run it with env `WORKTREE_PATH`, `MAIN_PATH`, `BRANCH`, `ISSUE_ID`. This is
   the project-specific escape hatch (per-worktree DB, asset build, etc.).
4. Do **not** blindly run `npm ci` / `composer install`. If a `worktree_clone`
   entry could not be cloned or linked, tell the user to run the install
   themselves in the worktree.

Report: the worktree path, what was cloned, what was linked, whether the hook
ran, and anything the user still needs to do (e.g. `npm run build`).

## Step 3 — enter it

- If a native tool to enter an existing worktree is available (Claude Code's
  `EnterWorktree` with a `path`), use it so the session's harness state stays
  consistent.
- Otherwise `cd` into the worktree and use absolute paths rooted there for the
  rest of the flow (plan, implement, `pr`).

Everything after this — write-back, planning, implementation, `pr` — happens in
the worktree. The other sub-commands (`comment` / `log` / `testing` / `done`)
already derive the issue ID from `git branch --show-current`, so they work
unchanged from inside any worktree.

## Cleanup

A worktree with **uncommitted changes is never removed** by the plugin — it is
reported and left for the user. No "remove anyway?" prompt.

`/youtrack-task done` — after the state change, if the issue's branch lives in a
worktree under `<worktree_dir>` and (`gh pr view <branch>` shows) its PR is merged
or gone:
- clean → offer:
  ```bash
  git worktree remove "<path>"     # never --force
  git branch -d "<branch>"         # -d only; never -D
  ```
- dirty → report the path + that it has uncommitted changes; do nothing.

`/youtrack-task worktree` sub-command:
- `list` — `git worktree list` filtered to this plugin's worktrees, each with its
  issue's current YouTrack state.
- `prune` — `scripts/sweep-worktrees`. For every plugin worktree whose PR is
  merged / closed **and** clean: `git worktree remove` → `git branch -d` (`-d`
  refuses an unmerged branch, the safe outcome) → `git worktree prune`. Dirty
  ones and open PRs are listed, not touched.
- `take <ID>` — `scripts/worktree-detach --id <ID> --switch`. The branch is
  checked out in a worktree and you want it in your current checkout: remove that
  worktree (**branch kept**), then `git switch <branch>` here (skipped if the
  current checkout has tracked changes). `ERROR=dirty` if the worktree isn't
  clean — commit / stash in it first.
- `remove <ID>` — `scripts/worktree-detach --id <ID>`. Same, without the switch.

Never `git worktree remove --force`, never `git branch -D`, never remove a
worktree that has uncommitted changes. `take` / `remove` keep the branch — only
`prune` (merged branches) deletes one, and only with `-d`.
