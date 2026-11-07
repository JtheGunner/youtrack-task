# Project resolution

Detail for the "Resolving a project" procedure in `SKILL.md`. Read-only: it only
calls `find_projects` and `get_project`.

## The 20-item cap

`find_projects` returns **at most 20 projects per call** (`limit` maximum 20) and
paginates with `offset`. A single call with an empty `query` therefore shows only
the first page; on an instance with more than 20 projects the rest are invisible
to it. Never conclude that a project does not exist from one unpaged call.

## Targeted search

`query` is a case-insensitive substring match on the project name **or** key, so
a repo name such as `intelli-key-port` finds the project even when its key
(`IKP`) looks unrelated. Try the candidates from `SKILL.md` step 1 one by one; an
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
