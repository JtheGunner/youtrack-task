# Running the plan + implementation through superpowers

When the `superpowers` plugin is installed, the primary flow's planning (step 6)
and implementation (step 8) run through its skills instead of a plain plan-mode
pass. Everything here is bound by the **Guardrails** in `SKILL.md`.

## When to use it

Check `use_superpowers` (config, default `auto`):

| value | behaviour |
| --- | --- |
| `auto` | use superpowers if its skills are available, else the plain fallback |
| `always` | use superpowers; if unavailable, stop and tell the user to install it |
| `never` | always the plain fallback (plan mode + normal dev workflow) |

"Available" = `superpowers:brainstorming` (and the others) show up in the skills
listing for this session.

## The issue description is the interface

`/youtrack-task new` writes the description in fixed sections precisely so each
superpowers skill gets a clean, labelled input. Map them straight through:

| Description section | Feeds |
| --- | --- |
| Summary + Context + Goal | the problem statement given to brainstorming / systematic-debugging |
| Acceptance criteria | success criteria for brainstorming; the checklist for `verification-before-completion`; the criteria for `requesting-code-review` |
| Scope (in / out) | the YAGNI boundary brainstorming must respect |
| Technical notes | known constraints handed to brainstorming and to the implementer |
| Open questions | brainstorming asks these back to the user as its clarifying questions |

Always also hand over: the issue ID, the branch name, and the repo exploration
(files the change is likely to touch).

If the issue predates the template and has an unstructured description, pass it
as-is and let brainstorming's questions fill the gaps.

## Step 6 — plan

1. Pick the process skill by issue **Type**:
   - `Bug` → `superpowers:systematic-debugging` first (establish root cause),
     then design the fix.
   - anything else → `superpowers:brainstorming`.
2. Feed it the mapped inputs above.
3. Let brainstorming classify the work:
   - **spike / bounded** → a short in-chat design. No plan document.
   - **architectural** → brainstorming writes its design doc, then
     `superpowers:writing-plans` produces the implementation plan.
     Location, in order of preference: the repo's existing
     `docs/superpowers/specs/` convention → `docs/plans/<ID>-plan.md` →
     in-chat only (no `docs/` dir).
4. Present the design / plan to the user; iterate until they approve it.

Record which path was taken — **bounded** vs **architectural** — it decides
step 8.

## Step 7 — write-back

Post the design or the plan-document contents as the plan comment
(`reference/writeback.md`). If `writing-plans` wrote a plan file here, that file
is the local copy — name its path, and do **not** let SKILL.md step 7's
`local_plan_copy` write a second `docs/plans/<ID>.md`.

## Step 8 — implement

Bound by the Guardrails. Path from step 6:

### bounded
- Implement directly with `superpowers:test-driven-development` (write the failing
  test first; acceptance-criteria items become tests where feasible).
- No plan-execution skill, no automatic code review.

### architectural (a plan document exists)
- Execute it with `superpowers:subagent-driven-development` in the current
  session. `--checkpoints` on the primary command switches to
  `superpowers:executing-plans` (stop for review after each phase).
- Coding inside each task still goes through `superpowers:test-driven-development`.
- After execution, run `superpowers:requesting-code-review` against the
  acceptance criteria **automatically**. `--no-review` skips it; `--review`
  forces it on the bounded path too. Config `review_before_pr` (`auto` default /
  `always` / `never`) is the standing setting.
- Address review feedback with `superpowers:receiving-code-review`.

### both paths, before finishing
- `superpowers:verification-before-completion` using the issue's **Acceptance
  criteria** as the checklist — run the real verification commands, don't assert
  from memory.
- Then post the one-line completion comment (`reference/writeback.md`), list the
  branch + files touched, and stop. Do **not** push, open a PR, or move the
  issue — `/youtrack-task pr` or the user's own ship flow is next.
- Do not invoke `superpowers:finishing-a-development-branch`; integration is the
  `pr` sub-command's / the user's job.

## Language

Whatever language the issue is in, everything this path writes to **git** —
commit messages from the TDD / execution steps, any branch it creates — is in
**English** (Guardrails). Design docs / plan files written locally are English
too. Only the YouTrack plan comment follows the issue's language.

## Fallback (no superpowers)

Exactly today's behaviour: plan mode for step 6, the normal development workflow
(TDD where it applies) for step 8, the skill's own guardrails and a manual
verification pass before the completion comment.
