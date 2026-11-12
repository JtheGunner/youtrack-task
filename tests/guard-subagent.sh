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
treason $W "cat <<\"EOF'
x
EOF" "heredoc"
treason $W "cat <<'EOF\"
git push --force origin main
EOF" "heredoc"
treason $W "cat <<EOF \${X:-\"}
git push --force origin main
EOF" "heredoc"
t 0 $W "cat > f.txt <<'EOF'
plain body
EOF"
t 0 $W "cat <<\"EOF\" | grep x
plain body
EOF"
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
t 0 $R "./gradlew test"
t 0 $R "gradle test"
t 0 $R "./gradlew :feature:play:testDebugUnitTest"
t 0 $R "./gradlew testDebugUnitTest lint"
t 0 $R "./gradlew --no-daemon --offline test"
t 0 $R "./gradlew :app:testDebugUnitTest --tests com.example.FooTest"
t 0 $R "./gradlew check -x lint"
t 0 $R "./gradlew detekt ktlintCheck"
t 0 $R "cd /r/wt && ./gradlew lintDebug 2>&1 | tail -30"

echo "# reviewer: built-in verification commands (swift, go build, golangci-lint, scripts/test*)"
t 0 $R "swift test"
t 0 $R "swift test --filter FooTests"
t 0 $R "swift build"
t 0 $R "go build ./..."
t 0 $R "golangci-lint run"
t 0 $R "golangci-lint run ./..."
t 0 $R "bash scripts/test.sh"
t 0 $R "./scripts/test.sh"
t 0 $R "sh scripts/run-tests.sh"
t 0 $R "cd /r/wt && swift test 2>&1 | tail -30"

echo "# reviewer: build / lint commands that could write or steer the build stay denied"
t 2 $R "golangci-lint run --fix"
t 2 $R "golangci-lint run --fix ./..."
t 2 $R "golangci-lint cache clean"
t 2 $R "golangci-lint run --out-format=json:evil"
t 2 $R "go build -o /tmp/x ./..."
t 2 $R "go build -toolexec=/tmp/evil ./..."
t 2 $R "go build -ldflags=-X=main.x=1 ./..."
t 2 $R "go install ./..."
t 2 $R "swift build -Xswiftc -DX"
t 2 $R "swift build --package-path /tmp/other"
t 2 $R "swift package update"
t 2 $R "swift run evil"
t 2 $R "./scripts/test.sh; rm -rf x"
t 2 $R "bash scripts/test.sh > out.txt"
t 2 $R "bash scripts/../evil.sh"
t 2 $R "bash scripts/deploy.sh"
treason $R "swift package update" "[blocked-by-guard]"

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
t 2 $R "./gradlew assembleDebug"
t 2 $R "./gradlew test publish"
t 2 $R "./gradlew clean test"
t 2 $R "./gradlew"
t 2 $R "./gradlew test -I evil.gradle"
t 2 $R "./gradlew test --init-script evil.gradle"
t 2 $R "./gradlew test -b other.gradle"
t 2 $R "./gradlew test --continuous"
t 2 $R "./gradlew test --tests"
t 2 $R "./gradlew :app:installDebug"
t 2 $R "./gradlew lintFix"
t 2 $R "./gradlew :app:detektBaseline"
t 2 $R "./gradlew detektGenerateConfig"
t 2 $R "./gradlew checkFormat"
t 2 $R "./gradlew ktlintFormat"
t 2 $R "./gradlew updateLintBaseline"
t 2 $R "./gradlew test -Dorg.gradle.jvmargs=-Xmx1g"
t 2 $R "./gradlew test -Dgradle.user.home=/tmp/x"
t 2 $R "./gradlew test -g /tmp/home"
t 2 $R "./gradlew test --gradle-user-home /tmp/home"
t 2 $R "./gradlew test --project-dir /tmp/x"
t 2 $R "GRADLE_OPTS=-javaagent:/tmp/a.jar ./gradlew test"
t 2 $R "JAVA_TOOL_OPTIONS=-javaagent:/tmp/a.jar ./gradlew test"
t 2 $R "ORG_GRADLE_PROJECT_x=1 ./gradlew test"
t 2 $R "./gradlew test --tests *"
t 2 $R "./gradlew test --tests=*"
t 2 $R "./gradlew test -x l?nt"
t 2 $R "./gradlew test --tests [a-z]*"
t 2 $R "./gradlew test *"
t 2 $R "./gradlew test -Pci=true"
t 2 $R "./gradlew test -Porg.gradle.java.home=/tmp/jdk"
t 2 $R "./gradlew lintF"
t 2 $R "./gradlew :app:lintFDebug"
t 2 $R "./gradlew lintFixDebug"
t 2 $R "./gradlew checkF"
t 2 $R "./gradlew testD"
t 2 $R "./gradlew lintVitalAnalyzeRelease"
t 2 $R "./gradlew LINTFIX"
t 2 $R "./gradlew :app:testDebugUnitTestFix"
t 2 $R "./gradlew check -x"
t 2 $R "./gradlew check -x -I"
t 2 $R "./gradlew check -x ../evil"
t 2 $R "./gradlew testUpdate"
t 2 $R "./gradlew testDeploy"
t 2 $R "./gradlew lintReset"
t 2 $R "./gradlew testRecord"
t 2 $R "./gradlew checkSync"
t 2 $R "./gradlew :app:testDebugUnitTest -Proborazzi.test.record=true"
t 2 $R "./gradlew test --tests=-I"
treason $R $'./gradlew test \\\ngrep -I /repo/evil.gradle' "line continuations"
treason $R $'./gradlew test \\\ngrep -Dorg.gradle.jvmargs=x f' "line continuations"
treason $R $'git diff \\\n--output=/tmp/x' "line continuations"
t 2 $R "ANDROID_HOME=/tmp/sdk ./gradlew test"
t 2 $R "KOTLIN_COMPILER_ARGS=x ./gradlew test"
t 2 $R "JDK_JAVAC_OPTIONS=x ./gradlew test"
t 2 $R "TMPDIR=/tmp/x ./gradlew test"
t 0 $R $'./gradlew test\ngit diff'

echo "# worker: history rewriting and destructive git commands are denied"
treason $W "git commit --amend -m x" "history"
treason $W "git commit --amend --no-edit" "history"
treason $W "git commit -m x --amend" "history"
treason $W "git reset --hard HEAD~1" "history"
treason $W "git reset --hard" "history"
treason $W "git clean -fdx" "history"
treason $W "git clean -n" "history"
treason $W "git rebase main" "history"
treason $W "git rebase -i HEAD~3" "history"
treason $W "git update-ref -d refs/heads/x" "history"
treason $W "git filter-branch --tree-filter x" "history"
treason $W "git worktree remove --force /r/wt" "history"
treason $W "git worktree remove -f /r/wt" "history"
treason $W "git worktree remove /r/wt --force" "history"
treason $W "cd /r/wt && git reset --hard origin/main" "history"
treason $W "git worktree remove -ff /r/wt" "history"
treason $W "git worktree remove --forc /r/wt" "history"
treason $W "git commit --amen -m x" "history"
treason $W "git commit --am --no-edit" "history"
treason $W "git reset --har HEAD~1" "history"
treason $W "git -C /r/wt clean -fd" "history"

echo "# worker: the base refs the reviewer trusts cannot be repointed"
treason $W "git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/evil" "base refs"
treason $W "git symbolic-ref -d refs/remotes/origin/HEAD" "base refs"
treason $W "git remote set-head origin evil" "base refs"
treason $W "git branch -f main HEAD" "base refs"
treason $W "git branch -M main" "base refs"
treason $W "git branch --move main other" "base refs"
treason $W "git branch --copy main other" "base refs"
treason $W "git symbolic-ref -m x refs/remotes/origin/HEAD refs/remotes/origin/evil" "base refs"
treason $W "git symbolic-ref --quiet refs/remotes/origin/HEAD refs/remotes/origin/evil" "base refs"
treason $W "git replace abc123 def456" "base refs"
treason $W "git fetch origin evil:refs/heads/main" "base refs"
treason $W "git fetch origin +refs/heads/x:refs/remotes/origin/main" "base refs"
treason $W "git checkout -B main" "base refs"
treason $W "git switch -C main" "base refs"
treason $W "git switch --force-create main" "base refs"
treason $W "git branch --forc main HEAD" "base refs"
treason $W "git branch --mov main other" "base refs"
treason $W "git branch --cop main other" "base refs"
t 0 $W "git fetch origin"
t 0 $W "git checkout -b feat/ABC-1-x"
t 0 $W "git switch -c feat/ABC-1-x"
t 0 $W "git switch feat/ABC-1-x"
t 0 $W "git branch --contains HEAD"
t 0 $W "git symbolic-ref HEAD"
t 0 $W "git symbolic-ref --short HEAD"
t 0 $W "git branch --show-current"
t 0 $W "git branch -a"
t 0 $W "git branch -vv"
t 0 $W "git branch feat/ABC-1-x"
t 0 $W "git remote -v"

echo "# worker: ordinary local git stays allowed"
t 0 $W "git commit -m 'amend the docs'"
t 0 $W "git commit -m 'reset --hard is blocked' -m body"
t 0 $W "git reset --soft HEAD~1"
t 0 $W "git reset HEAD file.txt"
t 0 $W "git restore file.txt"
t 0 $W "git merge main"
t 0 $W "git worktree add /r/wt2 -b x"
t 0 $W "git worktree list"
t 0 $W "git worktree remove /r/wt"
t 0 $W "git commit --allow-empty -m x"
t 0 $W "git commit --author='A <a@b.c>' -m x"
t 0 $W "git reset --mixed HEAD~1"
t 0 $W "git stash list"

echo "# worker: gh verbs that write outside the branch are denied"
treason $W "gh repo delete owner/name --yes" "gh"
treason $W "gh repo create x" "gh"
treason $W "gh release create v1.0.0" "gh"
treason $W "gh secret set TOKEN" "gh"
treason $W "gh pr create --title x" "pull requests"
treason $W "cd /r/wt && gh pr create --fill" "pull requests"
t 0 $W "gh pr view 5"
t 0 $W "gh pr checks 5"
t 0 $W "gh run list"

# ---- file tools (Edit / Write / MultiEdit) ---------------------------------
# Fixture: a repo with two linked worktrees, a symlink out of one of them, and a
# directory that is not a git repo. mktemp is resolved with pwd -P (macOS /var).
fx=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$fx"' EXIT
main=$fx/repo; wt=$main/.worktrees/YOU-1-a; wt2=$main/.worktrees/YOU-2-b
mkdir -p "$main" "$fx/outside" "$fx/plain"
git -C "$main" init -q -b main && git -C "$main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$main" worktree add -q -b b1 "$wt" && git -C "$main" worktree add -q -b b2 "$wt2"
ln -s "$fx/outside" "$wt/escape"

# tf <expected-exit> <agent or ""> <tool> <file_path> <cwd> [stderr-substring]
tf() {
  local exp=$1 agent=$2 tool=$3 file=$4 cwd=$5 want=${6:-} json err got
  json=$(jq -nc --arg a "$agent" --arg t "$tool" --arg f "$file" --arg w "$cwd" \
    '(if $a != "" then {agent_type:$a} else {} end) + {tool_name:$t,cwd:$w,tool_input:{file_path:$f}}')
  err=$(printf '%s' "$json" | bash "$hook" 2>&1 >/dev/null); got=$?
  if [ "$got" = "$exp" ] && { [ -z "$want" ] || printf '%s' "$err" | grep -qF -- "$want"; }; then
    echo "ok   $exp  [${agent##*:}] $tool ${file#"$fx"/} (cwd ${cwd#"$fx"/})${want:+ reason '$want'}"
  else echo "FAIL want $exp${want:+ '$want'} got $got ($err) [${agent##*:}] $tool $file (cwd $cwd)"; fail=1; fi
}

echo "# worker: file tools stay inside the worktree"
tf 0 $W Write "$wt/src/new.txt" "$wt"
tf 0 $W Edit "$wt/README.md" "$wt"
tf 0 $W MultiEdit "$wt/src/a/b.txt" "$wt"
tf 0 $W Write "src/rel.txt" "$wt"
tf 0 $W Write "$wt/.github/workflows/ci.yaml" "$wt"
tf 0 $W Write "$wt/.gitignore" "$wt"
tf 2 $W Write "$main/README.md" "$wt" "outside"
tf 2 $W Edit "$fx/outside/x" "$wt" "outside"
tf 2 $W MultiEdit "$HOME/.config/youtrack-task/config.toml" "$wt" "outside"
tf 2 $W Write "../rel-escape.txt" "$wt" "outside"
tf 2 $W Write "$wt/sub/../../escape.txt" "$wt" "outside"
tf 2 $W Write "$wt2/x" "$wt" "outside"
tf 2 $W Write "$wt/escape/x" "$wt" "outside"
mkdir -p "$wt-evil"
tf 2 $W Write "$wt-evil/x" "$wt" "outside"

echo "# worker: anything under .git is denied"
tf 2 $W Write "$wt/.git" "$wt" ".git"
tf 2 $W Write "$main/.git/hooks/pre-commit" "$wt" ".git"
tf 2 $W Edit "$wt/.git/hooks/post-commit" "$wt" ".git"
tf 2 $W Write "$wt/sub/../.git/config" "$wt" ".git"
tf 2 $W Write "$wt/.git/x" "$fx/plain" ".git"
tf 2 $W Write "$wt/.GIT/hooks/pre-commit" "$wt" ".git"
tf 2 $W Edit "$wt/sub/.Git/config" "$wt" ".git"

echo "# worker started in the main checkout: only linked worktrees are writable"
tf 0 $W Write "$wt/a.txt" "$main"
tf 0 $W Write "$wt2/a.txt" "$main"
tf 2 $W Write "$main/README.md" "$main" "outside"
tf 2 $W Write "$main/.worktrees/other/x" "$main" "outside"
tf 2 $W Edit "$HOME/.config/youtrack-task/config.toml" "$main" "outside"

echo "# worker without a git repo around: only the .git rule applies (best effort)"
tf 0 $W Write "$fx/plain/x" "$fx/plain"

echo "# file tools: main session, reviewer and incomplete input are untouched"
tf 0 "" Write "$main/README.md" "$wt"
tf 0 "" Edit "$wt/.git/hooks/x" "$wt"
tf 0 $R Write "$main/README.md" "$wt"
tf 0 $W Write "" "$wt"
printf '{"agent_type":"%s","tool_name":"Write","cwd":"%s","tool_input":{}}' "$W" "$wt" | bash "$hook" >/dev/null 2>&1
if [ $? = 0 ]; then echo "ok   0  file tool without file_path"; else echo "FAIL file tool without file_path"; fail=1; fi

echo "# main session, empty and malformed input are untouched"
t 0 "" "gh pr merge 5"
t 0 "" "git push --force"
t 0 $W ""
printf 'not json' | bash "$hook" >/dev/null 2>&1
if [ $? = 0 ]; then echo "ok   0  malformed input"; else echo "FAIL malformed input"; fail=1; fi
# ---- reviewer: extra commands from the user config and the base branch ------------
# Fixture: `main` carries .youtrack-task/reviewer-commands; the branch under review
# adds more entries to that file, which must have no effect.
rv=$fx/rv
mkdir -p "$rv/.youtrack-task"
git -C "$rv" init -q -b main
printf '%s\n' '# project verification commands' 'ddev exec vendor/bin/pest' '' 'make verify' 'bash ci/check.sh --fast' \
  > "$rv/.youtrack-task/reviewer-commands"
git -C "$rv" add . && git -C "$rv" -c user.name=t -c user.email=t@t commit -q -m base
git -C "$rv" switch -q -c feat/RV-1-x
printf '%s\n' 'ddev exec vendor/bin/pest' 'evil-tool --now' >> "$rv/.youtrack-task/reviewer-commands"
git -C "$rv" -c user.name=t -c user.email=t@t commit -q -am 'branch adds evil-tool'
# Ref shadowing: tags named like the base branch resolve before branches and remote refs
# when a short name is used. They point at the branch commit, which lists evil-tool.
git -C "$rv" tag main HEAD && git -C "$rv" tag master HEAD && git -C "$rv" tag origin/main HEAD
# Replace refs: `git replace` swaps an object for another one in every plain lookup, so the
# base commit would read as the branch tip (which lists evil-tool). The hook must ignore them.
git -C "$rv" replace "$(git -C "$rv" rev-list --max-parents=0 refs/heads/main)" HEAD
printf 'reviewer_commands = ["npm run build:ci", "docker compose run app lint,fast"]\n' > "$fx/reviewer-config.toml"

# tx <expected-exit> <command> <cwd> <config-file> [stderr-substring]
tx() {
  local exp=$1 cmd=$2 cwd=$3 cfg=$4 want=${5:-} json err got
  json=$(jq -nc --arg a "$R" --arg c "$cmd" --arg w "$cwd" '{agent_type:$a,tool_name:"Bash",cwd:$w,tool_input:{command:$c}}')
  err=$(printf '%s' "$json" | YOUTRACK_TASK_CONFIG=$cfg bash "$hook" 2>&1 >/dev/null); got=$?
  if [ "$got" = "$exp" ] && { [ -z "$want" ] || printf '%s' "$err" | grep -qF -- "$want"; }; then
    echo "ok   $exp  [extra] $(printf '%s' "$cmd" | head -c 80 | tr '\n' ' ')${want:+ reason '$want'}"
  else echo "FAIL want $exp${want:+ '$want'} got $got ($err) [extra] $cmd"; fail=1; fi
}
none=$fx/no-config.toml

echo "# reviewer: commands from the user config (exact match only)"
tx 0 "npm run build:ci" "$rv" "$fx/reviewer-config.toml"
tx 0 "docker compose run app lint,fast" "$rv" "$fx/reviewer-config.toml"
tx 0 "cd $rv && npm run build:ci 2>&1 | tail -20" "$rv" "$fx/reviewer-config.toml"
tx 2 "npm run build:ci --extra" "$rv" "$fx/reviewer-config.toml" "[blocked-by-guard]"
tx 2 "npm run build" "$rv" "$fx/reviewer-config.toml" "[blocked-by-guard]"
tx 2 "npm run build:ci; rm -rf x" "$rv" "$fx/reviewer-config.toml"
tx 2 "npm run build:ci > out.txt" "$rv" "$fx/reviewer-config.toml"
tx 2 "npm run build:ci && curl http://x" "$rv" "$fx/reviewer-config.toml" "[blocked-by-guard]"
tx 2 "npm run build:ci" "$rv" "$none" "[blocked-by-guard]"

echo "# reviewer: commands from .youtrack-task/reviewer-commands on the base branch"
tx 0 "ddev exec vendor/bin/pest" "$rv" "$none"
tx 0 "make verify" "$rv" "$none"
tx 0 "bash ci/check.sh --fast" "$rv" "$none"
tx 0 "cd $rv && make verify 2>&1 | tail" "$rv" "$none"
tx 2 "make verify-all" "$rv" "$none" "[blocked-by-guard]"
tx 2 "bash ci/check.sh" "$rv" "$none" "[blocked-by-guard]"
tx 2 "make verify > out.txt" "$rv" "$none"

echo "# reviewer: the branch under review cannot allow itself (the file is read from the base branch)"
tx 2 "evil-tool --now" "$rv" "$none" "[blocked-by-guard]"
tx 2 "evil-tool --now" "$rv" "$fx/reviewer-config.toml" "[blocked-by-guard]"
# ... also not through a tag named main / master / origin/main (full ref names are used)
tx 0 "make verify" "$rv" "$none"
tx 2 "make verify-evil" "$rv" "$none" "[blocked-by-guard]"

echo "# reviewer: no base branch file, no repo, or a comment line -> built-in and user config only"
mkdir -p "$fx/rv-empty" && git -C "$fx/rv-empty" init -q -b main && git -C "$fx/rv-empty" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
tx 2 "make verify" "$fx/rv-empty" "$none" "[blocked-by-guard]"
tx 0 "npm run build:ci" "$fx/rv-empty" "$fx/reviewer-config.toml"
tx 2 "make verify" "$fx/plain" "$none" "[blocked-by-guard]"
tx 2 "project verification commands" "$rv" "$none" "[blocked-by-guard]"
tx 0 "git diff main...HEAD" "$rv" "$none"

# Fail open without jq: run with a PATH that has no jq.
nojq=$(mktemp -d)
for b in bash cat printf; do ln -s "$(command -v $b)" "$nojq/$b" 2>/dev/null; done
nojq_err=$(printf '{"agent_type":"%s","tool_input":{"command":"gh pr merge 5"}}' "$W" | PATH="$nojq" "$(command -v bash)" "$hook" 2>&1 >/dev/null); nojq_rc=$?
if [ "$nojq_rc" = 0 ] && printf '%s' "$nojq_err" | grep -qi 'jq'; then echo "ok   0  without jq: passes and warns on stderr"; else echo "FAIL without jq: rc=$nojq_rc stderr='$nojq_err'"; fail=1; fi
rm -rf "$nojq"

exit $fail
