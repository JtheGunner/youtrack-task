# Generated issue structure

`/youtrack-task new` in free-text mode turns one blob of text into a **title** and
a **description** in the fixed structure below. The structure exists so a later
`/youtrack-task <id>` can parse the issue straight back into a plan with no
guesswork — the section headings are parse anchors.

## Title

- One line, imperative mood, ≤ 70 characters.
- No leading type word (`Bug:`, `Feature:`) — the Type field carries that.
- Names the outcome, not the activity
  (`Cart total ignores per-item discount`, not `Look into cart bug`).

## Description — fixed sections, in this order

Write the prose in the **language of the user's input**. Keep the headings
verbatim as below. Omit an *optional* section only when there is genuinely
nothing to put in it; never omit a required one.

### Summary  *(required)*
1–3 sentences: what needs to change and why. The paragraph someone reads to
grasp the issue.

### Context  *(required)*
Where this lives (area, screens, files), how it behaves today, what prompted the
request. Links / IDs if any.

### Goal  *(required)*
The intended end state in observable terms — what is true once this is done.

### Acceptance criteria  *(required)*
A checklist of testable statements; each item is something a reviewer or a test
can confirm. Reused verbatim later as the verification checklist.
- [ ] …
- [ ] …

### Scope  *(required)*
- In scope: …
- Out of scope: …

### Technical notes  *(optional)*
Known constraints, suspected root cause, files likely involved, an approach the
requester already has in mind, gotchas.

### Open questions  *(optional)*
Unknowns to resolve during planning.

## Generator rules

- Derive the title per the rules above.
- Fill every required section from the input. **Never invent facts** — if the
  input doesn't say, put the gap in **Open questions**, don't guess.
- Keep the user's own wording where it's already precise; tighten, don't
  paraphrase away detail.
- Infer **Type** from the generated title + description (same rule as
  `reference/branching.md` uses for the prefix).
- Do **not** infer **Priority**. Only if the input explicitly signals urgency
  (`blocker`, `prod down`, `asap`, `dringend`) propose a Priority and ask;
  otherwise leave it unset (project default).
- Show the full generated title + description and let the user edit before the
  issue is created.
