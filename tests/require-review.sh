#!/usr/bin/env bash
# Cases for hooks/require-review. Usage: tests/require-review.sh [path-to-hook]
# Prints one line per case and exits non-zero if any case differs from the
# expectation. Builds throwaway git repos; needs jq.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
hook=${1:-$root/hooks/require-review}
stamp=$root/skills/youtrack-task/scripts/review-stamp
fail=0
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

repo=$tmp/repo
git init -q -b main "$repo"
git -C "$repo" commit -q --allow-empty -m "feat: base"
git -C "$repo" worktree add -q -b feat/X-1-demo "$tmp/wt" >/dev/null 2>&1
git -C "$tmp/wt" commit -q --allow-empty -m "feat: work"

cfg=$tmp/config.toml
export YOUTRACK_TASK_CONFIG=$cfg
printf 'review_gate_hook = "on"\n' > "$cfg"

# run_hook <agent or ""> <cwd> <command> -> sets got, err
run_hook() {
  local agent=$1 cwd=$2 cmd=$3 json
  json=$(jq -nc --arg a "$agent" --arg w "$cwd" --arg c "$cmd" \
    '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}} + (if $a != "" then {agent_type:$a} else {} end)')
  err=$(printf '%s' "$json" | bash "$hook" 2>&1 >/dev/null); got=$?
}
# t <expected-exit> <label> <cwd> <command> [expected stderr substring]
t() {
  local exp=$1 label=$2 cwd=$3 cmd=$4 sub=${5:-} err got
  run_hook "" "$cwd" "$cmd"
  if [ "$got" = "$exp" ] && { [ -z "$sub" ] || printf '%s' "$err" | grep -qF -- "$sub"; }; then
    echo "ok   $exp  $label"
  else
    echo "FAIL want $exp got $got  $label"; printf '%s\n' "$err" | sed 's/^/     | /'; fail=1
  fi
}
stamp_it() { bash "$stamp" write --id X-1 --sha "$(git -C "$tmp/wt" rev-parse HEAD)" --verdict "$1" --independent "${2:-yes}" --dir "$tmp/wt" >/dev/null; }

wt=$tmp/wt
rm -f "$cfg"
t 0 "no config file (default off): unreviewed push passes" "$wt" "git push -u origin feat/X-1-demo"
printf 'review_gate_hook = "off"\n' > "$cfg"
t 0 "config off: unreviewed push passes" "$wt" "git push -u origin feat/X-1-demo"
printf 'review_gate_hook = "on"\n' > "$cfg"

t 2 "no stamp: git push denied" "$wt" "git push -u origin feat/X-1-demo" "has no review"
t 2 "no stamp: plain git push denied" "$wt" "git push" "has no review"
t 2 "no stamp: gh pr create denied" "$wt" "gh pr create --title t --body b" "has no review"
t 2 "no stamp: chained after cd denied" "$repo" "cd $wt && git push origin HEAD" "has no review"
t 2 "no stamp: git -C denied" "$repo" "git -C $wt push origin feat/X-1-demo" "has no review"

stamp_it PASS
t 0 "PASS on this commit: push allowed" "$wt" "git push -u origin feat/X-1-demo"
t 0 "PASS: gh pr create allowed" "$wt" "gh pr create --title t --body b"
t 0 "PASS: gh pr create with quoted title and body still allowed" "$wt" "gh pr create --title \"a b\" --body 'c d'"
t 2 "PASS: quoted --head cannot be resolved -> denied" "$repo" "gh pr create --head \"feat/X-1-demo\"" "cannot resolve"
t 0 "PASS: git push --all allowed when every issue branch is stamped" "$repo" "git push --all origin"
t 0 "PASS: gh pr create --head from the main checkout" "$repo" "gh pr create --base main --head feat/X-1-demo --title t"
t 0 "PASS: SHA refspec allowed" "$repo" "git -C $wt push -u origin $(git -C "$wt" rev-parse HEAD):refs/heads/feat/X-1-demo"

reviewed=$(git -C "$wt" rev-parse HEAD)
git -C "$wt" commit -q --allow-empty -m "fix: after review"
t 2 "new commit after PASS: push denied (stale)" "$wt" "git push" "not the one that was reviewed"
t 2 "new commit after PASS: gh pr create --head denied" "$repo" "gh pr create --head feat/X-1-demo" "not the one that was reviewed"
t 0 "pushing exactly the reviewed SHA still allowed" "$repo" "git -C $wt push origin $reviewed:refs/heads/feat/X-1-demo"
echo x > "$wt/dirty"
t 2 "dirty tree does not matter, the new commit does" "$wt" "git push" "not the one that was reviewed"
rm "$wt/dirty"

stamp_it FAILED
t 2 "FAILED: push denied" "$wt" "git push" "open findings"
stamp_it SKIPPED no
t 0 "SKIPPED waiver: push allowed" "$wt" "git push"

t 0 "SKIPPED waiver: git push --all allowed" "$repo" "git push --all origin"
git -C "$wt" commit -q --allow-empty -m "fix: more"
t 2 "waiver is bound to its commit" "$wt" "git push" "not the one that was reviewed"

# finding 1: the gate keys on the destination only
t 2 "issue branch pushed to main (src has the ID, dst does not)" "$repo" "git push origin feat/X-1-demo:main" "not the one that was reviewed"
t 2 "HEAD of an issue branch pushed to main" "$wt" "git push origin HEAD:main" "not the one that was reviewed"
t 2 "refs/heads source pushed to another name" "$repo" "git push origin refs/heads/feat/X-1-demo:refs/heads/release" "not the one that was reviewed"
# finding 2: pushing every ref
t 2 "git push --all denied" "$repo" "git push --all origin" "not the one that was reviewed"
t 2 "git push --mirror denied" "$repo" "git push --mirror origin" "not the one that was reviewed"
t 2 "git push --branches denied" "$repo" "git push --branches origin" "not the one that was reviewed"
t 0 "pure --tags push still passes" "$wt" "git push --tags origin"
# finding 3: quoted arguments must not drop out of the parse
t 2 "quoted refspec denied, not skipped" "$wt" "git push origin \"HEAD:main\"" "cannot resolve"
t 2 "quoted remote denied" "$wt" "git push 'origin' feat/X-1-demo" "cannot resolve"
t 2 "quoted -C directory denied" "$repo" "git -C \"$wt\" push origin feat/X-1-demo" "cannot tell in which directory"
t 2 "quoted cd target denied" "$repo" "cd \"$wt\" && git push" "cannot tell in which directory"
t 2 "variable in the directory denied" "$repo" "cd \$WT && git push" "cannot tell in which directory"
# round 3: matching / wildcard refspecs, spelling by SHA, escapes, unresolvable refs
tip=$(git -C "$wt" rev-parse HEAD)
t 2 "bare ':' (matching refspec) is gated like --all" "$repo" "git push origin :" "not the one that was reviewed"
t 2 "wildcard refspec denied" "$repo" "git push origin refs/heads/*:refs/heads/*" "cannot resolve"
t 2 "quoted wildcard refspec denied" "$repo" "git push origin 'refs/heads/*:refs/heads/*'" "cannot resolve"
t 2 "backslash-escaped refspec denied" "$wt" "git push origin feat/X-1\\-demo:main" "cannot resolve"
t 2 "brace expansion denied" "$wt" "git push origin feat/X-1-demo{,}:main" "cannot resolve"
t 2 "tilde revision denied" "$wt" "git push origin HEAD~0:main" "cannot resolve"
t 2 "issue tip pushed by raw SHA to another name" "$repo" "git push origin $tip:refs/heads/release" "not the one that was reviewed"
t 2 "unresolvable refspec source denied, not skipped" "$wt" "git push origin no-such-ref:main" "cannot resolve the refspec source"
t 2 "gh pr create --head of an issue branch that is not local" "$repo" "gh pr create --head feat/X-9-remote-only" "does not exist locally"
t 0 "gh pr create --head of a non-issue branch that is not local passes" "$repo" "gh pr create --head some-remote-branch"
# a local non-issue branch is no proof of review
git -C "$repo" branch scratch "$tip"
t 2 "a local scratch branch on the issue tip does not exempt it" "$repo" "git push origin $tip:refs/heads/release" "not the one that was reviewed"
git -C "$repo" branch -q -D scratch
# only a published commit (reachable from a remote-tracking ref) is exempt
git -C "$repo" branch feat/X-7-fresh main
t 2 "unpublished main tip under a fresh issue branch is gated" "$repo" "git push origin main" "has no review"
git -C "$repo" update-ref refs/remotes/origin/main main
t 0 "main published: a fresh issue branch on its tip does not block pushing main" "$repo" "git push origin main"
git -C "$repo" update-ref -d refs/remotes/origin/main
git -C "$repo" branch -q -D feat/X-7-fresh

t 0 "delete push passes" "$wt" "git push origin --delete feat/X-1-demo"
t 0 "colon-delete passes" "$wt" "git push origin :feat/X-1-demo"
t 0 "tags push passes" "$wt" "git push --tags"
t 0 "non-issue branch passes" "$repo" "git push origin main"
t 0 "command mentioning push in a quoted string passes" "$wt" "git commit -m 'do not git push yet'"
t 0 "echo of a push passes" "$wt" "echo \"git push\""
t 0 "unrelated command passes" "$wt" "ls -la"

printf 'review_gate_hook = "on"\nreview_before_pr = "never"\n' > "$cfg"
t 0 "review_before_pr = never: passes" "$wt" "git push"
printf 'review_gate_hook = "on"\n' > "$cfg"

run_hook ticket-worker "$wt" "git push"
[ "$got" = 0 ] && echo "ok   0  subagent calls are left to guard-subagent" || { echo "FAIL subagent call handled by require-review (rc=$got)"; fail=1; }

printf '{"tool_input":' | bash "$hook" >/dev/null 2>&1; [ $? = 0 ] && echo "ok   0  malformed input fails open" || { echo "FAIL malformed input"; fail=1; }

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILURES"
exit "$fail"
