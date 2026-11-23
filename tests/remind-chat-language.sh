#!/usr/bin/env bash
# Cases for hooks/remind-chat-language.
# Usage: tests/remind-chat-language.sh [path-to-hook]
# Prints one line per case and exits non-zero if any case differs from the
# expectation.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
hook=${1:-$root/hooks/remind-chat-language}
fail=0

ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; [ $# -gt 1 ] && printf '%s\n' "$2" | sed 's/^/     | /'; fail=1; }

[ -x "$hook" ] && ok "hook is executable" || bad "hook is missing or not executable: $hook"

out=$(bash "$hook" </dev/null 2>&1)
status=$?
[ "$status" = 0 ] && ok "exits 0" || bad "exit status $status, want 0" "$out"

printf '%s' "$out" | grep -qF '→ Chat language:' \
  && ok "points at the printed '→ Chat language:' line" \
  || bad "reminder does not mention the '→ Chat language:' line" "$out"
printf '%s' "$out" | grep -qiE 'not a user message' \
  && ok "says the compaction summary is not a user message" \
  || bad "reminder does not say the summary is not a user message" "$out"
printf '%s' "$out" | grep -qiE 'claude-mem|plugin' \
  && ok "covers notices relayed from hooks and plugins" \
  || bad "reminder does not cover relayed hook / plugin notices" "$out"
printf '%s' "$out" | grep -qF '/youtrack-task' \
  && ok "scoped to sessions that used /youtrack-task" \
  || bad "reminder is not scoped to /youtrack-task sessions" "$out"

# hooks.json registers it for SessionStart on compaction only.
reg=$(sed -n '/"SessionStart"/,/"PreToolUse"/p' "$root/hooks/hooks.json")
printf '%s' "$reg" | grep -qF 'remind-chat-language' \
  && ok "hooks.json registers remind-chat-language under SessionStart" \
  || bad "hooks.json does not register remind-chat-language under SessionStart"
compact=$(printf '%s' "$reg" | grep -B4 'remind-chat-language' | grep -F '"matcher"')
printf '%s' "$compact" | grep -qF '"compact"' \
  && ok "remind-chat-language runs on the compact matcher only" \
  || bad "remind-chat-language is not bound to the compact matcher" "$compact"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILURES"
exit "$fail"
