# Working on youtrack-task

This is a Claude Code plugin. The user-facing behaviour lives in
`skills/youtrack-task/SKILL.md`, its `reference/*.md`, and the bundled
`scripts/*`. `SPEC.md` is the design/contract doc; `README.md` is the user doc.

## Change checklist — do ALL of these for every behaviour change

Whenever you touch `SKILL.md`, a `reference/*.md`, a `scripts/*`, `.mcp.json`, or
`config.example.toml`, before committing:

1. **`README.md`** — update the affected section(s). New sub-command → add it to
   the intro bullets, the *During and after the work* list, and any relevant
   how-to section + the flags table. New config key → *Config overrides* +
   *What lives where*. New failure mode → *Troubleshooting*. This is the step
   that keeps getting missed — check it explicitly, every time.
2. **`CHANGELOG.md`** — add an entry under a new version heading (Keep a
   Changelog style, newest first).
3. **`SPEC.md`** — keep the command surface, flow steps, file tree, and config
   block in sync with what shipped.
4. **`config.example.toml`** — every config key the skill/scripts read must be
   documented here with its default.
5. **`tests/README.md`** — add/adjust the manual test rows for the new behaviour.
6. **Version bump** — `.claude-plugin/plugin.json` **and**
   `.claude-plugin/marketplace.json` (`plugins[0].version`), same number.
   SemVer: new feature → minor, fix → patch, breaking → major.
7. **Tag** — `git tag -a vX.Y.Z -m "…"` and push it with the commit.

Consistency to keep: config keys identical across SKILL.md's table,
`config.example.toml`, and SPEC.md's block; sub-command names identical across
SKILL.md dispatch table + sections, README, and SPEC.

## Conventions

- Commits/PR titles/branch names: English, Conventional Commits. No attribution
  trailers.
- Scripts: `bash`, no extension, `chmod +x`, emit `KEY=VALUE` lines, safe by
  construction (never `git … --force`, never `git branch -D`, never touch a dirty
  worktree). `reference/worktrees.md` is their contract — change both together.
- Nothing instance-specific in the repo (no real YouTrack URL, token, or
  project↔repo mapping). URL/token come from `YOUTRACK_MCP_URL` /
  `YOUTRACK_TOKEN`.
