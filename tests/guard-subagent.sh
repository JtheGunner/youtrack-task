#!/usr/bin/env bash
# Cases for hooks/guard-subagent. Usage: tests/guard-subagent.sh [path-to-hook]
# Prints one line per case and exits non-zero if any case behaves differently
# from the expectation. Needs jq.
set -u
hook=${1:-$(cd "$(dirname "$0")/.." && pwd)/hooks/guard-subagent}
fail=0
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

# run_hook <agent_type or ""> <command>  -> sets got (exit code) and err (stderr)
run_hook() {
  local agent=$1 cmd=$2 json
  if [ -n "$agent" ]; then
    json=$(jq -nc --arg a "$agent" --arg c "$cmd" '{agent_type:$a,tool_name:"Bash",tool_input:{command:$c}}')
  else
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
  fi
  err=$(printf '%s' "$json" | bash "$hook" 2>&1 >/dev/null); got=$?
}

# t <expected-exit> <agent_type or ""> <command>
t() {
  local exp=$1 agent=$2 cmd=$3 err got
  run_hook "$agent" "$cmd"
  if [ "$got" = "$exp" ]; then echo "ok   $exp  [${agent##*:}] $(printf '%s' "$cmd" | head -c 90 | tr '\n' ' ')"
  else echo "FAIL want $exp got $got [${agent##*:}] $cmd"; fail=1; fi
}

# treason <agent_type> <command> <stderr-substring>: denied, and for that reason
treason() {
  local agent=$1 cmd=$2 want=$3 err got
  run_hook "$agent" "$cmd"
  if [ "$got" = 2 ] && printf '%s' "$err" | grep -qF -- "$want"; then
    echo "ok   2  [${agent##*:}] reason '$want': $(printf '%s' "$cmd" | head -c 70 | tr '\n' ' ')"
  else echo "FAIL want 2 with '$want', got $got ($err) [${agent##*:}] $cmd"; fail=1; fi
}

W=youtrack-task:ticket-worker
R=youtrack-task:ticket-reviewer

echo "# worker: pushing is never allowed (the main session pushes after review)"
treason $W "git push -u origin fix/ABC-1-x" "never push"
treason $W "git push" "never push"
treason $W "git push --force origin fix/ABC-1-x" "never push"
treason $W "git push origin HEAD:main" "never push"
treason $W "cd /r/wt && git push -u origin fix/ABC-1-x" "never push"
treason $W "git -C /r/wt push origin fix/ABC-1-x" "never push"
treason $W "git push origin fix/ABC-1-x 2>&1" "never push"
treason $W "git  push origin x" "never push"

echo "# worker: hidden or wrapped commands"
treason $W "git --no-pager push origin main" "no git options"
treason $W "git -c core.hooksPath=/dev/null commit -m x" "no git options"
t 2 $W "(git push --force origin main)"
t 2 $W "! git push --force origin main"
treason $W "time git push --force origin main" "keywords"
treason $W "timeout 5 git push origin main" "wrapper"
treason $W "bash -c 'git push --force'" "wrapper"
treason $W 'git push origin $(echo main)' "substitution"
treason $W "/usr/bin/git push origin main" "by name"
treason $W "env gh pr merge 5" "wrapper"
treason $W "eval git push origin main" "wrapper"
t 2 $W "if true; then git push origin main; fi"
t 2 $W "git 'push' origin main"
t 2 $W 'git "push" origin main'
t 2 $W "g\\it push origin main"
t 2 $W "'git' push origin main"
t 2 $W "gh pr 'merge' 5"
t 2 $W "foo() { git push origin main; }; foo"
t 2 $W "{ git push origin main; }"
t 2 $W "PATH=/tmp/evil git status"
t 2 $W "GIT_SSH_COMMAND=x git status"
treason $W "git config alias.p '!git push --force'" "read-only"
treason $W "git config core.hooksPath /dev/null" "read-only"
t 0 $W "git config --get user.name"

echo "# worker: parser tricks fail closed (a quoted << is not a heredoc, so the hidden line is seen)"
treason $W "echo '<<X'
git push --force origin main
X" "never push"
treason $W "cat <<EOF
never terminated" "heredoc"
treason $W "echo 'abc
x <<X'
git push --force origin main
X" "never push"
treason $W "echo \"abc
x <<X\"
git push --force origin main
X" "never push"
treason $W "cat <<EOF'x
git push --force origin main
EOF
'" "heredoc"
treason $W "cat <<\"EOF\"x
git push --force origin main
EOFx" "heredoc"
treason $W "cat <<END-OF
git push --force origin main
END-OF" "heredoc"
treason $W "foo () { git push --force origin main; }; foo" "parentheses"
treason $W "foo() { git push --force origin main; }; foo" "no shell keywords"
treason $W "function foo { git push; }; foo" "no shell keywords"
t 0 $W "cat <<< 'here string'"
t 0 $W "cp file{,.bak}"
t 0 $W "git commit -m \"feat(x): {y} (z)\""
t 0 $W "echo \"a <<b\""
t 2 $W "trap 'git push' EXIT"
t 2 $W "hash -p /tmp/evil git"
t 2 $W "git fetch --upload-pack=evil origin"
t 2 $W "git ls-remote --exec=evil origin"
treason $W "true # it's
git push --force origin main
# '" "comments"
treason $W "echo \$'a'" "comments"
treason $W "echo 'unterminated" "comments"
t 2 $W "source ./evil.sh"
t 2 $W ". ./evil.sh"
t 2 $W "alias p='git push'"
t 2 $W "git send-pack origin main"
t 2 $W "git remote set-url origin x"
t 0 $W "git remote -v"

echo "# worker: merging, network, hook bypass, branch deletion"
treason $W "gh pr merge 5" "main session"
treason $W "gh api -X PUT repos/o/r/pulls/5/merge" "gh api"
treason $W "curl -s https://example.com" "network"
treason $W "cd /r && wget http://x" "network"
treason $W "git commit --no-verify -m x" "hooks"
treason $W "git commit -n -m x" "hooks"
treason $W "git commit -nm x" "hooks"
treason $W "git commit --no-verif -m x" "hooks"
treason $W "git branch -D x" "force-delete"
treason $W "git branch -fD x" "force-delete"
treason $W "git branch --delete --force x" "force-delete"
treason $W "git branch -d -f x" "force-delete"
t 0 $W "git branch -d merged-branch"

echo "# worker: ordinary work passes (quotes, separators in quotes, redirects, heredocs)"
t 0 $W "npm test"
t 0 $W "npm run build 2>&1 | tail -20"
t 0 $W "CI=true npm test"
t 0 $W "grep env README.md"
t 0 $W "grep -E \"a|b\" file"
t 0 $W "bash tests/run.sh"
t 0 $W "git status"
t 0 $W "git add -A && git commit -m 'feat(scope): add x'"
t 0 $W "git commit -m \"fix: handle a && b\""
t 0 $W "git commit -m \"fix: a; b\""
t 0 $W "git commit -m \"docs: use a|b\""
t 0 $W "git commit -m \"docs: explain --no-verify and git push\""
t 0 $W "git commit -m \"feat: x

for the record, this fixes it.
If it breaks, don't panic (see #1).\""
t 0 $W "git commit -F - <<'EOF'
feat: add x

for the record
if x; then y; fi
EOF"
t 0 $W "cat > notes.txt <<'EOF'
foo() { bar; }
git push origin main
EOF"
t 0 $W "git -C /r/dir status"
t 0 $W "cd /r/wt && composer test && git diff --stat"

echo "# reviewer: read-only allowlist - allowed"
t 0 $R "git diff main...HEAD"
t 0 $R "git diff --stat main...HEAD"
t 0 $R "git diff --output-indicator-new=+ main"
t 0 $R "cd /r/wt && git diff main...HEAD | head -50"
t 0 $R "cd /r/wt && php artisan test --filter Foo"
t 0 $R "npm test"
t 0 $R "npx vitest run"
t 0 $R "./vendor/bin/phpunit"
t 0 $R "php vendor/bin/phpunit --filter X"
t 0 $R "echo x > /dev/null"
t 0 $R "git ls-files 2>&1 | head"
t 0 $R "git ls-files > /dev/null 2>&1"
t 0 $R "grep -rn foo src"
t 0 $R "grep -rn \"->\" src"
t 0 $R "grep -rn \"=>\" src"
t 0 $R "rg \"Foo<Bar>\" src"
t 0 $R "rg \"a|b\" src"
t 0 $R "grep -E \"(a|b)\" f"
t 0 $R "git grep -n --only-matching foo"
t 0 $R "sed -n '1,20p' file.php"
t 0 $R "git branch"
t 0 $R "git branch -a"
t 0 $R "git remote -v"
t 0 $R "bash tests/run.sh"
t 0 $R "FOO=1 git diff"

echo "# reviewer: everything else is denied"
treason $R "git commit -m x" "allowlist"
treason $R "git push" "allowlist"
treason $R "gh pr merge 5" "allowlist"
treason $R "gh pr view 5" "allowlist"
treason $R "git log" "allowlist"
treason $R "git show HEAD" "allowlist"
t 2 $R "rm -rf src"
t 2 $R "bash -c 'git commit -am x'"
t 2 $R "sed -i s/a/b/ file"
t 2 $R "sed -n 'w out.txt' file"
t 2 $R "find . -delete"
t 2 $R "find . -fprint out.txt"
treason $R "echo x > file.txt" "redirection"
treason $R "cat <<'EOF'
x
EOF" "heredocs"
t 2 $R "curl http://x"
t 2 $R "git grep -O vim foo"
t 2 $R "git grep -nOvim foo"
t 2 $R "git grep --open-files-in-pager=vim foo"
t 2 $R "git diff --output=/tmp/x main"
t 2 $R "git diff --outp=x main"
t 2 $R "git diff --out'put'=x main"
t 2 $R "rg --pre ./evil foo"
t 2 $R "rg --pre-glob '*' foo"
t 2 $R "echo x >&2file"
t 2 $R "sed -n 1p -i file"
t 2 $R "sed -n 1p -f script.sed file"
t 2 $R "bash tests/../scripts/evil.sh"
t 0 $R "echo x >&2"
t 2 $R "sort in.txt"
t 2 $R "sort --compress-program=sh in.txt"
t 2 $R "tree -R ."
t 2 $R "find . -fls out.txt"
t 2 $R "tail -f log.txt"
t 2 $R "vendor/bin/evil-script"
t 2 $R "git branch -a -D x"
t 2 $R "git branch --list -D x"
t 2 $R "git branch -vv -m a b"
t 2 $R "git remote -v set-url origin x"
t 2 $R "git remote -v add x y"
t 2 $R "if true; then git diff; fi"
t 2 $R "'git' diff"
t 2 $R "PATH=/tmp/evil git diff"

echo "# main session, empty and malformed input are untouched"
t 0 "" "gh pr merge 5"
t 0 "" "git push --force"
t 0 $W ""
printf 'not json' | bash "$hook" >/dev/null 2>&1
if [ $? = 0 ]; then echo "ok   0  malformed input"; else echo "FAIL malformed input"; fail=1; fi
# Fail open without jq: run with a PATH that has no jq.
nojq=$(mktemp -d)
for b in bash cat printf; do ln -s "$(command -v $b)" "$nojq/$b" 2>/dev/null; done
printf '{"agent_type":"%s","tool_input":{"command":"gh pr merge 5"}}' "$W" | PATH="$nojq" "$(command -v bash)" "$hook" >/dev/null 2>&1
if [ $? = 0 ]; then echo "ok   0  fails open without jq"; else echo "FAIL fail-open without jq"; fail=1; fi
rm -rf "$nojq"

exit $fail
