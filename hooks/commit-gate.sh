#!/usr/bin/env bash
# Claude Code PreToolUse hook (matcher: Bash).
# Blocks `git commit` when this session has not run the verify skill.
# Exit 0 allows the command. Exit 2 blocks it, and stderr is shown to Claude.
#
# A commit is allowed when any of these hold:
#   - the session ran the verify or code-review skill (read from the transcript)
#   - the commit message says why it was not verified: `Verified: none (<reason>)`
#   - a merge, cherry-pick, revert, or rebase is in progress
#   - commits were already blocked twice in this session, so Claude does not get stuck
#   - the transcript cannot be read, so there is nothing to judge by
# A commit is always blocked while .claude/verify.sh has uncommitted changes.
#
# LIM_COMMIT_GATE=off|observe|enforce (default enforce). observe writes what would have
# been blocked to .git/lim-commit-gate.log and lets the commit through.

set -uo pipefail

# Without jq the hook cannot read its input, so it stays out of the way.
command -v jq >/dev/null 2>&1 || exit 0

mode=${LIM_COMMIT_GATE:-enforce}
[ "$mode" = off ] && exit 0

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
session=$(jq -r '.session_id // "default"' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
transcript=$(jq -r '.transcript_path // ""' <<<"$input")

# Only gate git commit (also `git -C dir commit` and `... && git commit`).
grep -Eq '(^|[;&|(]|[[:space:]])git[[:space:]]+(-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*commit([[:space:]]|$)' <<<"$cmd" || exit 0

cd "${CLAUDE_PROJECT_DIR:-$cwd}" 2>/dev/null || exit 0
top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$top" || exit 0

block() {  # $1: reason for the log, $2: message for Claude
  if [ "$mode" = observe ]; then
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$session" "$1" "$(head -c 200 <<<"$cmd" | tr '\t\n' '  ')" \
      >>"$(git rev-parse --git-path lim-commit-gate.log)"
    exit 0
  fi
  echo "$2" >&2
  exit 2
}

# A change must not edit the check that judges it.
if [ -e .claude/verify.sh ] && [ -n "$(git status --porcelain -- .claude/verify.sh)" ]; then
  block verify.sh-changed "Commit blocked: .claude/verify.sh has uncommitted changes. Do not change the checks that judge your change. Ask the user to review and commit verify.sh themselves."
fi

for p in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
  [ -e "$(git rev-parse --git-path "$p")" ] && exit 0
done

grep -Eq 'Verified:[[:space:]]*none[[:space:]]*\([^)]*[^)[:space:]][^)]*\)' <<<"$cmd" && exit 0

[ -r "$transcript" ] || exit 0
if jq -rR 'fromjson? | select(.type == "assistant") | .message.content[]?
           | select(.type == "tool_use" and .name == "Skill") | .input.skill // empty' "$transcript" 2>/dev/null \
     | grep -Eq '(^|:)(verify|code-review)$' \
   || grep -Eq '<command-name>/?([^<]*:)?(verify|code-review)</command-name>' "$transcript"; then
  exit 0
fi

state="${TMPDIR:-/tmp}/claude-commit-gate-${session//[^A-Za-z0-9_-]/}"
n=$(cat "$state" 2>/dev/null || echo 0)
if [ "$mode" != observe ] && [ "$n" -ge 2 ]; then
  rm -f "$state"
  exit 0
fi
[ "$mode" = observe ] || echo $((n + 1)) >"$state"

block no-verify "Commit blocked: this session has not run the verify skill. Run it before the first commit (AGENTS.md Order of work 2). If this commit does not need verifying, end its message with \`Verified: none (<reason>)\`."
