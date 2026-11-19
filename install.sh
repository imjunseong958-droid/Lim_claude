#!/usr/bin/env bash
# Installs this repo into ~/.claude (or $CLAUDE_HOME):
#   1. skills/verify      -> ~/.claude/skills/verify
#   2. hooks/commit-gate  -> ~/.claude/hooks/commit-gate.sh, registered in settings.json
#   3. CLAUDE.md          -> ~/.claude/CLAUDE.md, only if none exists yet
# Anything it replaces is backed up next to the original with a .bak-<timestamp> suffix.
# Safe to run again after `git pull`.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
dest=${CLAUDE_HOME:-$HOME/.claude}
stamp=$(date +%Y%m%d-%H%M%S)

command -v jq >/dev/null || { echo "install.sh needs jq (brew install jq)" >&2; exit 1; }
mkdir -p "$dest/skills" "$dest/hooks"

backup() {
  if [ -e "$1" ]; then
    cp -R "$1" "$1.bak-$stamp"
    echo "    backup: $1.bak-$stamp"
  fi
}

# 1. verify skill
echo "1. verify skill"
if diff -rq "$src/skills/verify" "$dest/skills/verify" >/dev/null 2>&1; then
  echo "    up to date"
else
  backup "$dest/skills/verify"
  rm -rf "$dest/skills/verify"
  cp -R "$src/skills/verify" "$dest/skills/verify"
  echo "    installed: $dest/skills/verify"
fi

# 2. commit-gate hook
echo "2. commit-gate hook"
hook="$dest/hooks/commit-gate.sh"
if cmp -s "$src/hooks/commit-gate.sh" "$hook"; then
  echo "    script up to date"
else
  backup "$hook"
  cp "$src/hooks/commit-gate.sh" "$hook"
  echo "    installed: $hook"
fi
chmod +x "$hook"

settings="$dest/settings.json"
had_settings=0
if [ -f "$settings" ]; then had_settings=1; else echo '{}' >"$settings"; fi
if jq -e '[.. | objects | .command? | strings | select(contains("commit-gate.sh"))] | length > 0' "$settings" >/dev/null; then
  echo "    already registered in $settings"
else
  if [ "$had_settings" = 1 ]; then backup "$settings"; fi
  entry=$(jq -n --arg cmd "\"$hook\"" \
    '{matcher: "Bash", hooks: [{type: "command", command: $cmd, timeout: 600}]}')
  tmp=$(mktemp "$settings.XXXXXX")
  jq --argjson e "$entry" '.hooks //= {} | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$e])' \
    "$settings" >"$tmp" && mv "$tmp" "$settings"
  echo "    registered in $settings"
fi

# 3. global CLAUDE.md
echo "3. CLAUDE.md"
if [ ! -e "$dest/CLAUDE.md" ]; then
  cp "$src/CLAUDE.md" "$dest/CLAUDE.md"
  echo "    installed: $dest/CLAUDE.md"
elif cmp -s "$src/CLAUDE.md" "$dest/CLAUDE.md"; then
  echo "    up to date"
else
  echo "    $dest/CLAUDE.md already exists and differs. Not touched."
  echo "    Compare with: diff \"$dest/CLAUDE.md\" \"$src/CLAUDE.md\""
fi

echo
echo "Done. Start a new Claude Code session to pick up the changes."
