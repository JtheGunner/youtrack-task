# Contributing to youtrack-task

Issues and pull requests are welcome. For larger changes, open an issue first so
the approach can be agreed on before you invest time.

## Where things live

- `skills/youtrack-task/SKILL.md`, its `reference/*.md` and the bundled
  `scripts/*` — the user-facing behaviour.
- `SPEC.md` — the design and contract document.
- `README.md` — the user documentation.
- `tests/README.md` — the manual test checklist (there is no mock server).

## Change checklist

Every behaviour change — anything touching `SKILL.md`, `reference/*.md`,
`scripts/*`, `.mcp.json` or `config.example.toml` — also updates:

1. **`README.md`** — the affected sections (intro bullets, how-to sections, flags
   table, *Config overrides*, *What lives where*, *Troubleshooting*).
2. **`CHANGELOG.md`** — an entry under a new version heading
   ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/), newest first).
3. **`SPEC.md`** — command surface, flow steps, file tree and config block.
4. **`config.example.toml`** — every config key the skill or scripts read, with
   its default.
5. **`tests/README.md`** — new or adjusted manual test rows.
6. **Version** — the same new version in `.claude-plugin/plugin.json` and
   `.claude-plugin/marketplace.json` (`plugins[0].version`), following
   [SemVer](https://semver.org/): feature → minor, fix → patch, breaking → major.

Keep config keys and sub-command names identical across `SKILL.md`, `README.md`,
`SPEC.md` and `config.example.toml`.

## Testing

Run the affected rows of [`tests/README.md`](tests/README.md) against a real
YouTrack instance, using a throwaway or low-stakes issue.

## Conventions

- Commits, PR titles and branch names in English,
  [Conventional Commits](https://www.conventionalcommits.org/) style.
- Scripts are `bash`, without extension, executable, emit `KEY=VALUE` lines and
  are safe by construction: never `git … --force`, never `git branch -D`, never
  touch a dirty worktree. `reference/worktrees.md` is their contract — change
  both together.
- Nothing instance-specific in the repo: no real YouTrack URL or token.

Releases are tagged `vMAJOR.MINOR.PATCH` by the maintainer.
