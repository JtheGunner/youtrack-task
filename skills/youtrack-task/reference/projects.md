# Project resolution

The one procedure for "the current repo's YouTrack project" (bare issue number,
repo sanity check, `new`, `all`). Read-only: it only calls `find_projects` and
`get_project`.

## Procedure

Everywhere the skill needs "the current repo's YouTrack project" (bare issue
number, repo sanity check, `new`), use this one procedure — never an ad-hoc
guess. `find_projects` returns **at most 20 projects per page**, so one call with
an empty query shows only the first page; a project missing from it may still
exist. Names differ from keys (repo `intelli-key-port` ↔ key `IKP`), so match on
the **name**, not the key.

1. **Candidates.** The repo name from `git remote get-url origin` (strip the
   `.git` suffix and any owner path) and the basename of the working directory,
   each also with `-` / `_` removed.
2. **Targeted search.** `find_projects(query=<candidate>)` per candidate. A
   case-insensitive exact name match wins. A single substring match is offered for
   confirmation. Several matches → ask which.
3. **Full listing, only if step 2 found nothing.** Page through
   `find_projects(query="", limit=20, offset=0, 20, 40, …)` until a page returns
   fewer than 20 items, then match the candidates against every name.
4. **Verify.** `get_project` on the chosen key before using it.
5. **Only now** may you say there is no matching project — after steps 2 and 3.
   A list you show the user to pick from must be the complete one from step 3
   (or say it is partial). Never answer *"there is no project named …"* from a
   single unpaged call.

The 20-item cap and the paging loop are spelled out below.

A project key the user typed (`--project KEY`) skips 1–3 and goes straight to
`get_project`. An issue ID's prefix is authoritative for that issue's project.

## The 20-item cap

`find_projects` returns **at most 20 projects per call** (`limit` maximum 20) and
paginates with `offset`. A single call with an empty `query` therefore shows only
the first page; on an instance with more than 20 projects the rest are invisible
to it. Never conclude that a project does not exist from one unpaged call.

## Targeted search

`query` is a case-insensitive substring match on the project name **or** key, so
a repo name such as `intelli-key-port` finds the project even when its key
(`IKP`) looks unrelated. Try the candidates from the procedure one by one; an
exact (case-insensitive) name match wins over a substring match.

## Paging through the full list

Used only when the targeted search found nothing, and whenever the user is shown
a list to pick from:

```
offset = 0
all    = []
loop:
    page = find_projects(query="", limit=20, offset=offset)
    all += page
    if len(page) < 20: stop
    offset += 20
```

Match the candidates against every name in `all`. A list shown to the user is
this complete list, or it says it is partial.

## Verify

Run `get_project` on the chosen key before using it. "No project named …" is
allowed only after the targeted search and the full paging both came up empty.
