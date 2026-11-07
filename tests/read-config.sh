#!/usr/bin/env bash
# Cases for skills/youtrack-task/scripts/read-config.
# Usage: tests/read-config.sh [path-to-script]
# Prints one line per case and exits non-zero if any case differs from the
# expectation. Uses throwaway config files under a temp dir.
set -u
script=${1:-$(cd "$(dirname "$0")/.." && pwd)/skills/youtrack-task/scripts/read-config}
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# run <config-file> -> sets out
run() { out=$(YOUTRACK_TASK_CONFIG=$1 bash "$script" 2>&1); }

# expect <label> <exact KEY=VALUE line>
expect() {
  if printf '%s\n' "$out" | grep -qxF -- "$2"; then echo "ok   $1"
  else echo "FAIL $1 (want '$2')"; printf '%s\n' "$out" | sed 's/^/     | /'; fail=1; fi
}

run "$tmp/missing.toml"
expect "missing file -> CONFIG_FILE=none"      "CONFIG_FILE=none"
expect "missing file -> confirm default true"  "CONFIRM_BRANCH_NAME=true"
expect "missing file -> worktree auto"         "WORKTREE=auto"
expect "missing file -> clone default"         "WORKTREE_CLONE=node_modules vendor"
expect "missing file -> review rounds 2"       "REVIEW_ROUNDS=2"

cat > "$tmp/user.toml" <<'EOF'
# comment
list_query = "for: me #Unresolved sort by: updated desc"
# confirm_branch_name = true
confirm_branch_name = false   # trailing comment
worktree = "always"
use_superpowers = "always"
worktree_clone = ["node_modules", "vendor", "storage"]
batch_skip_tags = ["manual", "blocked"]
batch_review_rounds = 4
[type_prefix]
Bug = "fix"
EOF
run "$tmp/user.toml"
expect "file present -> CONFIG_FILE"           "CONFIG_FILE=$tmp/user.toml"
expect "bare false is honoured"                "CONFIRM_BRANCH_NAME=false"
expect "commented key is ignored"              "CONFIRM_BRANCH_NAME=false"
expect "quoted scalar"                         "WORKTREE=always"
expect "quoted value with spaces"              "LIST_QUERY=for: me #Unresolved sort by: updated desc"
expect "list is space-separated"               "WORKTREE_CLONE=node_modules vendor storage"
expect "second list"                           "BATCH_SKIP_TAGS=manual blocked"
expect "unset key keeps default"               "REVIEW_GATE_HOOK=off"
expect "alias batch_review_rounds"             "REVIEW_ROUNDS=4"

printf 'review_rounds = 3\nbatch_review_rounds = 4\n' > "$tmp/rounds.toml"
run "$tmp/rounds.toml"
expect "review_rounds beats the alias"         "REVIEW_ROUNDS=3"

printf 'confirm_branch_name = "false"\n' > "$tmp/quoted.toml"
run "$tmp/quoted.toml"
expect "quoted false is honoured"              "CONFIRM_BRANCH_NAME=false"

printf '# confirm_branch_name = false\n' > "$tmp/commented.toml"
run "$tmp/commented.toml"
expect "only a commented key -> default"       "CONFIRM_BRANCH_NAME=true"

printf 'worktree = "off"\n[type_prefix]\nworktree = "always"\nconfirm_branch_name = false\n' > "$tmp/table.toml"
run "$tmp/table.toml"
expect "key in a [table] does not leak"        "CONFIRM_BRANCH_NAME=true"
expect "top-level value wins over [table]"     "WORKTREE=off"

exit $fail
