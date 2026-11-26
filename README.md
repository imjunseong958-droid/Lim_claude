# Lim_claude

Rules that make a coding agent run its change before calling it done, keep tests and docs lean, and merge its own PR without extra rounds. Install them into a repo's `AGENTS.md` and commit it, and everyone who clones the repo works under the same rules.

## What gets installed

| Path | What it is |
| --- | --- |
| `AGENTS.md` | Rules for order of work, verification, tests, docs, Git and PRs, merging, and subagents, plus Rust rules when the repo has `Cargo.toml` |
| `.claude/lim_claude/` | The installed version (`manifest`) and the original AGENTS.md and CLAUDE.md (`*.orig`) |
| `.gitignore` | Only if `.claude/` is ignored: a block that keeps `.claude/lim_claude/` tracked |

The first install:

1. Moves an existing `AGENTS.md` to `.claude/lim_claude/AGENTS.md.orig` and rewrites it with the Lim_claude block. Repo-specific rules go below the block's END line, and updates keep them.
2. Deletes `CLAUDE.md` and `.claude/CLAUDE.md`, keeping them as `.orig`, because Claude Code does not read `AGENTS.md` while a `CLAUDE.md` exists.
3. If all of `.claude/` is ignored, adds a `.gitignore` block that tracks only `.claude/lim_claude/`. The rest, such as `.claude/worktrees/` and `launch.json`, stays ignored.
4. Leaves `CLAUDE.local.md` alone with a warning: it is personal, and Claude Code does not read `AGENTS.md` for whoever has one.

The `.orig` files are committed, so uninstalling from any clone restores them. The suffix keeps Claude Code from reading them as rules.

## Usage

Get it once. It needs `jq`, which recent macOS ships with.

```bash
git clone https://github.com/imjunseong958-droid/Lim_claude.git ~/Lim_claude
```

Install into one or more repos (default: the current directory):

```bash
~/Lim_claude/lim.sh install ~/code/my-repo
```

Then:

1. Move rules specific to the repo from `.claude/lim_claude/AGENTS.md.orig` back below the END line. Drop general sections Lim_claude already covers (subagents, Git/PR, language rules).
2. If the repo has CI, make it a required status check: agents merge their own PRs once CI passes, and nothing inside the repo can stop a merge. On GitHub: Settings > Rules > Rulesets > New branch ruleset, target the default branch, turn on **Require status checks to pass**, and add the CI jobs (one job that waits on the others is enough). Leave **Require branches to be up to date before merging** off: with it on, every change to the default branch makes each open PR merge it in and run CI again before it can merge. Other hosts have this under branch protection. `install` reminds you when it finds CI config.
3. Check `git status` and commit. Teammates get the rules once they are committed.

Update pulls Lim_claude and installs again. It also removes what earlier versions installed: the `verify` skill, the `commit-gate.sh` hook, and the hook's registration in `.claude/settings.json` (the file goes too if nothing else is in it). A leftover file you edited is kept with a warning.

```bash
~/Lim_claude/lim.sh update ~/code/my-repo
```

Uninstall removes the blocks in `AGENTS.md` and `.gitignore` (and anything an earlier version left, as update does), restores the original `AGENTS.md` (with rules written below the block appended) and `CLAUDE.md`, and removes files and directories left empty, so an `AGENTS.md` or `.claude/` that did not exist before is not left behind.

```bash
~/Lim_claude/lim.sh uninstall ~/code/my-repo
```

## Why so little

1. **No verify skill, commit gate, or breaker subagent.** Earlier versions ran a verify skill before every first commit, blocked commits until it had run, and started a subagent to try to break each change. Every task paid for all of it, and it caught too little to be worth that. The agent now runs the related tests and tries the change itself, and CI runs the rest.
2. **No CI rerun when the default branch moves.** A PR whose CI passed is merged as long as it has no conflicts. Merging the default branch in and waiting for CI again only catches two PRs that pass alone but break together. That is rare, and the default branch's own CI catches it after the merge. Only a conflict, or the host, makes the agent update the branch.
3. **Fewer tests** (Tests). Tests that mirror the code, check only mocks, or exist for coverage catch no bugs and make refactoring harder. A test is kept only if breaking its behavior makes it fail.
4. **Fewer docs** (Docs). Overviews and summaries tell an agent nothing the code doesn't, go stale, and mislead the next agent.

When the same kind of bug gets through twice, add a test or a CI check that would have caught it. Delete rules and checks that no longer catch anything.

## Working on Lim_claude

`rules/` becomes the AGENTS.md block. After changing `lim.sh`, run `tests/test_lim.sh`. It builds scratch repos, runs install, reinstall, an update over an earlier version's install, and uninstall, and checks that uninstall leaves the repo as it was.
