#!/usr/bin/env bash
# Cases for hooks/guard-subagent. Usage: tests/guard-subagent.sh [path-to-hook]
# Prints one line per case and exits non-zero if any case behaves differently
# from the expectation. Needs jq.
set -u
hook=${1:-$(cd "$(dirname "$0")/.." && pwd)/hooks/guard-subagent}
fail=0
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

# t <expected-exit> <agent_type or ""> <command>
t() {
  local exp=$1 agent=$2 cmd=$3 json got
  if [ -n "$agent" ]; then
    json=$(jq -nc --arg a "$agent" --arg c "$cmd" '{agent_type:$a,tool_name:"Bash",tool_input:{command:$c}}')
  else
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
  fi
  printf '%s' "$json" | bash "$hook" >/dev/null 2>&1; got=$?
  if [ "$got" = "$exp" ]; then echo "ok   $exp  [$agent] $cmd"
  else echo "FAIL want $exp got $got [$agent] $cmd"; fail=1; fi
}

W=youtrack-task:ticket-worker
R=youtrack-task:ticket-reviewer

echo "# worker: the one allowed push form"
t 0 $W "git push -u origin fix/ABC-1-x"
t 0 $W "git push --set-upstream origin fix/ABC-1-x"
t 0 $W "git push origin fix/ABC-1-x"
t 0 $W "git push origin HEAD:fix/ABC-1-x"
t 0 $W "cd /r/.worktrees/ABC-1-x && git push -u origin fix/ABC-1-x"
t 0 $W "git -C /r/.worktrees/ABC-1-x push -u origin fix/ABC-1-x"

echo "# worker: every other push form is denied"
t 2 $W "git push"
t 2 $W "git push origin"
t 2 $W "git push origin HEAD"
t 2 $W "git push --force origin fix/ABC-1-x"
t 2 $W "git push -f origin fix/ABC-1-x"
t 2 $W "git push -fu origin fix/ABC-1-x"
t 2 $W "git push -df origin fix/ABC-1-x"
t 2 $W "git push --force-w origin fix/ABC-1-x"
t 2 $W "git push --forc origin fix/ABC-1-x"
t 2 $W "git push --del origin fix/ABC-1-x"
t 2 $W "git push --tags origin fix/ABC-1-x"
t 2 $W "git push --prune origin fix/ABC-1-x"
t 2 $W "git push origin HEAD:main"
t 2 $W "git push origin main"
t 2 $W "git push origin +fix/ABC-1-x"
t 2 $W "git push origin fix/ABC-1-x main"
t 2 $W "git push origin fix/ABC-1-x:main"
t 2 $W "git push origin :fix/ABC-1-x"

echo "# worker: hidden or wrapped commands"
t 2 $W "git --no-pager push origin main"
t 2 $W "git -c core.hooksPath=/dev/null commit -m x"
t 2 $W "git  push --force origin main"
t 2 $W "(git push --force origin main)"
t 2 $W "! git push --force origin main"
t 2 $W "GIT_X=1 git push --force origin main"
t 2 $W "time git push --force origin main"
t 2 $W "timeout 5 git push --force origin main"
t 2 $W "bash -c 'git push --force'"
t 2 $W 'git push origin $(echo main)'
t 2 $W "/usr/bin/git push origin main"
t 2 $W "env gh pr merge 5"
t 2 $W "eval git push origin main"
t 2 $W "git config alias.p '!git push --force'"
t 2 $W "git config core.hooksPath /dev/null"
t 0 $W "git config --get user.name"

echo "# worker: merging, hooks, branch deletion"
t 2 $W "gh pr merge 5"
t 2 $W "gh api -X PUT repos/o/r/pulls/5/merge"
t 2 $W "git commit --no-verify -m x"
t 2 $W "git branch -D x"

echo "# worker: ordinary work passes"
t 0 $W "npm test"
t 0 $W "grep env README.md"
t 0 $W "bash tests/run.sh"
t 0 $W "git commit -m 'feat: x'"
t 0 $W "git status"

echo "# reviewer: read-only allowlist"
t 0 $R "git diff main...HEAD"
t 0 $R "cd /r/wt && git diff main...HEAD | head -50"
t 0 $R "cd /r/wt && php artisan test --filter Foo"
t 0 $R "npm test"
t 0 $R "echo x > /dev/null"
t 2 $R "git commit -m x"
t 2 $R "git push"
t 2 $R "gh pr merge 5"
t 2 $R "rm -rf src"
t 2 $R "bash -c 'git commit -am x'"
t 2 $R "sed -i s/a/b/ file"
t 2 $R "sed -n 'w out.txt' file"
t 2 $R "find . -delete"
t 2 $R "find . -fprint out.txt"
t 2 $R "echo x > file.txt"
t 2 $R "curl http://x"
t 2 $R "git grep -O vim foo"
t 2 $R "git diff --output=/tmp/x main"
t 2 $R "rg --pre ./evil foo"
t 2 $R "sort -o out.txt in.txt"
t 2 $R "tree -o out.txt"
t 2 $R "vendor/bin/evil-script"
t 2 $R "FOO=1 git diff"

echo "# main session and malformed input are untouched"
t 0 "" "gh pr merge 5"
t 0 "" "git push --force"
printf 'not json' | bash "$hook" >/dev/null 2>&1
if [ $? = 0 ]; then echo "ok   0  malformed input"; else echo "FAIL malformed input"; fail=1; fi

exit $fail
