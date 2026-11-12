# 🧩 Other agents

Back to the [README](../README.md).

`skills/youtrack-task/` is a self-contained `SKILL.md` skill. Besides Claude Code it
runs in Cursor, GitHub Copilot, Codex CLI and other agents that can load a skill and
talk to an MCP server. It is also listed on
[Agensi.io](https://www.agensi.io/skills/youtrack-flow-for-ai-agents) and
[Product Hunt](https://www.producthunt.com/products/youtrack-task).

## Install

1. **Get the skill folder.** Download it from the
   [Agensi listing](https://www.agensi.io/skills/youtrack-flow-for-ai-agents), or copy
   `skills/youtrack-task/` from this repository, into the place your agent loads
   skills from. Keep the whole folder: `SKILL.md` reads the `reference/*.md` files
   next to it.
2. **Create an API token** in YouTrack (*Profile → Account Security → New token*,
   scope **YouTrack**).
3. **Add the YouTrack MCP server to the agent.** HTTP server at
   `https://<your-host>/mcp` with the header `Authorization: Bearer <token>`:

   | Agent | Where |
   |-------|-------|
   | Cursor | `.cursor/mcp.json`, an HTTP server named `youtrack` with `url` and `headers.Authorization` |
   | GitHub Copilot / VS Code | `.vscode/mcp.json`, same URL and header |
   | Codex CLI and others | the agent's own MCP settings |

   The plugin's `.mcp.json` only applies to Claude Code.
4. **Try it:** `youtrack-task PROJ-1` (or the agent's skill invocation) from a git
   repository.

Never commit the token. Keep it in the agent's MCP configuration or an environment
variable.

## What differs from Claude Code

| | Difference |
|:-:|-----------|
| 🏷️ | **Tool names** are matched by base name (`get_issue`, `update_issue`, …), not by the `mcp__youtrack__` prefix. |
| 📜 | **Bundled `scripts/` are optional.** Without them on disk the skill falls back to plain in-place git: no worktrees, nothing forced. |
| 🔍 | **The review gate runs in its weaker mode.** The `ticket-reviewer` agent and the hooks live at plugin level. The review is stamped `independent=no`, `pr` asks for confirmation, and `all --auto-merge` stays disabled. |

## Build the Agensi package

The upload ZIP contains the whole skill folder, so the `reference/*.md` files travel
with it. Build it with `tools/package-agensi` (output: `dist/agensi/youtrack-task.zip`).
Pushing a version tag also builds it in CI and attaches it to the GitHub Release. The
upload to Agensi itself is manual.

The skill-level readme is
[`skills/youtrack-task/README.md`](../skills/youtrack-task/README.md).
