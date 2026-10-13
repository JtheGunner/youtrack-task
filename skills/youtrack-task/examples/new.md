# Example: create an issue from free text

Illustrative run. Project key, user and issue number are placeholders.

```text
> /youtrack-task new "Hover on tinted table rows loses the colour on mouseover; want a same-hue hover instead"
```

The skill generates a title and a structured description in the language of the
input, infers the Type from the project's allowed values, and asks for **one**
confirmation before creating anything:

```text
Project:   PROJ (this repo)
Title:     Keep row tint visible on hover
Type:      Cosmetics (title describes a visual defect)   ← inferred, please confirm
Priority:  project default
Assignee:  dev.user (API-key owner)

Description:
## Summary
Hovering a tinted table row replaces its colour with the default hover colour.

## Goal
A same-hue hover state that keeps the row's tint recognisable.

## Acceptance criteria
- [ ] Tinted rows keep their hue on hover
- [ ] Untinted rows are unchanged

## Open questions
- Which tint colours exist besides the three in the status column?

Create it? (edit any field, or confirm)
```

After confirmation the skill calls `create_issue`, reports the new ID and URL, and
offers `/youtrack-task PROJ-<n>` to pick it up. It never invents facts: anything
missing from the input goes under *Open questions*.

Assignment: the API-key owner by default; `--assignee <login|email>` or an
explicit "assign to …" in the text picks someone else. An unknown user falls back
to the key owner and is flagged at the confirmation step.
