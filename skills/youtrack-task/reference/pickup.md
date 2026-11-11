# Primary flow — workspace set-up and resume

Loaded by the primary-flow dispatch row of `SKILL.md`; this is the detail of its
step 4 (and the resume check that steps 5–7 follow). Bound by the **Guardrails**
there. The branch-name question is gated by the table in `SKILL.md` step 4.

proceed?" question. Then run the bundled script — **do not hand-roll the branch /
worktree logic**, the script is the source of truth
(spec: `reference/worktrees.md`):

```
<skill-dir>/scripts/setup-workspace --id <ID> --slug <slug> --prefix <prefix> \
    [--base <branch>] [--mode worktree|inplace]
```
(run it with the repo root as working directory, see **Scripts**). `--mode worktree` for
`--worktree`, `--mode inplace` for `--no-worktree`; omit otherwise — the script
reads `config` `worktree`, does the dirty / branch / existing-worktree checks,
creates or resumes, and bootstraps a new worktree.

Act on its `KEY=VALUE` output:

| `MODE=` | do this |
| --- | --- |
| `inplace` | you're on `BRANCH` in the repo root. Report `BRANCH` / `BASE`. |
| `worktree` | enter `NEXT_CD` (see below). Report `BRANCH` `BASE` `DIR` `CLONED` `LINKED` + any `NOTE=` lines. Steps 5–8 run there. |
| `existing-worktree` | a worktree for this issue already exists → enter `NEXT_CD`. Announce *"Resuming `<ID>` in `<DIR>`."* Steps 5–7 follow the **resume check** below. |
| `existing-branch` | a branch for this issue exists but isn't checked out. Ask the user: `git switch <BRANCH>`, or `git worktree add <repo>/<worktree_dir>/<ID>-<slug> <BRANCH>` then enter it. Steps 5–7 follow the **resume check** below. |

**Entering a worktree:** use `EnterWorktree` with that `path` when it is
available. Otherwise a `cd` does not carry over to the next Bash call, so run
every later command with the worktree as working directory in the same call —
`git -C <DIR> …`, `(cd <DIR> && …)` — and use absolute paths for files.

**Resume check** (`existing-worktree` / `existing-branch`): look in the comments
read in step 2 for the two template headings of `reference/writeback.md`.

| Comments contain | Do this |
| --- | --- |
| `📌 Picked up in Claude Code` | skip step 5 |
| no pickup comment | step 5 runs normally |
| `## 📝 Implementation plan` | step 6 reuses that plan (no re-brainstorm unless asked); skip step 7 |
| no plan comment | steps 6 and 7 run normally |

`ERROR=dirty-tree` (exit 2) → tracked changes present, in-place branch wanted.
Ask the user: stash (`git stash push -u`, re-run, then pop or keep) or carry
(re-run with `--allow-dirty` — the changes ride onto the feature branch). Never a
commit on the base branch. Any other `ERROR=` → stop and show it.
