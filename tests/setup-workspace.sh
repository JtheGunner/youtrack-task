#!/usr/bin/env bash
# Cases for skills/youtrack-task/scripts/setup-workspace (start-point resolution).
# Usage: tests/setup-workspace.sh [path-to-script]
# Prints one line per case and exits non-zero if any case differs from the
# expectation. Builds throwaway git repos under a temp dir.
set -u
script=${1:-$(cd "$(dirname "$0")/.." && pwd)/skills/youtrack-task/scripts/setup-workspace}
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export YOUTRACK_TASK_CONFIG=$tmp/no-config.toml   # never read the real user config

# run <dir> <args...> -> sets out and rc
run() { local d=$1; shift; out=$(cd "$d" && bash "$script" "$@" 2>&1); rc=$?; }

check() { # <label> <condition-exit-code>
  if [ "$2" = 0 ]; then echo "ok   $1"; else
    echo "FAIL $1 (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/     | /'; fail=1
  fi
}

has() { printf '%s\n' "$out" | grep -qxF -- "$1"; }
tip() { git -C "$1" rev-parse "$2" 2>/dev/null; }

# mk_repo <dir> : repo on `main` with one commit, no remote
mk_repo() {
  git init -q -b main "$1"
  git -C "$1" commit -q --allow-empty -m "main: first"
}

# mk_local_base_scenario <dir> : local-only `relbase` (own commit), HEAD on `feat/other` (another commit)
mk_local_base_scenario() {
  mk_repo "$1"
  git -C "$1" branch relbase
  git -C "$1" switch -q relbase && git -C "$1" commit -q --allow-empty -m "relbase: commit"
  git -C "$1" switch -q -c feat/other main && git -C "$1" commit -q --allow-empty -m "other: commit"
}

# --- 1. in-place: local base without an origin ref, HEAD on another branch ----
r=$tmp/inplace; mk_local_base_scenario "$r"
run "$r" --id T-1 --slug s --prefix fix --base relbase --mode inplace
[ "$rc" = 0 ] && has "BASE=relbase" && [ "$(tip "$r" HEAD)" = "$(tip "$r" relbase)" ]
check "in-place: branch starts at the local base, not at HEAD" $?

# --- 2. new worktree: same situation ------------------------------------------
r=$tmp/newwt; mk_local_base_scenario "$r"
run "$r" --id T-2 --slug s --prefix fix --base relbase --mode worktree
[ "$rc" = 0 ] && has "BASE=relbase" && [ "$(tip "$r" fix/T-2-s)" = "$(tip "$r" relbase)" ]
check "new worktree: branch starts at the local base, not at HEAD" $?

# --- 3. linked worktree: script runs inside a linked worktree ----------------
r=$tmp/linked; mk_local_base_scenario "$r"
git -C "$r" switch -q main
git -C "$r" worktree add -q -b feat/linked-host "$tmp/linked-host" feat/other
run "$tmp/linked-host" --id T-3 --slug s --prefix fix --base relbase
[ "$rc" = 0 ] && has "BASE=relbase" && [ "$(tip "$tmp/linked-host" HEAD)" = "$(tip "$r" relbase)" ]
check "linked worktree: branch starts at the local base, not at HEAD" $?

# --- 4. origin/<base> wins over a diverged local <base> -----------------------
git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/clone" 2>/dev/null
git -C "$tmp/clone" commit -q --allow-empty -m "main: first"
git -C "$tmp/clone" push -q origin main 2>/dev/null
git -C "$tmp/clone" commit -q --allow-empty -m "main: local only"
want=$(tip "$tmp/clone" origin/main)
run "$tmp/clone" --id T-4 --slug s --prefix fix --base main --mode inplace
[ "$rc" = 0 ] && [ "$(tip "$tmp/clone" HEAD)" = "$want" ] && [ "$(tip "$tmp/clone" main)" != "$want" ]
check "origin/<base> takes precedence over a diverged local <base>" $?

# --- 5. neither origin/<base> nor local <base> --------------------------------
for mode in inplace worktree; do
  r=$tmp/none-$mode; mk_repo "$r"
  run "$r" --id T-5 --slug s --prefix fix --base nope --mode "$mode"
  [ "$rc" = 2 ] && has "ERROR=cannot-resolve-base" \
    && ! git -C "$r" show-ref --verify -q refs/heads/fix/T-5-s && [ ! -e "$r/.worktrees" ]
  check "$mode: unresolvable base -> ERROR=cannot-resolve-base, nothing created" $?
done

# --- 6. unresolvable base in a linked worktree --------------------------------
r=$tmp/none-linked; mk_repo "$r"
git -C "$r" worktree add -q -b feat/host "$tmp/none-linked-host"
run "$tmp/none-linked-host" --id T-6 --slug s --prefix fix --base nope
[ "$rc" = 2 ] && has "ERROR=cannot-resolve-base" \
  && ! git -C "$r" show-ref --verify -q refs/heads/fix/T-6-s
check "linked worktree: unresolvable base -> ERROR=cannot-resolve-base, no branch" $?

# --- 7. default base via origin/HEAD, normal case unchanged -------------------
git -C "$tmp/clone" switch -q -c feat/side
run "$tmp/clone" --id T-7 --slug s --prefix fix --mode worktree
[ "$rc" = 0 ] && has "BASE=main" && [ "$(tip "$tmp/clone" fix/T-7-s)" = "$want" ]
check "default base: new branch starts at origin/main" $?

# --- 8. resume detection with a custom worktree_dir (awk gets it via -v) -------
r=$tmp/custom-dir; mk_repo "$r"
printf 'worktree_dir = ".wt/nested.dir"\n' > "$tmp/custom.toml"
YOUTRACK_TASK_CONFIG=$tmp/custom.toml run "$r" --id T-8 --slug s --prefix fix --base main --mode worktree
[ "$rc" = 0 ] && has "MODE=worktree" && [ -d "$r/.wt/nested.dir/T-8-s" ]
check "custom worktree_dir: first run creates the worktree there" $?
YOUTRACK_TASK_CONFIG=$tmp/custom.toml run "$r" --id T-8 --slug s --prefix fix --base main --mode worktree
[ "$rc" = 0 ] && has "MODE=existing-worktree" && printf "%s\n" "$out" | grep -q "^DIR=.*/\.wt/nested\.dir/T-8-s$"
check "custom worktree_dir: second run resumes the existing worktree" $?

# --- 9. dirty tree, in-place: ERROR=dirty-tree, nothing created ----------------
r=$tmp/dirty; mk_repo "$r"
echo a > "$r/f"; git -C "$r" add f; git -C "$r" commit -q -m "add f"
echo b >> "$r/f"
run "$r" --id T-9 --slug s --prefix fix --base main --mode inplace
[ "$rc" = 2 ] && has "ERROR=dirty-tree" && ! git -C "$r" show-ref --verify -q refs/heads/fix/T-9-s \
  && [ "$(git -C "$r" branch --show-current)" = main ]
check "dirty tree, in-place: ERROR=dirty-tree, no branch, still on main" $?

# --- 10. --allow-dirty carries the tracked change onto the new branch ----------
run "$r" --id T-9 --slug s --prefix fix --base main --mode inplace --allow-dirty
[ "$rc" = 0 ] && has "MODE=inplace" && [ "$(git -C "$r" branch --show-current)" = fix/T-9-s ] \
  && grep -q '^b$' "$r/f" && [ "$(tip "$r" main)" = "$(tip "$r" HEAD)" ]
check "--allow-dirty: branch created, change carried, nothing committed" $?

# --- 11. a dirty tree does not block a worktree ----------------------------------
r=$tmp/dirty-wt; mk_repo "$r"
echo a > "$r/f"; git -C "$r" add f; git -C "$r" commit -q -m "add f"
echo b >> "$r/f"
run "$r" --id T-11 --slug s --prefix fix --base main --mode worktree
[ "$rc" = 0 ] && has "MODE=worktree" && [ -d "$r/.worktrees/T-11-s" ]
check "dirty tree, worktree mode: worktree is created" $?

# --- 12. existing worktree for the issue is resumed ----------------------------
run "$r" --id T-11 --slug s --prefix fix --base main --mode worktree
[ "$rc" = 0 ] && has "MODE=existing-worktree" && has "BRANCH=fix/T-11-s" \
  && printf '%s\n' "$out" | grep -q '^DIR=.*/\.worktrees/T-11-s$'
check "existing worktree: MODE=existing-worktree, same branch" $?

# --- 13. existing branch that is not checked out ---------------------------------
r=$tmp/exbranch; mk_repo "$r"
git -C "$r" branch fix/T-13-old
run "$r" --id T-13 --slug new --prefix fix --base main --mode inplace
[ "$rc" = 0 ] && has "MODE=existing-branch" && has "BRANCH=fix/T-13-old" \
  && ! git -C "$r" show-ref --verify -q refs/heads/fix/T-13-new
check "existing branch: MODE=existing-branch, no second branch" $?

# --- 14. an issue ID is not a prefix of another one (T-1 vs T-12) --------------
r=$tmp/collide; mk_repo "$r"
git -C "$r" branch fix/T-12-other
run "$r" --id T-1 --slug s --prefix fix --base main --mode worktree
[ "$rc" = 0 ] && has "MODE=worktree" && has "BRANCH=fix/T-1-s"
check "ID prefix collision: T-1 does not resume T-12's branch" $?
r=$tmp/collide-wt; mk_repo "$r"
run "$r" --id T-12 --slug other --prefix fix --base main --mode worktree
run "$r" --id T-1 --slug s --prefix fix --base main --mode worktree
[ "$rc" = 0 ] && has "MODE=worktree" && has "BRANCH=fix/T-1-s" && [ -d "$r/.worktrees/T-1-s" ]
check "ID prefix collision: T-1 does not resume T-12's worktree" $?

# --- 13. config keys inside a [table] are ignored (single parser: read-config) --------
r=$tmp/table-key; mk_repo "$r"
printf '[type_prefix]\nworktree_dir = ".wt"\nworktree_clone = ["nope"]\n' > "$tmp/table.toml"
YOUTRACK_TASK_CONFIG=$tmp/table.toml run "$r" --id T-13 --slug s --prefix fix --base main --mode worktree
[ "$rc" = 0 ] && has "MODE=worktree" && [ -d "$r/.worktrees/T-13-s" ] && [ ! -e "$r/.wt" ]
check "[table] worktree_dir is ignored: worktree lands in the default dir" $?

# --- 14. a failing read-config stops the script instead of yielding garbage values -------
r=$tmp/no-rc; mk_repo "$r"
mkdir "$tmp/bin-no-rc" && cp "$script" "$tmp/bin-no-rc/setup-workspace"   # no read-config next to it
script_saved=$script; script=$tmp/bin-no-rc/setup-workspace
run "$r" --id T-14 --slug s --prefix fix --base main --mode worktree
script=$script_saved
[ "$rc" = 2 ] && has "ERROR=read-config-failed" && ! git -C "$r" show-ref --verify -q refs/heads/fix/T-14-s && [ ! -e "$r/.worktrees" ]
check "missing read-config: ERROR=read-config-failed, exit 2, nothing created" $?

[ "$fail" = 0 ] && echo "ALL OK"
exit "$fail"
