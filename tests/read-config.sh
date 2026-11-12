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
expect "missing file -> confirm_pr default true" "CONFIRM_PR=true"
expect "missing file -> worktree auto"         "WORKTREE=auto"
expect "missing file -> clone default"         "WORKTREE_CLONE=node_modules vendor"
expect "missing file -> review rounds 2"       "REVIEW_ROUNDS=2"
expect "missing file -> batch_query not state-bound" "BATCH_QUERY=for: me #Unresolved sort by: updated desc"

cat > "$tmp/user.toml" <<'EOF'
# comment
list_query = "for: me #Unresolved sort by: updated desc"
# confirm_branch_name = true
confirm_branch_name = false   # trailing comment
# confirm_pr = true
confirm_pr = false            # trailing comment
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
expect "confirm_pr false is honoured"          "CONFIRM_PR=false"
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

printf 'confirm_pr = "false"\n' > "$tmp/pr-quoted.toml"
run "$tmp/pr-quoted.toml"
expect "confirm_pr quoted false is honoured"   "CONFIRM_PR=false"
expect "confirm_pr is independent of branch"   "CONFIRM_BRANCH_NAME=true"

printf '# confirm_pr = false\n' > "$tmp/pr-commented.toml"
run "$tmp/pr-commented.toml"
expect "confirm_pr only commented -> default"  "CONFIRM_PR=true"

printf '[type_prefix]\nconfirm_pr = false\n' > "$tmp/pr-table.toml"
run "$tmp/pr-table.toml"
expect "confirm_pr in a [table] does not leak" "CONFIRM_PR=true"

# --- every remaining key: default without a file, then a set value -----------
run "$tmp/missing.toml"
expect "default in_progress_state"             "IN_PROGRESS_STATE=In Progress"
expect "default testing_state"                 "TESTING_STATE=Testing"
expect "default done_state"                    "DONE_STATE=Done"
expect "default local_plan_copy"               "LOCAL_PLAN_COPY=auto"
expect "default default_new_type is empty"     "DEFAULT_NEW_TYPE="
expect "default use_superpowers"               "USE_SUPERPOWERS=auto"
expect "default review_before_pr"              "REVIEW_BEFORE_PR=always"
expect "default review_gate_hook"              "REVIEW_GATE_HOOK=off"
expect "default worktree_dir"                  "WORKTREE_DIR=.worktrees"
expect "default worktree_link"                 "WORKTREE_LINK=.env"
expect "default batch_max_parallel"            "BATCH_MAX_PARALLEL=3"
expect "default batch_skip_tags"               "BATCH_SKIP_TAGS=manual"

cat > "$tmp/all-keys.toml" <<'EOF'
in_progress_state = "Doing"
testing_state = "In Review"
done_state = Closed          # bare value with a trailing comment
local_plan_copy = "always"
default_new_type = "Task"
review_before_pr = "never"
review_gate_hook = "on"
worktree_dir = ".trees"
worktree_link = [".env", ".env.local", "config/secrets.php"]   # linked, not copied
batch_max_parallel = 5
EOF
run "$tmp/all-keys.toml"
expect "set in_progress_state (with a space)"  "IN_PROGRESS_STATE=Doing"
expect "set testing_state (with a space)"      "TESTING_STATE=In Review"
expect "set done_state, bare + comment"        "DONE_STATE=Closed"
expect "set local_plan_copy"                   "LOCAL_PLAN_COPY=always"
expect "set default_new_type"                  "DEFAULT_NEW_TYPE=Task"
expect "set review_before_pr"                  "REVIEW_BEFORE_PR=never"
expect "set review_gate_hook"                  "REVIEW_GATE_HOOK=on"
expect "set worktree_dir"                      "WORKTREE_DIR=.trees"
expect "list with several entries + comment"  "WORKTREE_LINK=.env .env.local config/secrets.php"
expect "set batch_max_parallel (bare number)"  "BATCH_MAX_PARALLEL=5"

# Same-named keys in a [table] must not leak for any of the new keys.
printf '[type_prefix]\nin_progress_state = "X"\ntesting_state = "X"\ndone_state = "X"\nworktree_dir = "x"\nworktree_link = ["x"]\nbatch_max_parallel = 9\n' > "$tmp/table-all.toml"
run "$tmp/table-all.toml"
expect "[table] in_progress_state does not leak" "IN_PROGRESS_STATE=In Progress"
expect "[table] testing_state does not leak"     "TESTING_STATE=Testing"
expect "[table] done_state does not leak"        "DONE_STATE=Done"
expect "[table] worktree_dir does not leak"      "WORKTREE_DIR=.worktrees"
expect "[table] worktree_link does not leak"     "WORKTREE_LINK=.env"
expect "[table] batch_max_parallel does not leak" "BATCH_MAX_PARALLEL=3"

# --- reviewer_commands: whole commands (spaces and commas inside), joined with ";" -----
run "$tmp/missing.toml"
expect "missing file -> reviewer_commands empty" "REVIEWER_COMMANDS="

cat > "$tmp/reviewer.toml" <<'EOF'
reviewer_commands = ["ddev exec vendor/bin/pest", "swift test --filter A,B", "npm run build"]   # trailing comment
EOF
run "$tmp/reviewer.toml"
expect "reviewer_commands keeps spaces and commas inside an entry" \
  "REVIEWER_COMMANDS=ddev exec vendor/bin/pest;swift test --filter A,B;npm run build"

cat > "$tmp/reviewer-table.toml" <<'EOF'
worktree = "always"
[type_prefix]
reviewer_commands = ["curl evil"]
EOF
run "$tmp/reviewer-table.toml"
expect "[table] reviewer_commands does not leak" "REVIEWER_COMMANDS="

cat > "$tmp/reviewer-empty.toml" <<'EOF'
reviewer_commands = []
EOF
run "$tmp/reviewer-empty.toml"
expect "empty reviewer_commands list" "REVIEWER_COMMANDS="

# --- single-key mode: `read-config <key>` prints only the resolved value ----------
get() { out=$(YOUTRACK_TASK_CONFIG=$1 bash "$script" "$2" 2>&1); rc=$?; }
expect_get() { # <label> <config> <key> <want>
  get "$2" "$3"
  if [ "$rc" = 0 ] && [ "$out" = "$4" ]; then echo "ok   $1"
  else echo "FAIL $1 (want '$4', got '$out', rc=$rc)"; fail=1; fi
}
expect_get "key mode: default when the file is missing" "$tmp/missing.toml" worktree_dir ".worktrees"
expect_get "key mode: configured scalar"              "$tmp/all-keys.toml" review_gate_hook "on"
expect_get "key mode: list value"                     "$tmp/all-keys.toml" worktree_link ".env .env.local config/secrets.php"
expect_get "key mode: [table] key is ignored"         "$tmp/table-all.toml" worktree_dir ".worktrees"
expect_get "key mode: key is case-insensitive"        "$tmp/all-keys.toml" WORKTREE_DIR ".trees"
expect_get "key mode: review_rounds alias resolved"   "$tmp/missing.toml" review_rounds "2"
get "$tmp/missing.toml" no_such_key
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q '^ERROR='; then echo "ok   key mode: unknown key -> ERROR, exit 2"
else echo "FAIL key mode: unknown key (rc=$rc, out='$out')"; fail=1; fi

exit $fail
