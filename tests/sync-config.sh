#!/usr/bin/env bash
# Cases for hooks/sync-config.
# Usage: tests/sync-config.sh [path-to-hook]
# Prints one line per case and exits non-zero if any case differs from the
# expectation. Every case runs against a throwaway plugin root, data dir and
# config file under a temp dir; nothing outside it is touched.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
hook=${1:-$root/hooks/sync-config}
fail=0
tmp=$(mktemp -d)
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; [ $# -gt 1 ] && printf '%s\n' "$2" | sed 's/^/     | /'; fail=1; }

# fixture <name> -> sets plugin / data / cfg for a fresh sandbox
fixture() {
  plugin=$tmp/$1/plugin; data=$tmp/$1/data; cfg=$tmp/$1/home/config.toml
  mkdir -p "$plugin/.claude-plugin" "$data" "$tmp/$1/home"
}

# release <version> -- writes plugin.json; the example comes from "$example"
release() {
  printf '{\n  "name": "youtrack-task",\n  "version": "%s"\n}\n' "$1" > "$plugin/.claude-plugin/plugin.json"
  printf '%s\n' "$example" > "$plugin/config.example.toml"
}

# run_hook -> sets out, status
run_hook() {
  out=$(CLAUDE_PLUGIN_ROOT=$plugin CLAUDE_PLUGIN_DATA=$data YOUTRACK_TASK_CONFIG=$cfg bash "$hook" </dev/null 2>&1)
  status=$?
}

has()  { grep -qxF -- "$2" "$1" && ok "$3" || bad "$3 (want line '$2' in $1)" "$(cat "$1" 2>/dev/null)"; }
lacks() { grep -qF -- "$2" "$1" && bad "$3 (unexpected '$2')" "$(cat "$1")" || ok "$3"; }
says() { printf '%s' "$out" | grep -qF -- "$1" && ok "$2" || bad "$2 (want '$1')" "$out"; }
silent() { [ -z "$out" ] && ok "$1" || bad "$1 (got output)" "$out"; }

example_v1='# youtrack-task — optional configuration
#
# Every key is optional.

# Query used to list candidate issues.
# list_query = "for: me"

# State names on your ladder.
# in_progress_state = "In Progress"   # set on pickup
# done_state        = "Done"          # target of done

# Isolate each pickup in a worktree.
# worktree = "auto"

# Branch prefix per Type.
# [type_prefix]
# Bug  = "fix"
# Task = "chore"'

# 1. A missing config is created from the example ------------------------------
fixture fresh; example=$example_v1; release 0.1.0
run_hook
[ "$status" -eq 0 ] && ok "fresh: exit 0" || bad "fresh: exit 0 (got $status)"
cmp -s "$cfg" "$plugin/config.example.toml" && ok "fresh: config equals the example" || bad "fresh: config equals the example" "$(cat "$cfg" 2>/dev/null)"
says "created" "fresh: message says created"
has "$data/config-synced-version" "0.1.0" "fresh: version stamp written"
cmp -s "$data/config.example.snapshot" "$plugin/config.example.toml" && ok "fresh: snapshot written" || bad "fresh: snapshot written"

# 2. Same version: nothing happens, not even a read of the config ---------------
printf '# my own note\nworktree = "always"\n' > "$cfg"
run_hook
silent "same version: no output"
[ "$(cat "$cfg")" = "$(printf '# my own note\nworktree = "always"')" ] && ok "same version: config untouched" || bad "same version: config untouched"

# 3. Update adds missing keys, commented, with their comment; nothing else moves
fixture update; example=$example_v1; release 0.1.0
cat > "$cfg" <<'EOF'
# my own note
list_query = "for: me #Mine"
worktree = "always"
EOF
run_hook   # first run on an existing config: no snapshot yet
example="$example_v1

# Ask before the PR.
# confirm_pr = true"
release 0.2.0
run_hook
says "confirm_pr" "update: message names the added key"
has "$cfg" "# confirm_pr = true" "update: new key appended commented"
has "$cfg" "# Ask before the PR." "update: its comment comes along"
has "$cfg" 'list_query = "for: me #Mine"' "update: user value kept"
has "$cfg" 'worktree = "always"' "update: second user value kept"
has "$cfg" "# my own note" "update: user comment kept"
[ "$(grep -c 'worktree = "auto"' "$cfg")" -eq 0 ] && ok "update: present key is not added again" || bad "update: present key is not added again" "$(cat "$cfg")"
[ -f "$cfg.bak" ] && ok "update: backup written" || bad "update: backup written"
has "$data/config-synced-version" "0.2.0" "update: version stamp moved"

# 4. Idempotent: a new version with an unchanged example changes nothing --------
before=$(cat "$cfg"); bak_before=$(cat "$cfg.bak")
release 0.3.0
run_hook
silent "idempotent: no output"
[ "$(cat "$cfg")" = "$before" ] && ok "idempotent: config unchanged" || bad "idempotent: config unchanged" "$(cat "$cfg")"
[ "$(cat "$cfg.bak")" = "$bak_before" ] && ok "idempotent: backup not rewritten" || bad "idempotent: backup not rewritten"
has "$data/config-synced-version" "0.3.0" "idempotent: stamp still moves"

# 5. A key dropped from the example is removed, with its own comment only ------
fixture remove
example="# header

# Old thing.
# old_key = 1

# Kept thing.
# kept_key = 2"
release 1.0.0
cat > "$cfg" <<'EOF'
# my own note about old_key
# Old thing.
old_key = 5
# Old thing.
# old_key = 1

# Kept thing.
kept_key = 7
my_key = 9
EOF
run_hook                      # no snapshot yet: nothing may be removed
has "$cfg" "old_key = 5" "no snapshot: nothing removed"
example="# header

# Kept thing.
# kept_key = 2"
release 1.1.0
run_hook
says "old_key" "remove: message names the removed key"
lacks "$cfg" "old_key = 5" "remove: active line gone"
lacks "$cfg" "# old_key = 1" "remove: commented line gone"
lacks "$cfg" "# Old thing." "remove: its comment gone"
has "$cfg" "# my own note about old_key" "remove: user's own comment kept"
has "$cfg" "kept_key = 7" "remove: kept key keeps the user value"
has "$cfg" "my_key = 9" "remove: user's own key kept"
grep -qxF "old_key = 5" "$cfg.bak" && ok "remove: backup still has the old value" || bad "remove: backup still has the old value"

# 6. The [type_prefix] table ----------------------------------------------------
fixture table; example=$example_v1; release 0.1.0
printf 'worktree = "always"\n' > "$cfg"
run_hook
[ "$(grep -c 'type_prefix' "$cfg")" -eq 1 ] && ok "table: missing block appended once" || bad "table: missing block appended once" "$(cat "$cfg")"
has "$cfg" '# Bug  = "fix"' "table: block carries its rows"
fixture table2; example=$example_v1; release 0.1.0
printf '[type_prefix]\nBug = "feat"\n' > "$cfg"
run_hook
lacks "$cfg" "# Bug" "table: an existing table is left alone"

# 7. The real example: complete on creation, stable on re-run -------------------
fixture real; example=$(cat "$root/config.example.toml"); release 9.0.0
run_hook
cmp -s "$cfg" "$plugin/config.example.toml" && ok "real example: created verbatim" || bad "real example: created verbatim"
release 9.0.1
run_hook
silent "real example: every key is recognised as present"
cmp -s "$cfg" "$plugin/config.example.toml" && ok "real example: re-run changes nothing" || bad "real example: re-run changes nothing"

# 8. Not writable: warn, exit 0, no stamp so the next session retries ----------
if [ "$(id -u)" -ne 0 ]; then
  fixture ro; example=$example_v1; release 0.1.0
  chmod 555 "$tmp/ro/home"
  run_hook
  [ "$status" -eq 0 ] && ok "read-only dir: exit 0" || bad "read-only dir: exit 0 (got $status)"
  says "could not" "read-only dir: warning shown"
  [ ! -e "$data/config-synced-version" ] && ok "read-only dir: no stamp written" || bad "read-only dir: no stamp written"
  chmod 755 "$tmp/ro/home"
  run_hook
  [ -f "$cfg" ] && ok "read-only dir: next run succeeds" || bad "read-only dir: next run succeeds"
else
  echo "skip read-only cases (running as root)"
fi

# 9. A broken plugin root never breaks the session -----------------------------
fixture broken; example=$example_v1; release 0.1.0; rm "$plugin/config.example.toml"
run_hook
[ "$status" -eq 0 ] && ok "missing example: exit 0" || bad "missing example: exit 0 (got $status)"
[ ! -e "$cfg" ] && ok "missing example: no config invented" || bad "missing example: no config invented"

exit $fail
