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

# 6. SKILL.md stays small and loads only what the invocation needs.
# The target is about 350 lines; the Guardrails, Language, Config table and the
# primary flow have to stay whole, so there is a little headroom.
max_lines=375
lines=$(wc -l < "$skill/SKILL.md" | tr -d ' ')
[ "$lines" -le "$max_lines" ] && ok "SKILL.md has $lines lines (max $max_lines)" \
  || bad "SKILL.md has $lines lines, max $max_lines"

desc=$(sed -n '2,/^---$/p' "$skill/SKILL.md" | sed -n 's/^description: //p')
[ -n "$desc" ] || bad "SKILL.md has no one-line description in its frontmatter"
[ "${#desc}" -lt 500 ] && ok "description has ${#desc} characters (max 499)" \
  || bad "description has ${#desc} characters, max 499"
printf '%s' "$desc" | grep -qi 'fetches the issue' \
  && bad "description summarises the workflow (triggers only)" || ok "description lists triggers only"

# Every reference file SKILL.md names exists.
refs=$(grep -oE 'reference/[a-z-]+\.md' "$skill/SKILL.md" | sort -u)
for r in $refs; do
  [ -f "$skill/$r" ] && ok "referenced file exists: $r" || bad "SKILL.md names a missing file: $r"
done

# Every Dispatch row (except the primary flow) names the reference file to read first.
dispatch=$(sed -n '/^## Dispatch on the first argument/,/^\*\*Every invocation/p' "$skill/SKILL.md" \
  | grep -E '^\| `(new|comment|log|pr|link|testing|done|worktree|all)`')
for cmd in new comment log pr link testing 'done' worktree all; do
  row=$(printf '%s\n' "$dispatch" | grep -E "^\| \`$cmd\` ")
  if printf '%s' "$row" | grep -qE 'read `reference/[a-z-]+\.md` before acting'; then
    ok "dispatch row '$cmd' says to read its reference file first"
  else
    bad "dispatch row '$cmd' lacks 'read \`reference/X.md\` before acting'" "$row"
  fi
done

# The Guardrails stay in SKILL.md, whole.
for g in 'Never commit to the repository' 'Never bypass or fight git hooks' 'Never mutate application state' \
  'Never start servers' 'Pushing and opening a PR happen only' 'No push or PR without a review' \
  'Merging a PR happens only' 'Worktree removal' 'The only YouTrack writes are' 'Language' 'Assignee'; do
  sed -n '/^## Guardrails/,/^## Language/p' "$skill/SKILL.md" | grep -qF -- "$g" \
    && ok "guardrail kept in SKILL.md: $g" || bad "guardrail missing from SKILL.md: $g"
done

# Moved sections are not duplicated back into SKILL.md.
for h in '^## new$' '^## pr$' '^## link$' '^## log$' '^## comment$' '^## worktree$' '^## State sub-commands'; do
  grep -qE "$h" "$skill/SKILL.md" && bad "SKILL.md still has section $h" || ok "section moved out of SKILL.md: $h"
done

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILURES"
exit "$fail"
