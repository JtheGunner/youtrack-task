# Changelog

## 0.4.1 — 2026-09-06

- Docs: README rewritten intro (create / pick up / ship), `--checkpoints` /
  `--review` / `--no-review` flags documented, install command fixed to
  `youtrack-task@youtrack-task`. SPEC brought in line with shipped behaviour
  (issue-ID resolution, 40-char slug + type-word strip, guardrails).

## 0.4.0 — 2026-09-06

- Route planning + implementation through the `superpowers` plugin when it is
  installed (`use_superpowers = auto`): `brainstorming` /
  `systematic-debugging` → `writing-plans` for the plan;
  `subagent-driven-development` / `executing-plans` + `test-driven-development` +
  `requesting-code-review` + `verification-before-completion` for the build. The
  issue description's sections map onto each skill's inputs. Unchanged fallback
  when superpowers is absent.
- New flags `--checkpoints`, `--review`, `--no-review`.
- New config `use_superpowers`, `review_before_pr`.
- `reference/superpowers.md`.

## 0.3.0 — 2026-09-06

- `/youtrack-task new "<free text>"` — generate the title and a structured
  description (Summary / Context / Goal / Acceptance criteria / Scope /
  Technical notes / Open questions) from one blob of text. `reference/issue-template.md`.

## 0.2.0 — 2026-09-06

- `/youtrack-task new` — create an issue (project / title / description required,
  type inferred + confirmed, priority optional).

## 0.1.0 — 2026-09-06

- Initial plugin: `/youtrack-task [ID]` pickup flow (fetch → branch → In Progress
  → plan → write-back), sub-commands `comment` / `log` / `pr` / `link` /
  `testing` / `done`, bundled YouTrack MCP server, guardrails.
