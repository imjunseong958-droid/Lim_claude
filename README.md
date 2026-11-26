# Lim_claude

Rules and tools that make a coding agent run its change and show the evidence before it calls the work done, then merge its own PR. Install it into a repo and commit it, and everyone who clones the repo works under the same rules.

Based on the Anthropic post [How the Claude Code team thinks about verification](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/), with more weight on running the change than on reading it: the one subagent per task tries to break the change and reports only failures it reproduced.

## What gets installed

| Path | What it is | Used by |
| --- | --- | --- |
| `AGENTS.md` | Rules for order of work, verification, tests, docs, Git and PRs, merging, and subagents, plus Rust rules when the repo has `Cargo.toml` | Any agent that reads AGENTS.md |
| `.claude/skills/verify/SKILL.md` | How to run the change and report the evidence | Claude Code (the `verify` skill); other agents through AGENTS.md |
| `.claude/hooks/commit-gate.sh` | Blocks `git commit` until the session ran the verify skill. Without CI, runs the checks before `git push` | Claude Code |
| `.claude/settings.json` | The hook's registrations | Claude Code |
| `.claude/lim_claude/` | The installed-file list (`manifest`) and the original AGENTS.md and CLAUDE.md (`*.orig`) | `lim.sh` |
| `.gitignore` | Only if `.claude/` is ignored: a block that keeps the Lim_claude files and `.claude/verify.sh` tracked | git |

The first install:

1. Moves an existing `AGENTS.md` to `.claude/lim_claude/AGENTS.md.orig` and rewrites it with the Lim_claude block. Repo-specific rules go below the block's END line, and updates keep them.
2. Deletes `CLAUDE.md` and `.claude/CLAUDE.md`, keeping them as `.orig`, because Claude Code does not read `AGENTS.md` while a `CLAUDE.md` exists.
3. If all of `.claude/` is ignored, adds a `.gitignore` block that tracks only the Lim_claude files and `.claude/verify.sh`. The rest, such as `.claude/worktrees/` and `launch.json`, stays ignored.
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
2. Set up the repo's checks (Per repo).
3. If the repo has CI, make it a required status check: agents merge their own PRs once CI passes, and nothing inside the repo can stop a merge. On GitHub: Settings > Rules > Rulesets > New branch ruleset, target the default branch, turn on **Require status checks to pass**, and add the CI jobs (one job that waits on the others is enough). Other hosts have this under branch protection. `install` reminds you when it finds CI config.
4. Check `git status` and commit. Teammates get the rules once they are committed.

Update pulls Lim_claude and installs again. It rewrites only changed files, deletes files Lim_claude no longer has, and adds missing hook registrations. Managed files edited in the repo are kept with a warning; `--force` overwrites them.

```bash
~/Lim_claude/lim.sh update ~/code/my-repo
```

Uninstall removes the installed files and the blocks in `AGENTS.md`, `settings.json`, and `.gitignore`, restores the original `AGENTS.md` (with rules written below the block appended) and `CLAUDE.md`, and removes files and directories left empty, so an `AGENTS.md` or `.claude/` that did not exist before is not left behind. Managed files you edited, and `.claude/verify.sh`, are kept.

```bash
~/Lim_claude/lim.sh uninstall ~/code/my-repo
```

## Per repo

### The checks: `.claude/verify.sh`

They run once on the final code before the PR opens: by the push gate on every `git push` in a repo without CI config, or by the agent before opening the PR in a repo with CI, which then checks the PR. Without `verify.sh`, the agent finds the build, linter, and tests in the README, CI config, Makefile, or package manifest, and the push gate guesses:

| File | Check |
| --- | --- |
| `Cargo.toml` | `cargo check -q && cargo test -q` |
| `go.mod` | `go vet ./... && go test ./...` |
| `package.json` with a real test script | `npm test --silent` |
| `pytest.ini`, or `[tool.pytest]` in `pyproject.toml` | `python3 -m pytest -q` |

To pick them yourself, copy the template, uncomment what fits, and delete its last two lines:

```bash
cp ~/Lim_claude/templates/verify.sh .claude/verify.sh
```

With CI, use the same checks as CI, so PRs don't fail only there. Run it once yourself: if it fails from the start, the agent cannot push. A person commits `verify.sh`; the hook blocks Claude's commits while it has uncommitted changes.

Keep `verify.sh` fast and reliable. It is the repo's smoke-test harness: a flaky one teaches agents to rerun instead of fix, and a slow one makes them run fewer checks.

## How the hook works

`commit-gate.sh` handles three Claude Code events. PostToolUse on `Skill` and UserPromptSubmit note that the session ran the verify skill (Claude called it, or the user typed `/verify`). PreToolUse on Bash gates `git commit` and `git push` in their usual spellings, including `git -C "/a b"`, `git -c k="v w"`, `/usr/bin/git`, `bash -c '…'`, subshells, and chains with `&&` or `;`. It ignores commands like `git log --grep commit` and `git commit-tree`, and quoted text that only mentions git, as in `grep -rn "git commit" docs/`, unless a shell's `-c`, `eval`, or `"$(...)"` runs it.

Each command is judged in the checkout it runs in: its starting folder, the `cd` moves before it, and git's `-C`. In a worktree that is the worktree, not the main checkout Claude Code names as the project. A command whose checkout is known only once it runs (it sets `GIT_DIR`, or runs `cd "$(...)"`) is blocked with a request to name the folder.

**Commit gate.** As in the post, it checks whether the session ran the verify skill, not the tests. A commit is allowed when:

1. the session ran the `verify` or `code-review` skill;
2. its message has `Verified: none (<reason>)`, in the command or a `-F` file;
3. a verified session committed on this branch before, and that work is not on the default branch yet (a fix or PR update, maybe in a new session);
4. a merge, cherry-pick, revert, or rebase is in progress; or
5. commits were blocked twice in the session: the next one goes through, so Claude cannot get stuck, and the count starts over. The checks still run before push or merge.

It is always blocked while `.claude/verify.sh` has uncommitted changes, deletion or rename included, even after two blocks.

**Push gate.** Only without CI config (`.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`, `azure-pipelines.yml`, `bitbucket-pipelines.yml`, `.travis.yml`, `Jenkinsfile`, `.buildkite`). It runs the checks in the push's checkout and blocks a failing push, showing Claude the last 60 lines. After 3 failures in a row in a session, it tells Claude to stop and report to the user, and keeps blocking. A tree that already passed in the session is not checked again.

**Modes.** `LIM_COMMIT_GATE=enforce` (default) blocks. `observe` blocks nothing and logs what it would have blocked to `.git/lim-commit-gate.log`. `off` does nothing. In a team repo, start with `observe` and look for false blocks: `LIM_COMMIT_GATE=observe claude`, or `"env"` in `.claude/settings.json` (team) or `.claude/settings.local.json` (you). Without `jq`, the hook does nothing.

## Taken from the post

| In the post | Here (AGENTS.md unless noted) |
| --- | --- |
| Verifying means running the change; if you pick one kind of test, pick end-to-end; use a `verify` skill before committing | Verification 1, Tests 3, the `verify` skill |
| Give the agent hands and eyes on the running app | The `verify` skill |
| Property tests (round-trip, invariants, idempotency, naive vs. optimized) and differential tests | Tests 8 and 9 |
| A check the change can modify is broken; review criteria (REVIEW.md) come from the default branch | Verification 3, Subagents 2, the hook's `verify.sh` block |
| Flaky tests are not retried, slept, or skipped; if the cause can't be found, delete with a reason | Verification 5 |
| Still failing after three rounds: bring in a person | Verification 6, the push gate |
| Run tests, build, and linter before opening a PR | Verification 2, the push gate |
| Commit gate on `/verify` or `/code-review`: off/observe/enforce, a reason for skipping, a pass after two blocks | `commit-gate.sh` |
| Stamp each commit with how it was verified, "none" included | Git and PRs 5. Find unverified commits with `git log --grep='^Verified: none'` |
| Tune one reviewer instead of stacking more | Subagents: one breaker, no second opinions |
| A review of an out-of-date commit means nothing | Order of work 5 |
| Rounds build on earlier rounds | Order of work, Subagents 4 |
| Pre-existing bugs are not the author's to fix | Subagents 3 |
| The person defines "done" and reviews the evidence | The agent writes what "done" means before implementing and puts the evidence for each item in the PR, where a person can check it, since it may merge with no one looking (Order of work 1, Git and PRs 4) |

## Where this differs from the post

1. **A breaker instead of a reviewer.** The post tunes one code reviewer. Here the subagent tries to make the change fail by running it and reports only reproduced failures, and it finds weakened tests by running the old versions against the new code. Findings from reading alone drift into nits and future needs, and each costs a round and can pull the change off course. A reproduced failure is evidence and becomes the regression test. One break round of at most 15 commands, run in the background while the checks run and the PR opens, then one rerun on the fixes.
2. **Flaky tests:** a PR that deletes one is not auto-merged. In the post a person sees each PR before merge; here nobody might, so a person checks it was not a real bug.
3. **Commit gate:** skipping needs `Verified: none (<reason>)`, merges and rebases are not gated, and a `verify.sh` change stays blocked after two blocks.
4. **Cheap checks:** the post suggests running tests when Claude finishes. Claude opens and merges the PR in the same turn, so that would be after the merge. Here the hook runs them before `git push`, and only without CI.

## Added beyond the post

1. **Auto-merge** (Merging). Agents merge their own PRs. The latest default branch is merged in first and the result checked again, because PRs that pass alone can break together. The agent asks instead on an unclear conflict, requested changes, an unfixed failure the change caused, a deleted flaky test, or branch protection. Force-pushes need approval.
2. **No duplicated work** (Order of work). Verifying, reviewing, fixing, and verifying again from scratch, then again at merge, made each task take far too long. Each step now runs once, later rounds see only what changed, and PR updates get no new break or verify run.
3. **Fewer tests** (Tests). Tests that mirror the code, check only mocks, or exist for coverage catch no bugs and make refactoring harder. A test is kept only if breaking its behavior makes it fail.
4. **Fewer docs** (Docs). Overviews and summaries tell an agent nothing the code doesn't, go stale, and mislead the next agent.
5. **Invariants checked mechanically** (Tests 9). For logic where a wrong state costs most, an invariant checked over every combination or random operation sequences catches what examples miss, without a model checker.
6. **Environments** (`verify` skill). A change that depends on where it runs is run in each setting it must support, or the gaps are listed.

## Keeping it useful

As the post says, turn misses into guardrails, and prune them. Guardrails here are checks that run, not notes that pile up: written-down lessons get carried into every task and hold back later design.

1. When the same kind of bug gets through twice, add a check that would have caught it: a test or a line in `verify.sh`. A person approves it in a PR.
2. Every PR lists the breaker's results (Git and PRs 4). If it keeps finding nothing, it costs more than it saves.
3. Rules, checks, and tests only grow if you let them. Delete what no longer catches anything.

## Working on Lim_claude

`rules/` becomes the AGENTS.md block; `skills/` and `hooks/` are copied under the repo's `.claude/`. After changing `lim.sh` or the hook, run `tests/test_lim.sh`. It builds scratch repos, runs install, reinstall (including changes on the Lim_claude side), and uninstall, checks that uninstall leaves the repo as it was, and feeds the hook the events Claude Code sends.
