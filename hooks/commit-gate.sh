#!/usr/bin/env bash
# Claude Code PreToolUse hook (matcher: Bash).
# Runs the project's checks before any `git commit` and blocks the commit if they fail.
# Exit 0 allows the command. Exit 2 blocks it, and stderr is shown to Claude.
#
# Which checks run:
#   1. .claude/verify.sh in the repo, if it exists and is executable
#   2. otherwise a guess from the project files (Cargo, Go, npm, pytest)
#   3. otherwise nothing, and the commit is allowed
#
# Skipped (commit allowed without running checks):
#   - during a merge, cherry-pick, revert, or rebase. AGENTS.md asks for one check run after the last merge instead.
#   - when the files are the same as at the last pass in this session (amending a message, splitting one change into commits)

set -uo pipefail

# Without jq the hook cannot read its input, so it stays out of the way.
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
session=$(jq -r '.session_id // "default"' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")

# Only gate git commit (also `git -C dir commit` and `... && git commit`).
grep -Eq '(^|[;&|(]|[[:space:]])git[[:space:]]+(-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*commit([[:space:]]|$)' <<<"$cmd" || exit 0

cd "${CLAUDE_PROJECT_DIR:-$cwd}" 2>/dev/null || exit 0
top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$top" || exit 0

# A change must not edit the check that judges it.
if [ -e .claude/verify.sh ] && [ -n "$(git status --porcelain -- .claude/verify.sh)" ]; then
  echo "Commit blocked: .claude/verify.sh has uncommitted changes. Do not change the checks that judge your change. Ask the user to review and commit verify.sh themselves." >&2
  exit 2
fi

for p in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
  [ -e "$(git rev-parse --git-path "$p")" ] && exit 0
done

if [ -x .claude/verify.sh ]; then
  check='./.claude/verify.sh'
elif [ -f Cargo.toml ]; then
  check='cargo check -q && cargo test -q'
elif [ -f go.mod ]; then
  check='go vet ./... && go test ./...'
elif [ -f package.json ] && jq -e '(.scripts.test // "") as $t | $t != "" and ($t | test("no test specified") | not)' package.json >/dev/null 2>&1; then
  check='npm test --silent'
elif [ -f pytest.ini ] || grep -q '^\[tool\.pytest' pyproject.toml 2>/dev/null; then
  check='python3 -m pytest -q'
else
  exit 0
fi

state="${TMPDIR:-/tmp}/claude-commit-gate-${session//[^A-Za-z0-9_-]/}"

# The files as they are now (ignored files left out), as a git tree id, built in a scratch index.
tree=""
if idx=$(mktemp "${TMPDIR:-/tmp}/claude-commit-gate-index.XXXXXX"); then
  trap 'rm -f "$idx"' EXIT
  cp "$(git rev-parse --git-path index)" "$idx" 2>/dev/null || rm -f "$idx"   # a copy lets git skip unchanged files
  tree=$(GIT_INDEX_FILE="$idx" git add -A 2>/dev/null && GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null) || tree=""
fi
if [ -n "$tree" ] && [ "$(cat "$state.pass" 2>/dev/null)" = "$tree" ]; then
  exit 0
fi

if out=$(bash -c "$check" 2>&1); then
  rm -f "$state"
  if [ -n "$tree" ]; then echo "$tree" >"$state.pass"; fi
  exit 0
fi

n=$(( $(cat "$state" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$state"

{
  echo "Commit blocked: \`$check\` failed (attempt $n)."
  echo "--- last 60 lines ---"
  tail -n 60 <<<"$out"
  echo "---"
  if [ "$n" -ge 3 ]; then
    echo "This check has failed $n times in a row. Stop. Do not commit. Report to the user what fails, what you tried, and your best guess at the cause."
  else
    echo "Fix the code, not the tests or checks. If the failure is flaky or was already failing before your change, stop and tell the user instead of working around it."
  fi
} >&2
exit 2
