#!/usr/bin/env bash
# Consistency checks over the skill text, references, hooks and scripts.
# Usage: tests/skill-text.sh
# Prints one line per case and exits non-zero if any case fails.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
skill=$root/skills/youtrack-task
fail=0

ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; shift; printf '%s\n' "$@" | sed 's/^/     | /'; fail=1; }

# 1. One issue-ID regex everywhere (skill, references, SPEC, README, hooks, scripts).
canonical='[A-Z][A-Z0-9_]*-[0-9]+'
q="'"
pat="\\[A-Z\\][^ \`\"|)${q}]*-(\\\\d|\\[0-9\\])\\+"
forms=$(grep -rhoE "$pat" "$root" \
  --exclude-dir=.git --exclude-dir=.worktrees --exclude-dir=tests \
  --exclude=CHANGELOG.md | sort | uniq -c)
others=$(printf '%s\n' "$forms" | grep -vF -- " $canonical" | grep . || true)
if [ -z "$forms" ]; then
  bad "no issue-ID regex found at all (pattern broken?)"
elif [ -n "$others" ]; then
  bad "issue-ID regex differs from $canonical" "$others"
else
  ok "every issue-ID regex is $canonical"
fi

grep -qF 'ISSUE_ID_RE' "$skill/SKILL.md" && ok "SKILL.md defines ISSUE_ID_RE" \
  || bad "SKILL.md does not define ISSUE_ID_RE"

# 2. The canonical regex handles keys with digits and underscores.
for id in P2X-5 YOU-30 A-1 AB_C-12; do
  printf '%s' "$id" | grep -qE "^${canonical}\$" && ok "full-ID match: $id" || bad "full-ID match failed: $id"
done
got=$(printf '%s' 'fix/P2X-5-foo' | grep -oE "$canonical" | head -1)
[ "$got" = "P2X-5" ] && ok "extraction from fix/P2X-5-foo gives P2X-5" || bad "extraction gave '$got', want P2X-5"
for id in x-5 YOU- -5 5; do
  printf '%s' "$id" | grep -qE "^${canonical}\$" && bad "full-ID match accepted: $id" || ok "full-ID match rejects: $id"
done

# 3. <skill-dir> is defined once and every script reference uses it.
grep -qF '<skill-dir>' "$skill/SKILL.md" && ok "SKILL.md defines <skill-dir>" || bad "SKILL.md does not define <skill-dir>"
bare=$(grep -nE '(^|[^/>])scripts/(read-config|setup-workspace|sweep-worktrees|worktree-detach|review-stamp)' \
  "$skill/SKILL.md" "$skill/reference/batch.md" "$skill/reference/review.md" || true)
[ -z "$bare" ] && ok "scripts are always called as <skill-dir>/scripts/<name>" \
  || bad "script path without <skill-dir>" "$bare"
if grep -rn "from this skill's" "$skill/SKILL.md" "$skill/reference" >/dev/null; then
  bad "stale wording \"from this skill's scripts/ directory\" remains" "$(grep -rn "from this skill's" "$skill/SKILL.md" "$skill/reference")"
else
  ok "no 'run it from this skill's scripts/ directory' wording"
fi

# 4. Every script the Scripts section names exists and is executable.
names=$(sed -n '/^## Scripts/,/^## Config/p' "$skill/SKILL.md" | sed -nE 's/^- `([a-z-]+)`.*/\1/p')
[ -n "$names" ] || bad "no scripts listed in the Scripts section"
for n in $names; do
  [ -x "$skill/scripts/$n" ] && ok "script present and executable: $n" || bad "script missing or not executable: $n"
done
for f in "$skill"/scripts/*; do
  n=$(basename "$f")
  printf '%s\n' "$names" | grep -qx "$n" && continue
  bad "script $n is not listed in SKILL.md's Scripts section"
done

# 5. --implement is documented where the flow is.
for f in "$skill/SKILL.md" "$root/README.md" "$root/SPEC.md"; do
  grep -qF -- '--implement' "$f" && ok "--implement documented in $(basename "$f")" || bad "--implement missing in $(basename "$f")"
done

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILURES"
exit "$fail"
