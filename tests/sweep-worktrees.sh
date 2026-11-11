#!/usr/bin/env bash
# Cases for skills/youtrack-task/scripts/sweep-worktrees.
# Usage: tests/sweep-worktrees.sh [path-to-script]
# `gh` is replaced by a stub in PATH that answers `gh pr view <branch> --json
# state -q .state` from files in $GH_STATE_DIR. Builds throwaway git repos.
set -u
script=${1:-$(cd "$(dirname "$0")/.." && pwd)/skills/youtrack-task/scripts/sweep-worktrees}
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export YOUTRACK_TASK_CONFIG=$tmp/no-config.toml   # never read the real user config

# gh stub: prints the state stored for the branch, exits 1 when there is none
mkdir "$tmp/stub" "$tmp/states"
cat > "$tmp/stub/gh" <<'STUB'
#!/usr/bin/env bash
# usage: gh pr view <branch> --json state -q .state
[ "$1" = pr ] && [ "$2" = view ] || exit 2
f="$GH_STATE_DIR/$(printf '%s' "$3" | tr / _)"
[ -f "$f" ] && cat "$f" || exit 1
STUB
chmod +x "$tmp/stub/gh"
export GH_STATE_DIR=$tmp/states
export PATH="$tmp/stub:$PATH"

run() { local d=$1; shift; out=$(cd "$d" && bash "$script" "$@" 2>&1); rc=$?; }
has() { printf '%s\n' "$out" | grep -qxF -- "$1"; }
hasre() { printf '%s\n' "$out" | grep -qE -- "$1"; }
check() {
  if [ "$2" = 0 ]; then echo "ok   $1"; else
    echo "FAIL $1 (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/     | /'; fail=1
  fi
}
state() { printf '%s' "$2" > "$GH_STATE_DIR/$(printf '%s' "$1" | tr / _)"; }
branch_exists() { git -C "$1" show-ref --verify -q "refs/heads/$2"; }

# mk_repo <dir> ; mk_wt <repo> <branch> <name> [merged]
# merged: the branch is already contained in main (git branch -d works).
# otherwise it carries one extra commit (git branch -d refuses).
mk_repo() { git init -q -b main "$1"; git -C "$1" commit -q --allow-empty -m "first"; }
mk_wt() {
  git -C "$1" worktree add -q -b "$2" "$1/.worktrees/$3" main
  [ "${4:-}" = merged ] || git -C "$1/.worktrees/$3" commit -q --allow-empty -m "work on $2"
}

# --- 1. merged PR, clean, branch merged: worktree and branch are removed -------
r=$tmp/merged; mk_repo "$r"; mk_wt "$r" fix/T-1-a T-1-a merged; state fix/T-1-a MERGED
run "$r" 
[ "$rc" = 0 ] && hasre '^REMOVED=.*/\.worktrees/T-1-a \(fix/T-1-a\)$' && has "DONE=1" \
  && [ ! -e "$r/.worktrees/T-1-a" ] && ! branch_exists "$r" fix/T-1-a
check "merged PR + clean: worktree and merged branch removed" $?

# --- 2. closed, unmerged PR: worktree removed, branch kept (no branch -D) ------
r=$tmp/closed; mk_repo "$r"; mk_wt "$r" fix/T-2-a T-2-a; state fix/T-2-a CLOSED
run "$r"
[ "$rc" = 0 ] && hasre '^REMOVED=.*T-2-a \(fix/T-2-a\)$' && [ ! -e "$r/.worktrees/T-2-a" ] \
  && branch_exists "$r" fix/T-2-a
check "closed, unmerged PR: worktree removed, unmerged branch kept (no branch -D)" $?

# --- 3. open PR, and no PR at all: kept ---------------------------------------
r=$tmp/open; mk_repo "$r"
mk_wt "$r" fix/T-3-a T-3-a; state fix/T-3-a OPEN
mk_wt "$r" fix/T-3-b T-3-b
run "$r"
[ "$rc" = 0 ] && hasre '^KEPT_OPEN=.*T-3-a \(fix/T-3-a\)$' && hasre '^KEPT_OPEN=.*T-3-b \(fix/T-3-b\)$' \
  && has "DONE=0" && [ -d "$r/.worktrees/T-3-a" ] && [ -d "$r/.worktrees/T-3-b" ]
check "open PR / no PR: worktrees kept" $?

# --- 4. dirty worktree is kept, even with a merged PR --------------------------
r=$tmp/dirty; mk_repo "$r"; mk_wt "$r" fix/T-4-a T-4-a merged; state fix/T-4-a MERGED
echo x > "$r/.worktrees/T-4-a/untracked"
run "$r"
[ "$rc" = 0 ] && hasre '^KEPT_DIRTY=.*T-4-a \(fix/T-4-a\)$' && has "DONE=0" \
  && [ -e "$r/.worktrees/T-4-a/untracked" ] && branch_exists "$r" fix/T-4-a
check "dirty worktree (untracked file) with merged PR: kept" $?

r=$tmp/dirty2; mk_repo "$r"; mk_wt "$r" fix/T-4-b T-4-b merged; state fix/T-4-b MERGED
echo x > "$r/.worktrees/T-4-b/tracked"; git -C "$r/.worktrees/T-4-b" add tracked; git -C "$r/.worktrees/T-4-b" commit -q -m t
echo y >> "$r/.worktrees/T-4-b/tracked"
run "$r"
[ "$rc" = 0 ] && hasre '^KEPT_DIRTY=.*T-4-b' && [ -d "$r/.worktrees/T-4-b" ]
check "dirty worktree (modified tracked file) with merged PR: kept" $?

# --- 5. --exclude ---------------------------------------------------------------
r=$tmp/excl; mk_repo "$r"
mk_wt "$r" fix/T-5-a T-5-a merged; state fix/T-5-a MERGED
mk_wt "$r" fix/T-5-b T-5-b merged; state fix/T-5-b MERGED
run "$r" --exclude fix/T-5-a
[ "$rc" = 0 ] && hasre '^KEPT_EXCLUDED=.*T-5-a \(fix/T-5-a\)$' && hasre '^REMOVED=.*T-5-b' \
  && [ -d "$r/.worktrees/T-5-a" ] && [ ! -e "$r/.worktrees/T-5-b" ]
check "--exclude keeps that branch, sweeps the others" $?

# --- 6. --dry-run changes nothing -------------------------------------------------
r=$tmp/dry; mk_repo "$r"; mk_wt "$r" fix/T-6-a T-6-a merged; state fix/T-6-a MERGED
run "$r" --dry-run
[ "$rc" = 0 ] && hasre '^REMOVED=.*T-6-a.*\[dry-run\]$' && has "DONE=1" \
  && [ -d "$r/.worktrees/T-6-a" ] && branch_exists "$r" fix/T-6-a
check "--dry-run reports but removes nothing" $?

# --- 7. worktrees outside worktree_dir are ignored ---------------------------------
r=$tmp/outside; mk_repo "$r"
git -C "$r" worktree add -q -b fix/T-7-a "$tmp/outside-wt" main; state fix/T-7-a MERGED
run "$r"
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q T-7-a && [ -d "$tmp/outside-wt" ]
check "worktree outside worktree_dir is not touched" $?

# --- 8. custom worktree_dir ---------------------------------------------------------
r=$tmp/customdir; mk_repo "$r"
printf 'worktree_dir = ".wt"\n' > "$tmp/custom.toml"
git -C "$r" worktree add -q -b fix/T-8-a "$r/.wt/T-8-a" main; state fix/T-8-a MERGED
YOUTRACK_TASK_CONFIG=$tmp/custom.toml run "$r"
[ "$rc" = 0 ] && hasre '^REMOVED=.*/\.wt/T-8-a' && [ ! -e "$r/.wt/T-8-a" ]
check "custom worktree_dir is honoured" $?

# --- 9. no gh on PATH -----------------------------------------------------------------
r=$tmp/nogh; mk_repo "$r"; mk_wt "$r" fix/T-9-a T-9-a merged; state fix/T-9-a MERGED
mkdir "$tmp/nogh-bin"
for t in git bash sed awk head grep dirname basename cat tr mkdir rm date env; do
  p=$(command -v "$t") && ln -s "$p" "$tmp/nogh-bin/$t"
done
out=$(cd "$r" && PATH="$tmp/nogh-bin" "$tmp/nogh-bin/bash" "$script" 2>&1); rc=$?
[ "$rc" = 0 ] && has "SKIPPED=no-gh" && has "DONE=0" && [ -d "$r/.worktrees/T-9-a" ]
check "no gh: SKIPPED=no-gh, nothing removed" $?

# --- 10. outside a git repo / bad arg ------------------------------------------------
run "$tmp" ; [ "$rc" = 2 ] && has "ERROR=not-in-git-repo"
check "outside a git repo: ERROR=not-in-git-repo" $?
run "$tmp/merged" --bogus; [ "$rc" = 2 ] && printf '%s\n' "$out" | grep -q '^ERROR=unknown arg'
check "unknown argument: ERROR, exit 2" $?

# --- 10b. config keys inside a [table] are ignored ---------------------------------
r=$tmp/tablekey; mk_repo "$r"
printf '[type_prefix]\nworktree_dir = ".wt"\n' > "$tmp/table.toml"
mk_wt "$r" fix/T-10-a T-10-a merged; state fix/T-10-a MERGED
YOUTRACK_TASK_CONFIG=$tmp/table.toml run "$r"
[ "$rc" = 0 ] && hasre '^REMOVED=.*/\.worktrees/T-10-a' && [ ! -e "$r/.worktrees/T-10-a" ]
check "[table] worktree_dir is ignored: default dir is still swept" $?

# --- 11. safety by construction: no --force, no branch -D ---------------------------
out=$(grep -vE '^[[:space:]]*#' "$script" | grep -nE -- '--force|branch +-D|push'); [ -z "$out" ]; rc=$?
check "script never uses --force, git branch -D or push" $rc

[ "$fail" = 0 ] && echo "ALL OK"
exit "$fail"
