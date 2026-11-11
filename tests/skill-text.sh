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

# Text moved out of SKILL.md starts on a clean sentence: no prose paragraph begins
# mid-sentence (lowercase first letter right after a blank line).
for f in "$skill"/reference/{new,pr,pickup,subcommands,scripts-fallback,projects}.md; do
  frag=$(awk 'prev=="" && /^[a-z]/ && !/^(curl|git|gh|bash|npm)/ {print FILENAME": "NR": "$0} {prev=$0}' "$f")
  [ -z "$frag" ] && ok "no mid-sentence fragment in $(basename "$f")" || bad "paragraph starts mid-sentence in $(basename "$f")" "$frag"
done

# 7. One definition per rule, the rest point to it.
# Language: defined in SKILL.md; the references carry no copy of the wording.
copies=$(grep -rniE 'silently English|never mix them up' "$skill/reference" || true)
[ -z "$copies" ] && ok "language rule is defined only in SKILL.md" \
  || bad "language rule is restated in a reference file" "$copies"

# Review gate: the developer docs (stamp contract, hook internals) live in SPEC.md.
review=$skill/reference/review.md
max_review_lines=130
rl=$(wc -l < "$review" | tr -d ' ')
[ "$rl" -le "$max_review_lines" ] && ok "review.md has $rl lines (max $max_review_lines)" \
  || bad "review.md has $rl lines, max $max_review_lines"
for h in '^## Stamp contract' '^## Enforcement hook'; do
  grep -qE "$h" "$review" && bad "review.md still has section $h (belongs in SPEC.md)" \
    || ok "section not in review.md: $h"
done
grep -qE '^#+ .*Stamp contract' "$root/SPEC.md" && ok "SPEC.md holds the stamp contract" \
  || bad "SPEC.md has no stamp contract section"

# The confirm tables lead with the effective value (flag over config), not a condition.
for f in "$skill/SKILL.md" "$skill/reference/pr.md"; do
  grep -qE '^ *\| Effective `confirm_(branch|pr)` \|' "$f" \
    && ok "confirm table leads with the effective value in $(basename "$f")" \
    || bad "confirm table in $(basename "$f") has no 'Effective' first column"
done

# The "scripts missing" path says it applies only then, and names what it cannot resolve.
grep -qi 'only when' "$skill/reference/scripts-fallback.md" && grep -qF 'type_prefix' "$skill/reference/scripts-fallback.md" \
  && ok "scripts-fallback.md is marked as the degraded path and names [type_prefix]" \
  || bad "scripts-fallback.md lacks 'only when' or the [type_prefix] note"

# Examples follow the spec.
ex=$skill/examples
grep -qF '## Context' "$ex/new.md" && grep -qF '## Scope' "$ex/new.md" \
  && ok "examples/new.md shows Context and Scope" || bad "examples/new.md lacks Context or Scope"
grep -qF 'moved to Testing.' "$ex/pr.md" && grep -qiE 'review' "$ex/pr.md" \
  && ok "examples/pr.md shows the review gate and the comma form" \
  || bad "examples/pr.md lacks the review gate or 'moved to Testing.'"
grep -qF 'Branch:' "$ex/pickup.md" && grep -qF 'Implementation plan' "$ex/pickup.md" && grep -qiE 'review' "$ex/pickup.md" \
  && ok "examples/pickup.md shows the branch line, the plan comment and the review gate" \
  || bad "examples/pickup.md lacks the branch line, the plan comment or the review gate"

# 8. Documented limits.
grep -qiE 'arrays? .*(one line|single line)|single-line arrays' "$root/config.example.toml" \
  && ok "config.example.toml says arrays must be single-line" \
  || bad "config.example.toml does not say that arrays must be single-line"
grep -qiE 'fixed' "$skill/reference/writeback.md" && grep -qiE 'ladder.*fixed|fixed.*ladder' "$root/README.md" \
  && ok "the state ladder is documented as fixed (writeback.md, README.md)" \
  || bad "the state ladder is not documented as fixed in writeback.md and README.md"
grep -qE 'git tag' "$root/CONTRIBUTING.md" && ok "CONTRIBUTING.md has the tag step" || bad "CONTRIBUTING.md lacks the tag step"
for k in list_query local_plan_copy default_new_type; do
  sed -n '/Config overrides/,/^## /p' "$root/README.md" | grep -qF "$k" \
    && ok "README Config overrides names $k" || bad "README Config overrides does not name $k"
done

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILURES"
exit "$fail"
