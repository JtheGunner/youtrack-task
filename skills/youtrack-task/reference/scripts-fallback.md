# Scripts missing

Loaded only when step 0 reports `SCRIPTS=missing` (`SKILL.md` "Scripts"): the
skill was loaded through a connection that does not materialise bundled files.
With the scripts on disk, never apply any of this: `read-config` output is the
only source of config values.

Never write the scripts out yourself. Degrade to plain git, in place, never
forcing anything:

- `setup-workspace` → `git switch -c <prefix>/<ID>-<slug> <base>` from a clean tree
  (ask before stashing); report `MODE=inplace`. No worktree.
- `read-config` → read `~/.config/youtrack-task/config.toml` with the Read tool
  (if it exists) and apply the defaults in the Config table yourself. This path
cannot resolve the `[type_prefix]` table or the array keys (`worktree_clone`,
`worktree_link`, `batch_skip_tags`) reliably: use the documented defaults for
them and say so.
- `sweep-worktrees` / `worktree prune` → skip and say so.
- `worktree take` / `worktree remove` → print the `git worktree remove <path>` /
  `git switch <branch>` commands for the user to run.
- `review-stamp` → still run the review gate (it needs no script), keep the
  reviewed SHA in this session only, and say that `pr` in a later session cannot
  verify it and will review again.
