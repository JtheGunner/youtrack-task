# Branch naming

Branch name = `<prefix>/<ISSUE-ID>-<slug>`

Example: issue `INFRA-42` "Rotate Vault unseal keys", Type `Task`
→ `chore/INFRA-42-rotate-vault-unseal-keys`

## Prefix from issue Type

| YouTrack Type | Prefix |
| --- | --- |
| Bug        | `fix`   |
| Feature    | `feat`  |
| Task       | `chore` |
| Epic       | `feat`  |
| Cosmetics  | `style` |
| *anything else / no Type* | `chore` |

Override per Type in `~/.config/youtrack-task/config.toml`:

```toml
[type_prefix]
Task = "feat"
```

A config entry replaces the row above for that exact Type name (case-sensitive,
as YouTrack reports it).

## Slug rules

1. Take the issue summary.
2. Strip a leading type label — it is already in the prefix. Remove a
   case-insensitive match of
   `^\s*(bug ?fix|hot ?fix|fix|feature|feat|refactoring|refactor|task|epic|chore|cosmetics?|change|docs?)(\s*/\s*(refactoring|refactor|feature|fix|task))*\s*[:\-–]\s*`
   from the front. E.g. `"Bugfix: Hover-Effekt …"` → `"Hover-Effekt …"`,
   `"Feature/Refactoring: Tabs …"` → `"Tabs …"`.
3. **Render it in English.** If the summary is not already English, produce a
   short English equivalent — terse, this is a branch name, not a translation.
   Identifiers, product names and proper nouns stay as-is.
   E.g. `"Hover-Effekt bei farblich markierten Tabellenzeilen korrigieren"` →
   `"fix hover on tinted table rows"`.
4. Lowercase.
5. Replace every run of non-`[a-z0-9]` characters with a single `-`.
6. Trim leading/trailing `-`.
7. Truncate to 40 characters; if the cut lands inside a word, back up to the last
   `-`; then trim a trailing `-`.

Branch names are **always English**, whatever language the issue is written in.

## Full-name cap

If `<prefix>/<ID>-<slug>` still exceeds 60 characters, shorten the slug further
until it fits. Never shorten the prefix or the ID.

## Confirm the name

Show the computed branch name and let the user accept it or supply their own
(e.g. a tighter English name like `fix/ADMIN-6-row-tint-hover`). Proceed with the
computed name only after the user has seen it.

## Base branch

1. `--base <branch>` argument if given.
2. else `git symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`).
3. else `main` if `origin/main` exists.
4. else `master` if `origin/master` exists.
5. else abort and ask.

Always `git fetch origin <base>` first, then branch from `origin/<base>` so the
new branch starts from the current remote tip, not a stale local ref.

## Guards

- **Never commit anything to the default branch.** If `git status --porcelain` is
  non-empty before branching, the only options are:
  1. `git stash push -u`, create the branch, then ask whether to `git stash pop`
     onto it or leave the stash for the user; or
  2. if the user confirms the pending changes belong with this issue, create the
     branch from the current dirty state and carry them over (no commit on the
     base branch).
  Do not offer "commit it on `<base>` first" — that is out of bounds.
- If the target branch already exists (`git rev-parse --verify <branch>`), do not
  recreate it — offer `git switch <branch>` instead.
- Never `git commit --no-verify` and never amend or rewrite existing commits. If a
  pre-commit hook fails or misbehaves, stop and report it; let the user decide.
