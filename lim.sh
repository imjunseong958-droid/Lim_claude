#!/usr/bin/env bash
# Lim_claude: put verification rules, a verify skill, and a commit-gate hook into a repo.
# Everything lands inside the target repo. Commit the result and everyone who clones it gets it.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  lim.sh install   [--force] [repo ...]   add or refresh Lim_claude in each repo (default: current dir)
  lim.sh update    [--force] [repo ...]   git pull Lim_claude, then install
  lim.sh uninstall [repo ...]             remove everything install added

--force  also replace managed files that were edited inside the repo
EOF
}

SRC=$(cd "$(dirname "$0")" && pwd)
BEGIN='<!-- BEGIN Lim_claude: managed by lim.sh. Edit outside this block; changes inside are replaced on update. -->'
END='<!-- END Lim_claude -->'
MANIFEST_REL=.claude/lim_claude.manifest
HOOK_REL=.claude/hooks/commit-gate.sh
HOOK_CMD='"$CLAUDE_PROJECT_DIR"/.claude/hooks/commit-gate.sh'
HAS_HOOK='[.hooks.PreToolUse[]?.hooks[]?.command // empty | select(contains("commit-gate.sh"))] | length > 0'
TMP=${TMPDIR:-/tmp}
force=0

say()      { printf '     %s\n' "$*"; }
warn()     { printf '     ! %s\n' "$*" >&2; }
sum()      { cksum <"$1" | awk '{print $1 "-" $2}'; }
tmpfile()  { mktemp "$TMP/lim.XXXXXX"; }
replace()  { cat "$2" >"$1"; rm -f "$2"; }   # overwrite $1 with $2, keeping $1's permissions
recorded() { if [ -f "$manifest" ]; then awk -F'\t' -v p="$1" '$1==p {print $2}' "$manifest"; fi; }

# Print FILE without the managed block and without leading or trailing blank lines.
strip_block() {
  awk -v b="$BEGIN" -v e="$END" '
    $0==b { skip=1; next }
    skip && $0==e { skip=0; next }
    !skip { line[++n]=$0 }
    END {
      s=1; while (s<=n && line[s] ~ /^[[:space:]]*$/) s++
      while (n>=s && line[n] ~ /^[[:space:]]*$/) n--
      for (i=s; i<=n; i++) print line[i]
    }' "$1"
}

# write_block FILE CONTENT: put CONTENT in the managed block at the end of FILE.
# Returns 1 when FILE was already up to date.
write_block() {
  local f=$1 content=$2 rest out
  rest=$(tmpfile); out=$(tmpfile)
  if [ -f "$f" ]; then strip_block "$f" >"$rest"; fi
  {
    if [ -s "$rest" ]; then cat "$rest"; echo; fi
    printf '%s\n' "$BEGIN"; cat "$content"; printf '%s\n' "$END"
  } >"$out"
  rm -f "$rest"
  if [ -f "$f" ] && cmp -s "$out" "$f"; then rm -f "$out"; return 1; fi
  replace "$f" "$out"
}

# remove_block FILE. Deletes FILE if nothing else is left in it. Returns 1 when there was no block.
remove_block() {
  local f=$1 out
  if [ ! -f "$f" ] || ! grep -qxF "$BEGIN" "$f"; then return 1; fi
  out=$(tmpfile)
  strip_block "$f" >"$out"
  if [ -s "$out" ]; then replace "$f" "$out"; else rm -f "$f" "$out"; fi
}

# Remove empty directories from $2 upward, stopping at the repo root $1.
prune() {
  local d=$2
  while [ "$d" != "$1" ] && [ "$d" != / ] && rmdir "$d" 2>/dev/null; do d=$(dirname "$d"); done
}

# remove_managed REPO PATH SUM: delete a file install wrote, unless it was edited since.
remove_managed() {
  local to="$1/$2"
  if [ ! -e "$to" ]; then return 0; fi
  if [ "$(sum "$to")" = "$3" ]; then
    rm -f "$to"; say "removed $2"; prune "$1" "$(dirname "$to")"
  else
    warn "$2 was edited in this repo; left in place"
  fi
}

install_repo() {
  local repo=$1 version newman list trel from to old content settings out
  manifest="$repo/$MANIFEST_REL"
  version=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)
  echo "== install into $repo (Lim_claude $version)"
  mkdir -p "$repo/.claude"
  newman=$(tmpfile); list=$(tmpfile)
  printf '# Lim_claude %s. Written by lim.sh; do not edit.\n' "$version" >"$newman"

  echo "  1. files"
  (cd "$SRC" && find skills hooks -type f ! -name .DS_Store | sort) >"$list"
  while IFS= read -r rel; do
    trel=".claude/$rel"; from="$SRC/$rel"; to="$repo/$trel"; old=$(recorded "$trel")
    if [ -e "$to" ] && cmp -s "$from" "$to"; then
      printf '%s\t%s\n' "$trel" "$(sum "$to")" >>"$newman"
      continue
    fi
    if [ -e "$to" ] && [ -z "$old" ]; then
      warn "$trel already exists and is not managed by Lim_claude; left as is"
      continue
    fi
    if [ -e "$to" ] && [ "$(sum "$to")" != "$old" ] && [ "$force" != 1 ]; then
      warn "$trel was edited in this repo; left as is (--force replaces it)"
      printf '%s\t%s\n' "$trel" "$old" >>"$newman"
      continue
    fi
    mkdir -p "$(dirname "$to")"
    cp "$from" "$to"
    if [ -x "$from" ]; then chmod +x "$to"; fi
    printf '%s\t%s\n' "$trel" "$(sum "$to")" >>"$newman"
    say "wrote $trel"
  done <"$list"
  # Files an older Lim_claude installed that no longer exist upstream.
  if [ -f "$manifest" ]; then
    awk -F'\t' 'NR==FNR { keep[$1]=1; next } !/^#/ && NF==2 && !($1 in keep)' "$newman" "$manifest" >"$list"
    while IFS=$'\t' read -r trel old; do
      remove_managed "$repo" "$trel" "$old"
    done <"$list"
  fi
  rm -f "$list"

  echo "  2. AGENTS.md"
  content=$(tmpfile)
  cat "$SRC/rules/base.md" >"$content"
  if [ -f "$repo/Cargo.toml" ]; then
    echo >>"$content"; cat "$SRC/rules/rust.md" >>"$content"
    say "Cargo.toml found, so the Rust rules are included"
  fi
  if write_block "$repo/AGENTS.md" "$content"; then say "updated AGENTS.md"; else say "AGENTS.md is up to date"; fi
  rm -f "$content"

  # Claude Code reads AGENTS.md only when the repo has no CLAUDE.md. Never write one; just say so.
  for f in CLAUDE.md .claude/CLAUDE.md; do
    if [ -f "$repo/$f" ] && [ "$(grep -Ec '^@(\./|\.\./)?AGENTS\.md[[:space:]]*$' "$repo/$f")" -eq 0 ]; then
      warn "$f exists, so Claude Code reads it instead of AGENTS.md. Add a line '@AGENTS.md' to $f."
    fi
  done

  echo "  3. .claude/settings.json"
  settings="$repo/.claude/settings.json"
  if ! awk -F'\t' -v p="$HOOK_REL" '$1==p {f=1} END {exit !f}' "$newman"; then
    say "commit-gate.sh is not managed here, so the hook was not registered"
  elif [ -f "$settings" ] && jq -e "$HAS_HOOK" "$settings" >/dev/null; then
    say "commit-gate hook is already registered"
  else
    if [ ! -f "$settings" ]; then echo '{}' >"$settings"; fi
    out=$(tmpfile)
    jq --arg cmd "$HOOK_CMD" '
      .hooks //= {}
      | .hooks.PreToolUse = ((.hooks.PreToolUse // [])
          + [{matcher: "Bash", hooks: [{type: "command", command: $cmd, timeout: 600}]}])' \
      "$settings" >"$out"
    replace "$settings" "$out"
    say "registered the commit-gate hook"
  fi

  replace "$manifest" "$newman"
  echo "  Done. Review with: git -C \"$repo\" status, then commit."
}

uninstall_repo() {
  local repo=$1 list trel old f settings out
  manifest="$repo/$MANIFEST_REL"
  echo "== uninstall from $repo"

  echo "  1. files"
  if [ -f "$manifest" ]; then
    list=$(tmpfile)
    awk -F'\t' '!/^#/ && NF==2' "$manifest" >"$list"
    while IFS=$'\t' read -r trel old; do
      remove_managed "$repo" "$trel" "$old"
    done <"$list"
    rm -f "$list" "$manifest"
  else
    say "no manifest, so no managed files"
  fi

  echo "  2. AGENTS.md"
  if remove_block "$repo/AGENTS.md"; then
    if [ -e "$repo/AGENTS.md" ]; then say "removed the Lim_claude block from AGENTS.md"; else say "removed AGENTS.md (nothing else was in it)"; fi
  else
    say "no Lim_claude block in AGENTS.md"
  fi

  echo "  3. .claude/settings.json"
  settings="$repo/.claude/settings.json"
  if [ -f "$settings" ] && jq -e "$HAS_HOOK" "$settings" >/dev/null; then
    out=$(tmpfile)
    jq '
      .hooks.PreToolUse |= (map(.hooks |= map(select((.command // "") | contains("commit-gate.sh") | not)))
                            | map(select(.hooks | length > 0)))
      | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end' "$settings" >"$out"
    if [ "$(jq -c . "$out")" = '{}' ]; then
      rm -f "$settings" "$out"; say "removed .claude/settings.json (nothing else was in it)"
    else
      replace "$settings" "$out"; say "unregistered the commit-gate hook"
    fi
  fi
  prune "$repo" "$repo/.claude"

  if [ -e "$repo/.claude/verify.sh" ]; then say ".claude/verify.sh is yours, so it was kept"; fi
  echo "  Done. Review with: git -C \"$repo\" status, then commit."
}

# Resolve a target to the root of its git repo.
resolve() {
  local dir top
  dir=$(cd "$1" 2>/dev/null && pwd) || { echo "not a directory: $1" >&2; return 1; }
  if top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then dir=$top
  else warn "$dir is not a git repository; installing there anyway"; fi
  if [ "$dir" = "$SRC" ]; then echo "refusing to install Lim_claude into itself" >&2; return 1; fi
  printf '%s\n' "$dir"
}

cmd=${1:-}
if [ $# -gt 0 ]; then shift; fi
repos=()
for a in "$@"; do
  case $a in
    --force) force=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $a" >&2; usage >&2; exit 1 ;;
    *) repos+=("$a") ;;
  esac
done
if [ ${#repos[@]} -eq 0 ]; then repos=(.); fi

command -v jq >/dev/null || { echo "lim.sh needs jq (macOS: brew install jq, Debian/Ubuntu: apt install jq)" >&2; exit 1; }

case $cmd in
  install)
    for r in "${repos[@]}"; do install_repo "$(resolve "$r")"; done ;;
  update)
    echo "== git pull in $SRC"
    git -C "$SRC" pull --ff-only
    for r in "${repos[@]}"; do install_repo "$(resolve "$r")"; done ;;
  uninstall)
    for r in "${repos[@]}"; do uninstall_repo "$(resolve "$r")"; done ;;
  -h|--help|help|"")
    usage ;;
  *)
    echo "unknown command: $cmd" >&2; usage >&2; exit 1 ;;
esac
