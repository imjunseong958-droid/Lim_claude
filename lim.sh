#!/usr/bin/env bash
# Lim_claude: put verification rules, a verify skill, and a commit-gate hook into a repo.
# Everything lands inside the target repo. Commit the result and everyone who clones it gets it.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  lim.sh install   [--force] [repo ...]   add or refresh Lim_claude in each repo (default: current dir)
  lim.sh update    [--force] [repo ...]   git pull Lim_claude, then install
  lim.sh uninstall [repo ...]             remove everything install added and restore the old AGENTS.md and CLAUDE.md

install takes over AGENTS.md and removes CLAUDE.md (Claude Code skips AGENTS.md while a CLAUDE.md
exists). The originals are kept under .claude/lim_claude/ and uninstall puts them back.

--force  also replace managed files that were edited inside the repo
EOF
}

SRC=$(cd "$(dirname "$0")" && pwd)
MD_BEGIN='<!-- BEGIN Lim_claude: managed by lim.sh and replaced on update. Put repo-specific rules below the END line. -->'
MD_END='<!-- END Lim_claude -->'
GI_BEGIN='# BEGIN Lim_claude: managed by lim.sh. Lets git track the Lim_claude files under .claude/.'
GI_END='# END Lim_claude'
STATE_REL=.claude/lim_claude
MANIFEST_REL=$STATE_REL/manifest
TAKEOVER="AGENTS.md CLAUDE.md .claude/CLAUDE.md"   # files install replaces or removes; originals are kept
SETTINGS_REL=.claude/settings.json
HOOK_REL=.claude/hooks/commit-gate.sh
HOOK_CMD='"$CLAUDE_PROJECT_DIR"/.claude/hooks/commit-gate.sh'
HAS_HOOK='[.hooks.PreToolUse[]?.hooks[]?.command // empty | select(contains("commit-gate.sh"))] | length > 0'
TMP=${TMPDIR:-/tmp}
force=0
repo=""
manifest=""

say()      { printf '     %s\n' "$*"; }
warn()     { printf '     ! %s\n' "$*" >&2; }
sum()      { cksum <"$1" | awk '{print $1 "-" $2}'; }
tmpfile()  { mktemp "$TMP/lim.XXXXXX"; }
replace()  { cat "$2" >"$1"; rm -f "$2"; }   # overwrite $1 with $2, keeping $1's permissions
recorded() { if [ -f "$manifest" ]; then awk -F'\t' -v p="$1" '$1==p {print $2}' "$manifest"; fi; }
is_git()   { git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; }
ignored()  { git -C "$repo" check-ignore -q --no-index -- "$1" 2>/dev/null; }

# Where install keeps the original of a file it took over. The .orig suffix keeps Claude Code
# from loading the copy as instructions.
orig_rel() { printf '%s/%s.orig' "$STATE_REL" "${1//\//__}"; }
save_orig() {
  local o; o="$repo/$(orig_rel "$1")"
  if [ -e "$o" ]; then warn "$(orig_rel "$1") already exists, so $1 was left as is"; return 1; fi
  cp -p "$repo/$1" "$o"
}

# strip_block FILE BEGIN END: print FILE without the block and without leading or trailing blank lines.
strip_block() {
  awk -v b="$2" -v e="$3" '
    $0==b { skip=1; next }
    skip && $0==e { skip=0; next }
    !skip { line[++n]=$0 }
    END {
      s=1; while (s<=n && line[s] ~ /^[[:space:]]*$/) s++
      while (n>=s && line[n] ~ /^[[:space:]]*$/) n--
      for (i=s; i<=n; i++) print line[i]
    }' "$1"
}

# write_block FILE CONTENT BEGIN END top|bottom. Returns 1 when FILE was already up to date.
write_block() {
  local f=$1 content=$2 begin=$3 end=$4 where=$5 rest out
  rest=$(tmpfile); out=$(tmpfile)
  if [ -f "$f" ]; then strip_block "$f" "$begin" "$end" >"$rest"; fi
  {
    if [ "$where" = bottom ] && [ -s "$rest" ]; then cat "$rest"; echo; fi
    printf '%s\n' "$begin"; cat "$content"; printf '%s\n' "$end"
    if [ "$where" = top ] && [ -s "$rest" ]; then echo; cat "$rest"; fi
  } >"$out"
  rm -f "$rest"
  if [ -f "$f" ] && cmp -s "$out" "$f"; then rm -f "$out"; return 1; fi
  replace "$f" "$out"
}

# remove_block FILE BEGIN END. Deletes FILE if nothing else is left. Returns 1 when there was no block.
remove_block() {
  local f=$1 out
  if [ ! -f "$f" ] || ! grep -qxF "$2" "$f"; then return 1; fi
  out=$(tmpfile)
  strip_block "$f" "$2" "$3" >"$out"
  if [ -s "$out" ]; then replace "$f" "$out"; else rm -f "$f" "$out"; fi
}

# Remove empty directories from $1 upward, stopping at the repo root.
prune() {
  local d=$1
  while [ "$d" != "$repo" ] && [ "$d" != / ] && rmdir "$d" 2>/dev/null; do d=$(dirname "$d"); done
}

# remove_managed PATH SUM: delete a file install wrote, unless it was edited since.
remove_managed() {
  local to="$repo/$1"
  if [ ! -e "$to" ]; then return 0; fi
  if [ "$(sum "$to")" = "$2" ]; then
    rm -f "$to"; say "removed $1"; prune "$(dirname "$to")"
  else
    warn "$1 was edited in this repo; left in place"
  fi
}

# Print .gitignore rules that make each given path trackable. A directory that is ignored gets
# re-included with its other children still ignored, so only the Lim_claude files become visible.
track_rules() {
  local p d rest forced
  for p in "$@"; do
    forced=0; d=""; rest=$p
    while [ "${rest#*/}" != "$rest" ]; do
      d="${d:+$d/}${rest%%/*}"; rest=${rest#*/}
      if [ "$forced" = 1 ] || ignored "$d/"; then printf '!%s/\n%s/*\n' "$d" "$d"; forced=1; fi
    done
    if [ "$forced" = 1 ] || ignored "$p"; then printf '!%s\n' "$p"; fi
  done | awk '!seen[$0]++'
}

# Paths that must be committed for teammates to get Lim_claude.
shared_paths() {
  awk -F'\t' '!/^#/ && NF==2 {print $1}' "$manifest"
  if [ -f "$repo/$SETTINGS_REL" ]; then echo "$SETTINGS_REL"; fi
  echo "$MANIFEST_REL"
  echo .claude/verify.sh   # the repo's own checks; trackable even before someone writes it
  for p in $TAKEOVER; do
    if [ -e "$repo/$(orig_rel "$p")" ]; then orig_rel "$p"; echo; fi
  done
}

install_repo() {
  local version newman list trel from to old content settings out gi rules p
  repo=$1; manifest="$repo/$MANIFEST_REL"
  version=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)
  echo "== install into $repo (Lim_claude $version)"
  mkdir -p "$repo/$STATE_REL"
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
      remove_managed "$trel" "$old"
    done <"$list"
  fi
  rm -f "$list"

  echo "  2. AGENTS.md and CLAUDE.md"
  # The first install takes over AGENTS.md and removes CLAUDE.md, because Claude Code skips
  # AGENTS.md whenever a CLAUDE.md exists. Originals are kept so uninstall can put them back.
  if [ -s "$repo/AGENTS.md" ] && ! grep -qxF "$MD_BEGIN" "$repo/AGENTS.md"; then
    if save_orig AGENTS.md; then
      : >"$repo/AGENTS.md"
      say "moved the old AGENTS.md to $(orig_rel AGENTS.md) (uninstall puts it back)"
    fi
  fi
  for p in CLAUDE.md .claude/CLAUDE.md; do
    if [ -e "$repo/$p" ] && save_orig "$p"; then
      rm -f "$repo/$p"
      say "removed $p so Claude Code reads AGENTS.md; kept it as $(orig_rel "$p") (uninstall puts it back)"
    fi
  done
  if [ -e "$repo/CLAUDE.local.md" ]; then
    warn "CLAUDE.local.md exists, so Claude Code will not read AGENTS.md for whoever has that file"
  fi
  content=$(tmpfile)
  cat "$SRC/rules/base.md" >"$content"
  if [ -f "$repo/Cargo.toml" ]; then
    echo >>"$content"; cat "$SRC/rules/rust.md" >>"$content"
    say "Cargo.toml found, so the Rust rules are included"
  fi
  if write_block "$repo/AGENTS.md" "$content" "$MD_BEGIN" "$MD_END" top; then say "wrote AGENTS.md"; else say "AGENTS.md is up to date"; fi
  rm -f "$content"

  echo "  3. $SETTINGS_REL"
  settings="$repo/$SETTINGS_REL"
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

  echo "  4. .gitignore"
  gi="$repo/.gitignore"
  if ! is_git; then
    say "not a git repository, so skipped"
  else
    remove_block "$gi" "$GI_BEGIN" "$GI_END" || true
    rules=$(tmpfile)
    track_rules $(shared_paths) >"$rules"
    if [ -s "$rules" ]; then
      write_block "$gi" "$rules" "$GI_BEGIN" "$GI_END" bottom || true
      say ".claude/ is ignored here, so rules were added to let git track the Lim_claude files"
    else
      say "nothing to change"
    fi
    rm -f "$rules"
    for p in $(shared_paths); do
      if ignored "$p"; then warn "$p is still ignored by git; check .gitignore"; fi
    done
  fi

  echo "  Done. Review with: git -C \"$repo\" status, then commit."
}

uninstall_repo() {
  local list trel old settings out agents orig p to
  repo=$1; manifest="$repo/$MANIFEST_REL"
  echo "== uninstall from $repo"

  echo "  1. files"
  if [ -f "$manifest" ]; then
    list=$(tmpfile)
    awk -F'\t' '!/^#/ && NF==2' "$manifest" >"$list"
    while IFS=$'\t' read -r trel old; do
      remove_managed "$trel" "$old"
    done <"$list"
    rm -f "$list"
  else
    say "no manifest, so no managed files"
  fi

  echo "  2. AGENTS.md and CLAUDE.md"
  agents="$repo/AGENTS.md"
  if remove_block "$agents" "$MD_BEGIN" "$MD_END"; then
    if [ -e "$agents" ]; then say "removed the Lim_claude block from AGENTS.md"
    elif [ ! -e "$repo/$(orig_rel AGENTS.md)" ]; then say "removed AGENTS.md (nothing else was in it)"; fi
  fi
  for p in $TAKEOVER; do
    orig="$repo/$(orig_rel "$p")"; to="$repo/$p"
    if [ ! -e "$orig" ]; then continue; fi
    if [ "$p" = AGENTS.md ]; then
      # Repo-specific rules written below the block stay, after the original text.
      out=$(tmpfile)
      { cat "$orig"; if [ -s "$to" ]; then echo; cat "$to"; fi; } >"$out"
      replace "$to" "$out"
    elif [ -e "$to" ]; then
      cp -p "$orig" "$to.orig"
      warn "$p exists again, so its original was saved as $p.orig"
    else
      mkdir -p "$(dirname "$to")"
      cp -p "$orig" "$to"
    fi
    rm -f "$orig"
    say "restored the original $p"
  done

  echo "  3. $SETTINGS_REL"
  settings="$repo/$SETTINGS_REL"
  if [ -f "$settings" ] && jq -e "$HAS_HOOK" "$settings" >/dev/null; then
    out=$(tmpfile)
    jq '
      .hooks.PreToolUse |= (map(.hooks |= map(select((.command // "") | contains("commit-gate.sh") | not)))
                            | map(select(.hooks | length > 0)))
      | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end' "$settings" >"$out"
    if [ "$(jq -c . "$out")" = '{}' ]; then
      rm -f "$settings" "$out"; say "removed $SETTINGS_REL (nothing else was in it)"
    else
      replace "$settings" "$out"; say "unregistered the commit-gate hook"
    fi
  fi

  echo "  4. .gitignore"
  if remove_block "$repo/.gitignore" "$GI_BEGIN" "$GI_END"; then say "removed the Lim_claude rules"; else say "nothing to change"; fi

  rm -f "$manifest"
  prune "$repo/$STATE_REL"
  prune "$repo/.claude"
  if [ -e "$repo/.claude/verify.sh" ]; then say ".claude/verify.sh is yours, so it was kept"; fi
  echo "  Done. Review with: git -C \"$repo\" status, then commit."
}

# Resolve a target to the root of its git repo.
resolve() {
  local dir top
  dir=$(cd "$1" 2>/dev/null && pwd) || { echo "not a directory: $1" >&2; return 1; }
  if [ -z "$dir" ] || [ "$dir" = / ]; then echo "refusing to use $1" >&2; return 1; fi
  if top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then dir=$top
  else warn "$dir is not a git repository; using it anyway"; fi
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

# Resolve every target first, so a bad path stops the run before anything is written.
targets=()
case $cmd in
  install|update|uninstall)
    for r in "${repos[@]}"; do d=$(resolve "$r"); targets+=("$d"); done ;;
esac

case $cmd in
  install)
    for d in "${targets[@]}"; do install_repo "$d"; done ;;
  update)
    echo "== git pull in $SRC"
    git -C "$SRC" pull --ff-only
    for d in "${targets[@]}"; do install_repo "$d"; done ;;
  uninstall)
    for d in "${targets[@]}"; do uninstall_repo "$d"; done ;;
  -h|--help|help|"")
    usage ;;
  *)
    echo "unknown command: $cmd" >&2; usage >&2; exit 1 ;;
esac
