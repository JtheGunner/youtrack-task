#!/usr/bin/env bash
# Cases for skills/youtrack-task/scripts/worktree-detach.
# Usage: tests/worktree-detach.sh [path-to-script]
# Builds throwaway git repos under a temp dir.
set -u
script=${1:-$(cd "$(dirname "$0")/.." && pwd)/skills/youtrack-task/scripts/worktree-detach}
fail=0
tmp=$(cd "$(mktemp -d)" && pwd -P)   # physical path: git reports resolved paths
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export YOUTRACK_TASK_CONFIG=$tmp/no-config.toml   # never read the real user config

run() { local d=$1; shift; out=$(cd "$d" && bash "$script" "$@" 2>&1); rc=$?; }
has() { printf '%s\n' "$out" | grep -qxF -- "$1"; }
hasre() { printf '%s\n' "$out" | grep -qE -- "$1"; }
check() {
  if [ "$2" = 0 ]; then echo "ok   $1"; else
    echo "FAIL $1 (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/     | /'; fail=1
  fi
}
branch_exists() { git -C "$1" show-ref --verify -q "refs/heads/$2"; }
mk_repo() { git init -q -b main "$1"; git -C "$1" commit -q --allow-empty -m "first"; }
mk_wt() { git -C "$1" worktree add -q -b "$2" "$1/.worktrees/$3" main; }

# --- 1. --id removes the worktree and keeps the branch --------------------------
r=$tmp/basic; mk_repo "$r"; mk_wt "$r" fix/T-1-a T-1-a
run "$r" --id T-1
[ "$rc" = 0 ] && hasre '^REMOVED=.*/\.worktrees/T-1-a$' && has "BRANCH=fix/T-1-a" \
  && [ ! -e "$r/.worktrees/T-1-a" ] && branch_exists "$r" fix/T-1-a && ! printf '%s\n' "$out" | grep -q '^SWITCHED='
check "--id: worktree removed, branch kept, no switch" $?

# --- 2. dirty worktree is refused ----------------------------------------------------
r=$tmp/dirty; mk_repo "$r"; mk_wt "$r" fix/T-2-a T-2-a
echo x > "$r/.worktrees/T-2-a/untracked"
run "$r" --id T-2
[ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q '^ERROR=dirty' && [ -e "$r/.worktrees/T-2-a/untracked" ] \
  && branch_exists "$r" fix/T-2-a
check "dirty worktree: ERROR=dirty, nothing removed" $?

# --- 3. --switch with a clean main checkout -----------------------------------------------
r=$tmp/switch; mk_repo "$r"; mk_wt "$r" fix/T-3-a T-3-a
run "$r" --id T-3 --switch
[ "$rc" = 0 ] && has "SWITCHED=fix/T-3-a" && [ "$(git -C "$r" branch --show-current)" = fix/T-3-a ] \
  && [ ! -e "$r/.worktrees/T-3-a" ]
check "--switch: worktree removed and branch checked out here" $?

# --- 4. --switch with tracked changes in the current checkout: no switch ------------------
r=$tmp/switch-dirty; mk_repo "$r"
echo a > "$r/f"; git -C "$r" add f; git -C "$r" commit -q -m f; mk_wt "$r" fix/T-4-a T-4-a
echo b >> "$r/f"
run "$r" --id T-4 --switch
[ "$rc" = 0 ] && hasre '^REMOVED=' && printf '%s\n' "$out" | grep -q '^NOTE=not switching' \
  && ! printf '%s\n' "$out" | grep -q '^SWITCHED=' && [ "$(git -C "$r" branch --show-current)" = main ] \
  && grep -q '^b$' "$r/f" && branch_exists "$r" fix/T-4-a
check "--switch with tracked changes here: removed, switch skipped with NOTE, edit intact" $?

# --- 5. ID prefix collision: T-1 must not match T-12's worktree -------------------------
r=$tmp/collide; mk_repo "$r"; mk_wt "$r" fix/T-12-a T-12-a
run "$r" --id T-1
[ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q '^ERROR=no-worktree' && [ -d "$r/.worktrees/T-12-a" ]
check "ID prefix collision: T-1 does not detach T-12's worktree" $?
mk_wt "$r" fix/T-1-b T-1-b
run "$r" --id T-1
[ "$rc" = 0 ] && hasre '^REMOVED=.*/T-1-b$' && [ -d "$r/.worktrees/T-12-a" ]
check "ID prefix collision: T-1 detaches only its own worktree" $?

# --- 6. no worktree for the ID -----------------------------------------------------------
r=$tmp/none; mk_repo "$r"
run "$r" --id T-9
[ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q '^ERROR=no-worktree'
check "no worktree for the ID: ERROR=no-worktree" $?

# --- 7. --dir targets one worktree directly ------------------------------------------------
r=$tmp/bydir; mk_repo "$r"; mk_wt "$r" fix/T-7-a T-7-a
run "$r" --dir "$r/.worktrees/T-7-a"
[ "$rc" = 0 ] && hasre '^REMOVED=.*/T-7-a$' && branch_exists "$r" fix/T-7-a
check "--dir: that worktree is removed, branch kept" $?

# --- 8. the main checkout is never removed ------------------------------------------------
run "$r" --dir "$r"
[ "$rc" = 2 ] && has "ERROR=that-is-the-main-checkout" && [ -d "$r/.git" ]
check "--dir pointing at the main checkout: refused" $?

# --- 9. argument and environment errors ------------------------------------------------------
run "$r"; [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q '^ERROR=need --id or --dir'
check "no --id/--dir: ERROR, exit 2" $?
run "$r" --bogus; [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q '^ERROR=unknown arg'
check "unknown argument: ERROR, exit 2" $?
run "$tmp"; [ "$rc" = 2 ] && has "ERROR=not-in-git-repo"
check "outside a git repo: ERROR=not-in-git-repo" $?

# --- 9b. config keys inside a [table] are ignored ----------------------------------
r=$tmp/tablekey; mk_repo "$r"; mk_wt "$r" fix/T-9-a T-9-a
printf '[type_prefix]\nworktree_dir = ".wt"\n' > "$tmp/table.toml"
YOUTRACK_TASK_CONFIG=$tmp/table.toml run "$r" --id T-9
[ "$rc" = 0 ] && hasre '^REMOVED=.*/\.worktrees/T-9-a$' && [ ! -e "$r/.worktrees/T-9-a" ]
check "[table] worktree_dir is ignored: worktree in the default dir is found" $?

# --- 10. safety by construction: no --force, no branch deletion ------------------------------
out=$(grep -vE '^[[:space:]]*#' "$script" | grep -nE -- '--force|branch +-[dD]|push'); [ -z "$out" ]; rc=$?
check "script never uses --force, branch deletion or push" $rc

[ "$fail" = 0 ] && echo "ALL OK"
exit "$fail"
