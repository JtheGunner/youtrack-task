# `new` — create an issue

Loaded by the `new` dispatch row of `SKILL.md`. Bound by the **Guardrails** and
the **Language** rules there. The structure of a generated description is in
`reference/issue-template.md`.

```
/youtrack-task new "<free text describing the work>"     # free-text mode
/youtrack-task new [--project KEY] [--title "..."] [--description "..."] [--priority NAME] [--type NAME]
                  [--assignee LOGIN|EMAIL]
```

Create a new YouTrack issue. Two ways to supply the content:

- **Free-text mode** — the first non-flag argument is a prose blob (has spaces
  and isn't a bare project key), or `--from-text "..."` is given. The skill
  generates the title and a structured description from it (see step 0).
- **Field mode** — pass `--title` / `--description` etc.; any missing required
  field (project, title, description) is asked for, one at a time.

Bare `/youtrack-task new` → ask first: *"Paste a free-text description, or fill
the fields one by one?"*

### 0. Free-text mode: generate title + description

Follow `reference/issue-template.md`:
- Produce a `title` (one imperative line, ≤ 70 chars, no type word) in the
  language of the input — never translated to English.
- Produce a `description` in the fixed sections
  (Summary / Context / Goal / Acceptance criteria / Scope / Technical notes? /
  Open questions?), in the language of the input.
- Do not invent facts — gaps go in **Open questions**.
- Field mode counts too: if only one of `--title` / `--description` is given, the
  field you generate or ask for follows the language of the one that was given.
- `--title` / `--description` passed alongside free text override the generated
  value for that field; a given `--title` is used verbatim (no translation).
- If the text **explicitly** names an assignee (*"assign to max.muster"*,
  *"für max.muster"*, *"@max.muster"*), take it as the requested assignee —
  a merely mentioned name is not one. `--assignee` overrides it.

Then continue with steps 1–4 using the generated values. Priority is still only
set if the input explicitly signals urgency (then propose + ask) or `--priority`
is given.

### 1. Resolve the fields

**project** (required)
- `--project KEY` if given.
- Else resolve the current repo's project with the procedure in `reference/projects.md` and offer
  it: *"Create in `ADMIN` (this repo)? or name another project."* Never tell the
  user a project doesn't exist unless that procedure ran to the end.
- Else list **all** projects (paginated, see `reference/projects.md`) and ask.
- Validate the key exists (`mcp__youtrack__get_project`) before continuing.

**title** (required) — `--title` or ask.

**description** (required) — `--description` or ask. Multi-line is fine.

**type**
- `--type NAME` → validate against the project's allowed Type values and use it.
- Omitted → **infer** from title + description: pick one of the project's allowed
  Type values (Bug / Cosmetics / Feature / Task / Epic or whatever the schema
  lists), and show it with a one-line rationale for confirmation —
  *"Type: Bug (title mentions 'Fehler' / 'korrigieren'). OK, or pick another?"*
  Never create with an inferred Type unconfirmed. If inference is genuinely
  unclear and `default_new_type` is set in config, propose that instead.

**priority** (optional)
- `--priority NAME` → validate against the schema and use it.
- Omitted → leave unset; YouTrack applies the project default. Do not infer.

**assignee** — always set; defaults to the API-key owner.
- `mcp__youtrack__get_current_user` → the token's owner (the **key owner**).
- No assignee requested (`--assignee` / free text) → the key owner.
- Requested → `mcp__youtrack__find_user` with the given login or email.
  Found → that user's login. Not found → **fall back to the key owner** and flag
  it in step 3: *"Assignee: `<owner>` (⚠ `<requested>` not found → API-key
  owner)"*. Don't stop to ask — the step-3 confirmation is where it's corrected.

### 2. Read the schema

`mcp__youtrack__get_issue_fields_schema` for the project → exact field names and
allowed value spellings for Type and Priority. Match user/inferred values to the
schema's spelling (case-insensitive); if no match, show the allowed values and
ask. If the schema has no `Assignee` field, drop the assignee and say so in
step 3 (*"no Assignee field in `<PROJECT>` — created unassigned"*).

### 3. Confirm, then create

Show the assembled issue — project, title, full description, Type, Priority
(or "project default"), Assignee (with the ⚠ fallback note if step 1 fell back),
and a **Language** line (*"Language: German (from your input) — say so if it
should be English"*) — and get **one confirmation**. If the title and the
description are not in the language named on that line, fix that before showing
anything. The user may edit any field here before
confirming, including the Language and changing or clearing the Assignee; a new assignee login is
checked with `find_user` again. Editing one field does not regenerate the others
(an edited title leaves the generated description as-is) — except the Language:
changing it regenerates title and description in the new language.

Then `mcp__youtrack__create_issue` with project, summary (= title), description,
and the Type / Priority / Assignee custom fields (Assignee = the login). If the
create call can't set a custom field (listed in `failedToUpdateFields`, or
absent from `updatedFields`), follow up on the new issue —
`mcp__youtrack__change_issue_assignee` for Assignee, `mcp__youtrack__update_issue`
for the rest.

### 4. Report and offer pickup

Report the new issue ID, its URL, project, Type, Priority, Assignee (or why it's
unassigned), title. Then offer:
*"Pick it up now? → `/youtrack-task <new-ID>`"* (branch + In Progress + plan).
Don't chain automatically.

Creating is one MCP write; on failure report what failed and stop (nothing half-
created to clean up unless a follow-up `update_issue` / `change_issue_assignee`
failed after `create_issue` — then say the issue exists but that field didn't
stick).
