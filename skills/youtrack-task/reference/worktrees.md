# Worktrees — running tasks in parallel

Instead of `git switch`-ing the current checkout (which clobbers another task's
work in progress), a pickup can create the branch in its own **git worktree**, so
several `/youtrack-task <id>` runs — in different terminals / sessions — each get
an isolated working directory.

## When a worktree is used

Config `worktree`:

| value | behaviour |
| --- | --- |
| `auto` *(default)* | create a worktree when the current checkout is **dirty** or already on a **non-default branch**; otherwise switch in place |
| `off` | always switch in place (`git switch -c`) — the pre-0.6 behaviour |
| `always` | every pickup gets a worktree |

Flags override for one run: `--worktree` forces one, `--no-worktree` forces
in-place.

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

**Gitignore guard (required):** `git check-ignore -q <worktree_dir>` must pass.
If it doesn't, add `/<worktree_dir>/` to the repo's `.gitignore` and commit that
one change (English message, e.g. `chore: ignore .worktrees/`) before creating
anything.

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

`/youtrack-task done` — after the state change, if the issue's branch lives in a
worktree under `<worktree_dir>` and (`gh pr view <branch>` shows) its PR is merged
or gone, offer:
```bash
git worktree remove "<path>"        # never --force; if the tree is dirty, ask first
git branch -d "<branch>"            # -d only; never -D
```

`/youtrack-task worktree` sub-command:
- `list` — `git worktree list` filtered to this plugin's worktrees, each with its
  issue's current YouTrack state.
- `prune` — for every plugin worktree whose issue is `done_state` (or whose PR is
  merged), `git worktree remove` (skip dirty ones, report them) then
  `git worktree prune`.

Never `git worktree remove --force`, never `git branch -D`, never delete a
worktree with uncommitted changes without explicit confirmation.
