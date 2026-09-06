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
2. Lowercase.
3. Replace every run of non-`[a-z0-9]` characters with a single `-`.
4. Trim leading/trailing `-`.
5. Truncate to 50 characters, then trim a trailing `-` again.

## Full-name cap

If `<prefix>/<ID>-<slug>` exceeds 60 characters, shorten the slug further until it
fits. Never shorten the prefix or the ID.

## Base branch

1. `--base <branch>` argument if given.
2. else `git symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`).
3. else `main` if `origin/main` exists.
4. else `master` if `origin/master` exists.
5. else abort and ask.

Always `git fetch origin <base>` first, then branch from `origin/<base>` so the
new branch starts from the current remote tip, not a stale local ref.

## Guards

- Working tree must be clean. If `git status --porcelain` is non-empty, stop and
  offer `git stash push -u`.
- If the target branch already exists (`git rev-parse --verify <branch>`), do not
  recreate it — offer `git switch <branch>` instead.
