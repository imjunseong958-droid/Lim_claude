# Lim_claude

Rules and tools that make a coding agent run its change and check it before it says "done". Install it into a repo and commit it, and everyone who clones that repo works under the same rules.

Based on the Anthropic blog post [How the Claude Code team thinks about verification](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/).

## What gets installed in a repo

| Path | What it is | Used by |
| --- | --- | --- |
| `AGENTS.md` | Rules for order of work, verification, tests, docs, Git and PRs, merging, and subagents. Rust rules are added when the repo has `Cargo.toml` | Any agent that reads AGENTS.md |
| `.claude/skills/verify/SKILL.md` | How to run the change and record the evidence | Claude Code (the `verify` skill). Other agents reach it through AGENTS.md |
| `.claude/hooks/commit-gate.sh` | Blocks `git commit` when the session has not run the verify skill. In a repo without CI, runs the checks before `git push` | Claude Code |
| `.claude/settings.json` | The hook's registrations | Claude Code |
| `.claude/lim_claude/` | The list of installed files (`manifest`) and the original AGENTS.md and CLAUDE.md (`*.orig`) | `lim.sh` |
| `.gitignore` | Only in repos that ignore `.claude/`: a block that keeps the Lim_claude files and `.claude/verify.sh` tracked | git |

### What the first install cleans up

1. **Existing `AGENTS.md`:** its content moves to `.claude/lim_claude/AGENTS.md.orig`, and `AGENTS.md` is rewritten with the Lim_claude block. Put rules specific to the repo below the block's END line. Updates keep that part.
2. **`CLAUDE.md` and `.claude/CLAUDE.md`:** deleted, because Claude Code does not read `AGENTS.md` when a `CLAUDE.md` exists. The originals are kept in `.claude/lim_claude/` as `.orig`.
3. **`.gitignore`:** if all of `.claude/` is ignored, a block at the end keeps only the Lim_claude files and `.claude/verify.sh` tracked. Everything else, such as `.claude/worktrees/`, `launch.json`, and other skills, stays ignored.
4. `CLAUDE.local.md` is personal, so it is left alone with a warning. Claude Code does not read `AGENTS.md` for anyone who has one.

The kept originals are committed, so uninstalling from another clone still restores them. The `.orig` suffix keeps Claude Code from reading the backups as rules.

## Usage

### 1. Get Lim_claude (once)

```bash
git clone https://github.com/imjunseong958-droid/Lim_claude.git ~/Lim_claude
```

It needs `jq`, which recent macOS ships with.

### 2. Install into a repo

```bash
~/Lim_claude/lim.sh install ~/code/my-repo
```

1. You can pass several repo paths. With none, it installs into the current directory.
2. If the old `AGENTS.md` had rules for that repo only (domain rules, things not to do), move those sections from `.claude/lim_claude/AGENTS.md.orig` back below the END line. General sections that Lim_claude already covers (Subagents, Git/PR, language rules) can be dropped.
3. Check `git status` and commit. Teammates get the rules only once they are committed.

### 3. Update

```bash
~/Lim_claude/lim.sh update ~/code/my-repo
```

1. Runs `git pull` in Lim_claude, then installs into the repo again.
2. Changes only the files that changed, deletes files Lim_claude no longer has, and adds hook registrations missing from `settings.json`.
3. Managed files you edited inside the repo are not overwritten; you get a warning. Add `--force` to overwrite them.

### 4. Uninstall

```bash
~/Lim_claude/lim.sh uninstall ~/code/my-repo
```

1. Removes the installed files, the block in `AGENTS.md`, the hook registrations in `settings.json`, and the block in `.gitignore`.
2. Restores the original `AGENTS.md` and `CLAUDE.md`. Rules you wrote below the block are appended to the original `AGENTS.md`.
3. Removes files and directories left empty. An `AGENTS.md` or `.claude/` that did not exist before is not left behind.
4. Leaves managed files you edited, and `.claude/verify.sh`.

## Per repo: the checks (`.claude/verify.sh`)

The repo's checks run once on the final code, before a PR is opened.

1. **Repo without CI config:** the push gate runs them before every `git push` and blocks the push if they fail. Merged code is checked the same way when the agent pushes it.
2. **Repo with CI:** the agent runs them once before opening the PR, and CI checks the PR. Turn on required status checks for the default branch in branch protection, so the host refuses to merge until CI passes. Agents merge their own PRs, and this is what stops a merge before CI is green.

The checks are `.claude/verify.sh` if it exists. Otherwise the agent finds the build, linter, and tests in the README, CI config, Makefile, or package manifest, and the push gate guesses from the project files:

| File | Check |
| --- | --- |
| `Cargo.toml` | `cargo check -q && cargo test -q` |
| `go.mod` | `go vet ./... && go test ./...` |
| `package.json` (with a real test script) | `npm test --silent` |
| `pytest.ini`, or `[tool.pytest]` in `pyproject.toml` | `python3 -m pytest -q` |

To pick the checks yourself, copy the template:

```bash
cp ~/Lim_claude/templates/verify.sh .claude/verify.sh
```

1. Uncomment the checks that fit the repo and delete the last two lines.
2. In a repo with CI, use the same checks as CI, so PRs don't fail only in CI (on formatting, for example).
3. A person has to commit `verify.sh`. The hook blocks Claude's commits while `verify.sh` has uncommitted changes.
4. After installing, run it once yourself to see that it passes on that machine. If it fails from the start, the agent cannot push.

## How the hook works

`commit-gate.sh` is registered for three Claude Code events. PostToolUse on the `Skill` tool notes that Claude ran the verify skill. UserPromptSubmit notes that the user typed `/verify`. PreToolUse on Bash gates `git commit` and `git push`, including `git -C dir commit` and `git add -A && git commit && git push`, and ignores commands like `git log --grep commit`.

### Commit gate

This follows the gate in the blog post. It does not run tests; it checks whether the session ran the verify skill.

1. A commit is allowed if the session ran the `verify` or `code-review` skill, whether Claude called it or the user typed `/verify`.
2. A commit whose message has `Verified: none (<reason>)` is allowed without it, for a docs-only commit for example.
3. Otherwise the commit is blocked and Claude is told to run the verify skill first. After two blocks in a session, the next commit is let through, so Claude cannot get stuck. That is safe because the checks still run before the code is pushed or merged.
4. A commit is always blocked while `.claude/verify.sh` has uncommitted changes, even after two blocks.
5. Commits during a merge, cherry-pick, revert, or rebase are allowed. AGENTS.md (Merging) says how merged code is checked.

### Push gate

1. Works only in repos without CI config: `.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`, `azure-pipelines.yml`, `bitbucket-pipelines.yml`, `.travis.yml`, `Jenkinsfile`, or `.buildkite`.
2. Runs the checks. If they fail, it shows Claude the last 60 lines of output and blocks the push.
3. After 3 failures in a row in a session, it tells Claude to stop and report to the user. It keeps blocking.
4. Does not run the checks again when the files are the same as at the last pass in the session.

### Modes

`LIM_COMMIT_GATE` sets the mode. `enforce` (the default) blocks. `observe` blocks nothing and writes what it would have blocked to `.git/lim-commit-gate.log`. `off` does nothing. When bringing this into a team repo, run it in `observe` for a while and check for false blocks. Start Claude with `LIM_COMMIT_GATE=observe claude`, or put it under `"env"` in `.claude/settings.json` (whole team) or `.claude/settings.local.json` (just you).

Without `jq`, the hook does nothing.

## Taken from the blog post

| In the post | Where it is here |
| --- | --- |
| Verifying means running the change. If you pick one kind of test, pick end-to-end. Use the verify skill before committing | AGENTS.md Order of work 2, Verification 1, Tests 3, the `verify` skill |
| Property tests and differential tests | AGENTS.md Tests 8 |
| If a change can modify the check that judges it, the check is broken | AGENTS.md Verification 3, the hook's block on `verify.sh` changes |
| Flaky tests are not retried until green; if the cause can't be found, delete the test and write down why | AGENTS.md Verification 5, the `verify` skill |
| A check still failing after three rounds brings in a person | AGENTS.md Verification 6, the push gate's failure count |
| Run cheap checks (tests, build, linter) locally before opening a PR | AGENTS.md Order of work 6, Verification 2, the push gate |
| A commit gate that blocks commits when the session did not run `/verify` or `/code-review`, with off, observe, and enforce modes; a commit can explain why it was not verified; after two blocks the next commit goes through | `commit-gate.sh` |
| Say in the PR how it was verified, or that it wasn't | AGENTS.md Git and PRs 4, `verify` skill section 4 |
| Stamp each commit with how it was verified, including "none", so unverified commits can be found | AGENTS.md Git and PRs 5 (the `Verified:` trailer). Find them with `git log --grep='^Verified: none'` |
| Tune one reviewer instead of adding more. Read the review criteria (REVIEW.md) from the default branch | AGENTS.md Subagents 2 |
| Review committed code only. A review of an out-of-date commit means nothing | AGENTS.md Order of work 4 |
| Review and verification rounds build on earlier rounds instead of starting over | AGENTS.md Order of work 5, Subagents 3 |

## Where this differs from the post

1. **Flaky tests:** as in the post, a test whose cause can't be found is deleted with the reason written down. But a PR that deletes one is not auto-merged; it goes to a person. In the post a person looks at PRs before merging, while here agents merge their own PRs and nobody might see the deletion. This lets a person catch a real bug that the agent mistook for flakiness.
2. **Commit gate:** it follows the post, with three differences. The reason for skipping verification must be written as `Verified: none (<reason>)`. Commits during a merge or rebase are not gated. A change to `.claude/verify.sh` stays blocked even after two blocks.
3. **Enforcing the cheap checks:** the post suggests a hook that runs the tests when Claude finishes. Here the hook runs them before `git push`, because Claude opens and merges the PR in the same turn, so "when Claude finishes" would be after the merge. It runs only without CI, because with CI the PR is checked by CI anyway.

## Added beyond the post

1. **Fewer tests:** agents often keep the tests they wrote to check something once. Tests that mirror the implementation, check only mocks, or exist for coverage pile up, catch no bugs, and make refactoring harder. So tests are written only for changed behavior or fixed bugs, and a new test is kept only after breaking the behavior it checks and seeing it fail. One-off checks are scratch scripts that get deleted. End-to-end and golden tests stay, and new behavior is covered through them where possible. When golden files are regenerated, each changed line is checked and listed in the PR. (AGENTS.md Tests)
2. **Fewer docs:** architecture overviews, per-file descriptions, and work summaries tell an agent nothing the code doesn't, and they go stale and mislead the next agent. So no new docs unless the user asks, plans and verification reports go in the PR description, and only the parts of existing docs that a change makes wrong are fixed. (AGENTS.md Docs)
3. **No duplicated work:** verifying, reviewing, fixing, verifying again from scratch, and verifying again when merging PRs made each task take far too long. So the order is fixed: implement, verify, commit, review, PR, merge. The `verify` skill runs once per task. The full checks run once on the final code. While working, only the related tests run. Review fixes are re-checked by the same reviewer looking at only that diff, and by hand only for the behavior a fix changed. Review stops after 3 rounds (the post sets no limit). Fixes, merges, and conflict resolution after the PR is open get no new review or `verify` run. (AGENTS.md Order of work, Verification 2)
4. **Auto-merge:** agents merge the PRs they opened without asking. Before merging, the latest default branch is merged into the PR branch, conflicts are resolved, and the merged result must pass CI, or the push gate when there is no CI. Each PR can pass alone and still break when combined, so the check of the merged result stays. The agent does not merge, and tells the user instead, when a conflict needs a judgment call, a person requested changes, a review finding it could not fix may be a real bug, the PR deletes a flaky test, or branch protection blocks the merge. Force-pushes still need the user's approval. (AGENTS.md Merging)

## This repo's layout

| Path | Role |
| --- | --- |
| `lim.sh` | install, update, uninstall |
| `rules/base.md`, `rules/rust.md` | The rules that go into the `AGENTS.md` block |
| `skills/`, `hooks/` | Files copied under the repo's `.claude/` |
| `templates/verify.sh` | Template for a repo's checks |
| `tests/test_lim.sh` | Tests for `lim.sh` and the hook. Builds scratch repos, runs install, reinstall (including changes on the Lim_claude side), and uninstall, checks that uninstall leaves the repo as it was, and feeds the hook the events Claude Code sends. Run it after changing `lim.sh` or the hook |
