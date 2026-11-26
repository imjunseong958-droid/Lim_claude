#!/usr/bin/env bash
# Round-trip tests for lim.sh. Usage: tests/test_lim.sh [path/to/Lim_claude] (default: this repo)
set -u
R=${1:-$(cd "$(dirname "$0")/.." && pwd)}
T=$(mktemp -d "${TMPDIR:-/tmp}/limtest.XXXX")
pass=0; fail=0
ok()   { echo "  PASS $*"; pass=$((pass+1)); }
bad()  { echo "  FAIL $*"; fail=$((fail+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
mkrepo(){ git init -q "$1" && git -C "$1" config user.email t@t && git -C "$1" config user.name t; }
snap() { (cd "$1" && find . -path ./.git -prune -o -type f -print | sort | while read -r f; do printf '%s %s\n' "$(cksum <"$f")" "$f"; done); }
ST=.claude/lim_claude

echo "== A. fresh Rust repo: install, reinstall, uninstall =="
A="$T/a"; mkrepo "$A"; echo '[package]' > "$A/Cargo.toml"; git -C "$A" add -A; git -C "$A" commit -qm init
before=$(snap "$A")
(cd "$A" && "$R/lim.sh" install) > "$T/a.out" 2>&1; rc=$?
check "install exit 0" '[ $rc -eq 0 ]'
check "AGENTS.md starts with block and has Rust rules" 'head -1 "$A/AGENTS.md" | grep -q "BEGIN Lim_claude" && grep -q "^## Rust" "$A/AGENTS.md"'
check "only AGENTS.md and the manifest written" '[ "$(cd "$A" && git status --porcelain -uall | sort | tr "\n" " ")" = "?? .claude/lim_claude/manifest ?? AGENTS.md " ]'
check "manifest lists no files" '[ "$(grep -vc "^#" "$A/$ST/manifest")" -eq 0 ]'
after1=$(snap "$A")
"$R/lim.sh" install "$A" > "$T/a2.out" 2>&1
check "reinstall changes nothing" '[ "$(snap "$A")" = "$after1" ]'
"$R/lim.sh" uninstall "$A" > "$T/a3.out" 2>&1
check "uninstall restores repo exactly" '[ "$(snap "$A")" = "$before" ]'
check "no .claude dir left" '[ ! -e "$A/.claude" ]'

echo "== B. Moza-like: .claude/ ignored, old AGENTS.md, CLAUDE.md, .claude/CLAUDE.md, worktrees =="
B="$T/b"; mkrepo "$B"
printf 'node_modules/\n.claude/\n*.tmp\n.DS_Store\n' > "$B/.gitignore"
printf '## Subagents\n\nDo not spawn subagents unless I ask.\n' > "$B/AGENTS.md"
printf '# Claude stuff\n' > "$B/CLAUDE.md"
git -C "$B" add -A; git -C "$B" commit -qm init
mkdir -p "$B/.claude/worktrees/w" "$B/.claude/skills/mine"
echo '{}' > "$B/.claude/launch.json"; echo x > "$B/.claude/worktrees/w/f"; echo mine > "$B/.claude/skills/mine/SKILL.md"
printf 'dot claude md\n' > "$B/.claude/CLAUDE.md"
before=$(snap "$B")
"$R/lim.sh" install "$B" > "$T/b.out" 2>&1; rc=$?
check "install exit 0" '[ $rc -eq 0 ]'
check "old AGENTS.md moved to .orig" '[ "$(cat "$B/$ST/AGENTS.md.orig")" = "$(printf "## Subagents\n\nDo not spawn subagents unless I ask.")" ]'
check "AGENTS.md is only the block" '[ "$(head -1 "$B/AGENTS.md" | grep -c "BEGIN Lim_claude")" -eq 1 ] && [ "$(tail -1 "$B/AGENTS.md")" = "<!-- END Lim_claude -->" ]'
check "CLAUDE.md removed, original kept" '[ ! -e "$B/CLAUDE.md" ] && [ "$(cat "$B/$ST/CLAUDE.md.orig")" = "# Claude stuff" ]'
check ".claude/CLAUDE.md removed, original kept" '[ ! -e "$B/.claude/CLAUDE.md" ] && [ "$(cat "$B/$ST/.claude__CLAUDE.md.orig")" = "dot claude md" ]'
git -C "$B" add -A
tracked=$(git -C "$B" diff --cached --name-only | sort | tr '\n' ' ')
echo "    staged: $tracked"
check "git tracks the Lim_claude files" '(for f in $ST/manifest $ST/AGENTS.md.orig $ST/CLAUDE.md.orig $ST/.claude__CLAUDE.md.orig; do echo "$tracked" | grep -q "$f" || exit 1; done)'
check "git still ignores worktrees, launch.json, other skills" '! echo "$tracked" | grep -q "worktrees\|launch.json\|skills/mine"'
git -C "$B" reset -q
"$R/lim.sh" install "$B" > "$T/b2.out" 2>&1
check "reinstall keeps one .gitignore block" '[ "$(grep -c "BEGIN Lim_claude" "$B/.gitignore")" -eq 1 ]'
"$R/lim.sh" uninstall "$B" > "$T/b3.out" 2>&1; rc=$?
check "uninstall exit 0" '[ $rc -eq 0 ]'
check "uninstall restores repo exactly" '[ "$(snap "$B")" = "$before" ]'
echo "    (uninstall output)"; sed 's/^/    /' "$T/b3.out"

echo "== C. an install from an older version: install and uninstall remove the skill, the hook, and its registration =="
hookjq='{type: "command", command: "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/commit-gate.sh"}'
old_install(){   # what an older Lim_claude left in repo $1; $2 is the user's own settings.json
  "$R/lim.sh" install "$1" >/dev/null 2>&1
  mkdir -p "$1/.claude/skills/verify" "$1/.claude/hooks"
  echo skill > "$1/.claude/skills/verify/SKILL.md"; printf '#!/bin/sh\nexit 0\n' > "$1/.claude/hooks/commit-gate.sh"
  for f in .claude/skills/verify/SKILL.md .claude/hooks/commit-gate.sh; do
    printf '%s\t%s\n' "$f" "$(cksum <"$1/$f" | awk '{print $1 "-" $2}')" >> "$1/$ST/manifest"
  done
  jq -n "($2) | .hooks.PreToolUse += [{matcher: \"Bash\", hooks: [$hookjq]}] | .hooks.PostToolUse += [{matcher: \"Skill\", hooks: [$hookjq]}]
         | .hooks.UserPromptSubmit += [{hooks: [$hookjq]}]" > "$1/.claude/settings.json"
}
C="$T/c"; mkrepo "$C"; git -C "$C" commit -q --allow-empty -m init
before=$(snap "$C"); "$R/lim.sh" install "$C" >/dev/null 2>&1; fresh_install=$(snap "$C"); "$R/lim.sh" uninstall "$C" >/dev/null 2>&1
old_install "$C" '{}'
"$R/lim.sh" install "$C" > "$T/c.out" 2>&1; rc=$?
check "install exit 0" '[ $rc -eq 0 ]'
check "skill, hook, and settings.json removed: same as a fresh install" '[ "$(snap "$C")" = "$fresh_install" ] && grep -q "removed .claude/settings.json" "$T/c.out"'
"$R/lim.sh" install "$C" > "$T/c2.out" 2>&1
check "next install has nothing to remove" 'grep -q "nothing to remove" "$T/c2.out"'
C2="$T/c2"; mkrepo "$C2"; git -C "$C2" commit -q --allow-empty -m init
old_install "$C2" '{permissions: {allow: ["Bash(ls:*)"]}, hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "mine.sh"}]}]}}'
echo tweak >> "$C2/.claude/skills/verify/SKILL.md"
"$R/lim.sh" install "$C2" > "$T/c3.out" 2>&1
check "the user's settings kept, the hook unregistered" 'jq -e "[.permissions.allow, [.hooks[][].hooks[].command]] == [[\"Bash(ls:*)\"], [\"mine.sh\"]]" "$C2/.claude/settings.json" >/dev/null'
check "an edited leftover is kept with a warning, an unedited one removed" 'grep -q tweak "$C2/.claude/skills/verify/SKILL.md" && grep -q "was edited" "$T/c3.out" && [ ! -e "$C2/.claude/hooks" ]'
C3="$T/c3"; mkrepo "$C3"; git -C "$C3" commit -q --allow-empty -m init
before=$(snap "$C3"); old_install "$C3" '{}'
"$R/lim.sh" uninstall "$C3" > "$T/c4.out" 2>&1; rc=$?
check "uninstall of an older install restores repo exactly" '[ $rc -eq 0 ] && [ "$(snap "$C3")" = "$before" ]'

echo "== D. upstream changes and repo-specific rules below the block =="
L="$T/lim"; mkdir "$L"; (cd "$R" && tar cf - --exclude .git .) | (cd "$L" && tar xf -)
D="$T/d"; mkrepo "$D"; printf 'Mine.\n' > "$D/AGENTS.md"; git -C "$D" add -A; git -C "$D" commit -qm init
"$L/lim.sh" install "$D" >/dev/null 2>&1
printf '\n## Moza only\n\n1. Extra rule.\n' >> "$D/AGENTS.md"
echo "10. New rule." >> "$L/rules/base.md"
"$L/lim.sh" install "$D" > "$T/d.out" 2>&1
check "block updated once, repo rules kept below" '[ "$(grep -c "BEGIN Lim_claude" "$D/AGENTS.md")" -eq 1 ] && grep -q "10. New rule." "$D/AGENTS.md" && [ "$(tail -1 "$D/AGENTS.md")" = "1. Extra rule." ]'
"$L/lim.sh" uninstall "$D" >/dev/null 2>&1
check "uninstall: original first, then repo rules" '[ "$(cat "$D/AGENTS.md")" = "$(printf "Mine.\n\n## Moza only\n\n1. Extra rule.")" ]'

echo "== E. guards =="
"$R/lim.sh" install "$R" > "$T/f.out" 2>&1; rc=$?
check "refuses to install into itself" '[ $rc -ne 0 ] && grep -q "into itself" "$T/f.out"'
"$R/lim.sh" install "$T/does-not-exist" > "$T/f2.out" 2>&1; rc=$?
check "bad path stops before writing" '[ $rc -ne 0 ] && grep -q "not a directory" "$T/f2.out" && ! grep -q "== install" "$T/f2.out"'
"$R/lim.sh" bogus > /dev/null 2>&1; rc=$?
check "unknown command exits non-zero" '[ $rc -ne 0 ]'

echo "== F. no temp files left behind =="
G="$T/g"; mkrepo "$G"; git -C "$G" commit -q --allow-empty -m init
GT="$T/gtmp"; mkdir "$GT"
TMPDIR="$GT" "$R/lim.sh" install "$G" >/dev/null 2>&1; TMPDIR="$GT" "$R/lim.sh" uninstall "$G" >/dev/null 2>&1
check "normal install and uninstall leave none" '[ -z "$(ls -A "$GT")" ]'
H="$T/h"; mkrepo "$H"; git -C "$H" commit -q --allow-empty -m init; touch "$H/.claude"   # fails after temp files exist
TMPDIR="$GT" "$R/lim.sh" install "$H" >/dev/null 2>&1; rc=$?
check "failed install leaves none" '[ $rc -ne 0 ] && [ -z "$(ls -A "$GT")" ]'
TMPDIR="$GT" "$R/lim.sh" install "$G" 2>/dev/null | head -1 >/dev/null; rc=${PIPESTATUS[0]}
check "install cut off by a closed pipe dies by SIGPIPE (141)" '[ $rc -eq 141 ]'
check "install cut off by a closed pipe leaves none" '[ -z "$(ls -A "$GT")" ]'
TMPDIR="/nonexistent" "$R/lim.sh" --help >/dev/null 2>&1; rc=$?
check "--help needs no temp dir" '[ $rc -eq 0 ]'

echo "== G. called through a symlink =="
L2="$T/lim2"; mkdir "$L2"; (cd "$R" && tar cf - --exclude .git .) | (cd "$L2" && tar xf -); git init -q "$L2"; ln -s "$L2" "$T/limlink"
"$T/limlink/lim.sh" install "$T/limlink" > "$T/h.out" 2>&1; rc=$?
check "refuses to install into itself through a symlink" '[ $rc -ne 0 ] && grep -q "into itself" "$T/h.out" && [ ! -e "$L2/AGENTS.md" ]'

echo "== H. CI note =="
J="$T/j"; mkrepo "$J"; git -C "$J" commit -q --allow-empty -m init
"$R/lim.sh" install "$J" > "$T/j.out" 2>&1
mkdir -p "$J/.github/workflows"; touch "$J/.github/workflows/ci.yml"
"$R/lim.sh" install "$J" > "$T/j2.out" 2>&1
check "install says to require CI, and not an up-to-date branch, only in a repo with CI" '! grep -q "required status check" "$T/j.out" && grep -q "required status check" "$T/j2.out" && grep -q "up to date\" off" "$T/j2.out"'

echo
echo "passed $pass, failed $fail"
rm -rf "$T"
[ "$fail" -eq 0 ]
