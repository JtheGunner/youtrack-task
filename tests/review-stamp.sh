#!/usr/bin/env bash
# Cases for skills/youtrack-task/scripts/review-stamp.
# Usage: tests/review-stamp.sh [path-to-script]
# Prints one line per case and exits non-zero if any case differs from the
# expectation. Builds throwaway git repos under a temp dir.
set -u
script=${1:-$(cd "$(dirname "$0")/.." && pwd)/skills/youtrack-task/scripts/review-stamp}
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

repo=$tmp/repo
git init -q "$repo"
git -C "$repo" commit -q --allow-empty -m "feat: first"
git -C "$repo" worktree add -q -b feat/X-1 "$tmp/wt" >/dev/null 2>&1

# run <dir> <args...> -> sets out and rc
run() { local d=$1; shift; out=$(cd "$d" && bash "$script" "$@" 2>&1); rc=$?; }

# expect <label> <expected-rc> <expected-substring-or-empty>
expect() {
  local label=$1 want_rc=$2 want=$3
  if [ "$rc" = "$want_rc" ] && { [ -z "$want" ] || printf '%s' "$out" | grep -qF -- "$want"; }; then
    echo "ok   $label"
  else
    echo "FAIL $label (rc=$rc, want rc=$want_rc, want '$want')"; printf '%s\n' "$out" | sed 's/^/     | /'; fail=1
  fi
}

head_sha() { git -C "$1" rev-parse HEAD; }

run "$repo" check --id X-1;                         expect "no stamp -> MISSING"          0 "REVIEW=MISSING"

sha=$(head_sha "$repo")
run "$repo" write --id X-1 --sha "$sha" --verdict PASS --independent yes
expect "write PASS on HEAD"                          0 "WROTE=X-1"
run "$repo" check --id X-1;                         expect "check -> PASS"                0 "REVIEW=PASS"
printf '%s' "$out" | grep -qF "INDEPENDENT=yes" && echo "ok   independent flag stored" || { echo "FAIL independent flag stored"; fail=1; }

run "$tmp/wt" check --id X-1;                       expect "worktree sees the same stamp" 0 "REVIEW=PASS"

echo x > "$repo/file"
run "$repo" check --id X-1;                         expect "untracked file -> STALE"      0 "REVIEW=STALE"
rm "$repo/file"
run "$repo" check --id X-1;                         expect "tree clean again -> PASS"     0 "REVIEW=PASS"

git -C "$repo" commit -q --allow-empty -m "fix: second"
run "$repo" check --id X-1;                         expect "new commit -> STALE"          0 "REVIEW=STALE"

sha=$(head_sha "$repo")
run "$repo" write --id X-1 --sha "$sha" --verdict FAILED --independent yes --round 2
expect "write FAILED on HEAD"                        0 "WROTE=X-1"
run "$repo" check --id X-1;                         expect "check -> FAILED"              0 "REVIEW=FAILED"

run "$repo" write --id X-1 --sha 0000000000000000000000000000000000000000 --verdict PASS --independent yes
expect "refuse SHA that is not HEAD"                 2 "ERROR=sha-not-head"

echo x > "$repo/file"
run "$repo" write --id X-1 --sha "$sha" --verdict PASS --independent yes
expect "refuse write on dirty tree"                  2 "ERROR=dirty"
rm "$repo/file"

run "$repo" write --id X-1 --sha "$sha" --verdict MAYBE --independent yes
expect "refuse unknown verdict"                      2 "ERROR=bad-verdict"
run "$repo" write --id X-1 --sha "$sha" --verdict PASS --independent perhaps
expect "refuse unknown independent value"            2 "ERROR=bad-independent"
run "$repo" check --id '../evil';                   expect "refuse path-like id"          2 "ERROR=bad-id"
run "$repo" check --id 'x-1';                       expect "refuse lowercase id"          2 "ERROR=bad-id"
run "$repo" check;                                  expect "refuse missing id"            2 "ERROR=need --id"
run "$repo" frobnicate --id X-1;                    expect "refuse unknown command"       2 "ERROR=unknown-command"
run "$tmp" check --id X-1;                          expect "refuse outside a repo"        2 "ERROR=not-in-git-repo"

# --sha: ask about an exact commit, ignoring HEAD and the working tree
old=$(git -C "$repo" rev-parse HEAD)
run "$repo" write --id X-1 --sha "$old" --verdict PASS --independent yes
git -C "$repo" commit -q --allow-empty -m "fix: third"
run "$repo" check --id X-1 --sha "$old";            expect "check --sha on the stamped commit -> PASS" 0 "REVIEW=PASS"
run "$repo" check --id X-1 --sha "$(git -C "$repo" rev-parse HEAD)"
expect "check --sha on another commit -> STALE"      0 "REVIEW=STALE"
echo x > "$repo/file"
run "$repo" check --id X-1 --sha "$old";            expect "check --sha ignores a dirty tree" 0 "REVIEW=PASS"
rm "$repo/file"
run "$repo" check --id X-1 --sha nonsense;          expect "refuse malformed --sha"       2 "ERROR=bad-sha"

# SKIPPED waiver: bound to its commit, never independent
sha=$(git -C "$repo" rev-parse HEAD)
run "$repo" write --id X-1 --sha "$sha" --verdict SKIPPED --independent yes
expect "refuse an independent SKIPPED waiver"        2 "ERROR=bad-independent"
run "$repo" write --id X-1 --sha "$sha" --verdict SKIPPED --independent no
expect "write SKIPPED waiver"                        0 "WROTE=X-1"
run "$repo" check --id X-1;                         expect "check -> SKIPPED"             0 "REVIEW=SKIPPED"
git -C "$repo" commit -q --allow-empty -m "fix: fourth"
run "$repo" check --id X-1;                         expect "waiver is stale after a commit" 0 "REVIEW=STALE"

# project keys with a digit (P2X-5) are whole IDs, not X-5
git -C "$repo" worktree add -q -b fix/P2X-5-demo "$tmp/wt2" >/dev/null 2>&1
sha2=$(head_sha "$tmp/wt2")
run "$tmp/wt2" write --id P2X-5 --sha "$sha2" --verdict PASS --independent yes --dir "$tmp/wt2"
expect "write PASS for a key with a digit (P2X-5)"   0 "WROTE=P2X-5"
run "$tmp/wt2" check --id P2X-5 --dir "$tmp/wt2";   expect "check P2X-5 -> PASS"          0 "REVIEW=PASS"
run "$tmp/wt2" check --id X-5 --dir "$tmp/wt2";     expect "X-5 is a different issue -> MISSING" 0 "REVIEW=MISSING"

# the stamp lives inside the git dir, never in the working tree
git -C "$repo" status --porcelain | grep -q . && { echo "FAIL stamp leaked into working tree"; fail=1; } || echo "ok   working tree untouched"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILURES"
exit "$fail"
