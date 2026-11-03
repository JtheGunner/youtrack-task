#!/usr/bin/env bash
# Cases for hooks/guard-subagent. Usage: tests/guard-subagent.sh [path-to-hook]
# Builds two throwaway git repos (one on an issue branch, one on the default
# branch) so the HEAD / no-refspec push checks run against real branches.
set -u
hook=${1:-$(cd "$(dirname "$0")/.." && pwd)/hooks/guard-subagent}
fail=0
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
REPO=$(mktemp -d); trap 'rm -rf "$REPO"' EXIT
for r in hookrepo hookmain; do
  git init -q "$REPO/$r"
  git -C "$REPO/$r" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
done
git -C "$REPO/hookrepo" switch -q -c fix/ABC-1-x
t() { # expected agent command
  local exp=$1 agent=$2 cmd=$3 json
  if [ -n "$agent" ]; then json=$(jq -nc --arg a "$agent" --arg c "$cmd" '{agent_type:$a,tool_name:"Bash",tool_input:{command:$c}}')
  else json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}'); fi
  printf '%s' "$json" | bash "$hook" >/dev/null 2>&1; got=$?
  [ "$got" = "$exp" ] && echo "ok   $exp  [$agent] $cmd" || { echo "FAIL want $exp got $got [$agent] $cmd"; fail=1; }
}
W=youtrack-task:ticket-worker; R=youtrack-task:ticket-reviewer
t 0 $W "git push -u origin fix/ABC-1-x"
t 0 $W "cd $REPO/hookrepo && git push"
t 0 $W "cd $REPO/hookrepo && git push origin HEAD"
t 0 $W "git -C $REPO/hookrepo push -u origin HEAD"
t 2 $W "cd $REPO/hookmain && git push"
t 2 $W "cd $REPO/hookmain && git push origin HEAD"
t 2 $W "git push --force origin fix/ABC-1-x"
t 2 $W "git push -f origin fix/ABC-1-x"
t 2 $W "git push origin HEAD:main"
t 2 $W "git push origin +fix/ABC-1-x"
t 2 $W "git push origin main"
t 2 $W "gh pr merge 5"
t 2 $W "git commit --no-verify -m x"
t 2 $W "git branch -D x"
t 0 $W "npm test"
t 0 $R "git diff main...HEAD"
t 0 $R "npm test"
t 2 $R "git commit -m x"
t 2 $R "git push"
t 2 $R "gh pr merge 5"
t 2 $R "rm -rf src"
t 2 $W "git push -fu origin fix/ABC-1-x"
t 2 $W "git push -df origin fix/ABC-1-x"
t 2 $W "git push --tags origin fix/ABC-1-x"
t 2 $W "git push --prune origin fix/ABC-1-x"
t 2 $W "bash -c 'git push --force'"
t 2 $W 'git push origin $(echo main)'
t 2 $W "/usr/bin/git push origin main"
t 2 $W "git -c core.hooksPath=/dev/null commit -m x"
t 2 $W "gh api -X PUT repos/o/r/pulls/5/merge"
t 2 $W "env gh pr merge 5"
t 2 $W "eval git push origin main"
t 0 $W "grep env README.md"
t 0 $W "bash tests/run.sh"
t 2 $W "git push origin HEAD"
t 2 $R "bash -c 'git commit -am x'"
t 2 $R "sed -i s/a/b/ file"
t 2 $R "find . -delete"
t 2 $R "echo x > file.txt"
t 0 $R "echo x > /dev/null"
t 0 $R "cd /r/wt && git diff main...HEAD | head -50"
t 0 $R "cd /r/wt && php artisan test --filter Foo"
t 2 $R "curl http://x"
t 0 "" "gh pr merge 5"
t 0 "" "git push --force"
printf 'not json' | bash "$hook" >/dev/null 2>&1; [ $? = 0 ] && echo "ok   0  malformed" || { echo "FAIL malformed"; fail=1; }
exit $fail
