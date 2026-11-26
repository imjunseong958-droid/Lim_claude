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
check "skill installed" '[ -f "$A/.claude/skills/verify/SKILL.md" ]'
check "hook installed and executable" '[ -x "$A/.claude/hooks/commit-gate.sh" ]'
check "AGENTS.md starts with block and has Rust rules" 'head -1 "$A/AGENTS.md" | grep -q "BEGIN Lim_claude" && grep -q "^## Rust" "$A/AGENTS.md"'
check "no CLAUDE.md created" '[ ! -e "$A/CLAUDE.md" ]'
check "settings has hook" 'jq -e ".hooks.PreToolUse[0].hooks[0].command == \"\\\"\$CLAUDE_PROJECT_DIR\\\"/.claude/hooks/commit-gate.sh\"" "$A/.claude/settings.json" >/dev/null'
check "hook registered for Bash, Skill, and prompts" 'jq -e "[.hooks.PreToolUse[0].matcher, .hooks.PostToolUse[0].matcher, (.hooks.UserPromptSubmit[0].hooks[0].command | contains(\"commit-gate.sh\"))] == [\"Bash\", \"Skill\", true]" "$A/.claude/settings.json" >/dev/null'
check "manifest lists 2 files" '[ "$(grep -vc "^#" "$A/$ST/manifest")" -eq 2 ]'
check "no .gitignore needed" '[ ! -e "$A/.gitignore" ]'
after1=$(snap "$A")
"$R/lim.sh" install "$A" > "$T/a2.out" 2>&1
check "reinstall changes nothing" '[ "$(snap "$A")" = "$after1" ]'
jq '.hooks |= {PreToolUse}' "$A/.claude/settings.json" > "$T/old.json"; cp "$T/old.json" "$A/.claude/settings.json"   # an install from before the Skill and prompt hooks
"$R/lim.sh" install "$A" > "$T/a4.out" 2>&1
check "reinstall adds the missing hook registrations" '[ "$(snap "$A")" = "$after1" ] && grep -q "registered the commit-gate hook" "$T/a4.out"'
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
check "git tracks the Lim_claude files" '(for f in .claude/hooks/commit-gate.sh .claude/skills/verify/SKILL.md .claude/settings.json $ST/manifest $ST/AGENTS.md.orig $ST/CLAUDE.md.orig $ST/.claude__CLAUDE.md.orig; do echo "$tracked" | grep -q "$f" || exit 1; done)'
check "git still ignores worktrees, launch.json, other skills" '! echo "$tracked" | grep -q "worktrees\|launch.json\|skills/mine"'
git -C "$B" reset -q
printf '#!/bin/sh\nexit 0\n' > "$B/.claude/verify.sh"
check "a verify.sh written later is visible to git" '[ "$(git -C "$B" status --porcelain -- .claude/verify.sh)" = "?? .claude/verify.sh" ]'
rm "$B/.claude/verify.sh"
"$R/lim.sh" install "$B" > "$T/b2.out" 2>&1
check "reinstall keeps one .gitignore block" '[ "$(grep -c "BEGIN Lim_claude" "$B/.gitignore")" -eq 1 ]'
"$R/lim.sh" uninstall "$B" > "$T/b3.out" 2>&1; rc=$?
check "uninstall exit 0" '[ $rc -eq 0 ]'
check "uninstall restores repo exactly" '[ "$(snap "$B")" = "$before" ]'
echo "    (uninstall output)"; sed 's/^/    /' "$T/b3.out"

echo "== C. edited managed files, --force =="
C="$T/c"; mkrepo "$C"; git -C "$C" commit -q --allow-empty -m init
"$R/lim.sh" install "$C" >/dev/null 2>&1
echo "# local tweak" >> "$C/.claude/hooks/commit-gate.sh"
"$R/lim.sh" install "$C" > "$T/c.out" 2>&1
check "edited file kept on install" 'tail -1 "$C/.claude/hooks/commit-gate.sh" | grep -q "local tweak" && grep -q "was edited" "$T/c.out"'
"$R/lim.sh" install --force "$C" > "$T/c2.out" 2>&1
check "--force replaces it" 'cmp -s "$R/hooks/commit-gate.sh" "$C/.claude/hooks/commit-gate.sh"'
echo "tweak" >> "$C/.claude/skills/verify/SKILL.md"
"$R/lim.sh" uninstall "$C" > "$T/c3.out" 2>&1
check "uninstall keeps edited skill" 'grep -q tweak "$C/.claude/skills/verify/SKILL.md" && grep -q "left in place" "$T/c3.out"'
check "uninstall removes unedited hook" '[ ! -e "$C/.claude/hooks/commit-gate.sh" ] && [ ! -d "$C/.claude/hooks" ]'

echo "== D. upstream changes and repo-specific rules below the block =="
L="$T/lim"; mkdir "$L"; (cd "$R" && tar cf - --exclude .git .) | (cd "$L" && tar xf -)
D="$T/d"; mkrepo "$D"; printf 'Mine.\n' > "$D/AGENTS.md"; git -C "$D" add -A; git -C "$D" commit -qm init
before=$(snap "$D")
printf '#!/bin/sh\necho extra\n' > "$L/hooks/extra.sh"; chmod +x "$L/hooks/extra.sh"
"$L/lim.sh" install "$D" >/dev/null 2>&1
check "new upstream file installed" '[ -x "$D/.claude/hooks/extra.sh" ]'
printf '\n## Moza only\n\n1. Extra rule.\n' >> "$D/AGENTS.md"
rm "$L/hooks/extra.sh"; echo "10. New rule." >> "$L/rules/base.md"
"$L/lim.sh" install "$D" > "$T/d.out" 2>&1
check "file dropped upstream is removed" '[ ! -e "$D/.claude/hooks/extra.sh" ] && grep -q "removed .claude/hooks/extra.sh" "$T/d.out"'
check "block updated once, repo rules kept below" '[ "$(grep -c "BEGIN Lim_claude" "$D/AGENTS.md")" -eq 1 ] && grep -q "10. New rule." "$D/AGENTS.md" && [ "$(tail -1 "$D/AGENTS.md")" = "1. Extra rule." ]'
"$L/lim.sh" uninstall "$D" >/dev/null 2>&1
check "uninstall: original first, then repo rules" '[ "$(cat "$D/AGENTS.md")" = "$(printf "Mine.\n\n## Moza only\n\n1. Extra rule.")" ]'

echo "== E. registered hook command runs from settings =="
E="$T/e"; mkrepo "$E"; git -C "$E" commit -q --allow-empty -m init
"$R/lim.sh" install "$E" >/dev/null 2>&1
printf '#!/bin/sh\nexit 0\n' > "$E/.claude/verify.sh"; chmod +x "$E/.claude/verify.sh"
git -C "$E" add -A; git -C "$E" commit -qm setup
cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$E/.claude/settings.json")
hook(){ CLAUDE_PROJECT_DIR="$E" sh -c "$cmd" 2>"$T/e.err"; }   # event JSON on stdin, as Claude Code sends it
bash_ev(){ jq -n --arg s "$1" --arg c "$E" --arg m "$2" '{hook_event_name:"PreToolUse", session_id:$s, cwd:$c, tool_name:"Bash", tool_input:{command:$m}}' | hook; }
skill_ev(){ jq -n --arg s "$1" --arg k "$2" '{hook_event_name:"PostToolUse", session_id:$s, tool_name:"Skill", tool_input:{skill:$k}}' | hook; }
prompt_ev(){ jq -n --arg s "$1" --arg p "$2" '{hook_event_name:"UserPromptSubmit", session_id:$s, prompt:$p}' | hook; }
commit="git commit -m x"
bash_ev s1-$$ "$commit"; rc=$?
check "no verify in the session: commit blocked (rc=2)" '[ $rc -eq 2 ] && grep -q "has not run the verify skill" "$T/e.err"'
bash_ev s1-$$ "$commit"; r2=$?; bash_ev s1-$$ "$commit"; r3=$?
check "after two blocks the next commit goes through" '[ $r2 -eq 2 ] && [ $r3 -eq 0 ]'
skill_ev s2-$$ verify; bash_ev s2-$$ "$commit"; rc=$?
check "Claude ran the verify skill: commit allowed" '[ $rc -eq 0 ]'
prompt_ev s3-$$ "verify it works"; bash_ev s3-$$ "$commit"; r1=$?
pout=$(prompt_ev s3-$$ "/verify"); bash_ev s3-$$ "$commit"; r2=$?
check "user typed /verify: commit allowed (a prompt that only mentions verify is not)" '[ $r1 -eq 2 ] && [ $r2 -eq 0 ]'
check "prompt hook prints nothing into Claude's context" '[ -z "$pout" ]'
bash_ev s4-$$ 'git commit -m Docs -m "Verified: none (docs only)"'; r1=$?
bash_ev s4-$$ 'git commit -m Docs -m "Verified: none"'; r2=$?
check "Verified: none with a reason allowed, without one blocked" '[ $r1 -eq 0 ] && [ $r2 -eq 2 ]'
skill_ev s5-$$ verify; echo "# edited" >> "$E/.claude/verify.sh"; bash_ev s5-$$ "$commit"; rc=$?
check "uncommitted verify.sh change blocks even after verify" '[ $rc -eq 2 ] && grep -q "verify.sh has uncommitted" "$T/e.err"'
git -C "$E" checkout -q -- .claude/verify.sh
echo x > "$E/f"; git -C "$E" add f; git -C "$E" commit -qm f
git -C "$E" checkout -qb side; echo side > "$E/f"; git -C "$E" commit -qam side
git -C "$E" checkout -q -; echo main > "$E/f"; git -C "$E" commit -qam main
git -C "$E" merge side >/dev/null 2>&1; echo merged > "$E/f"; git -C "$E" add f
bash_ev s6-$$ "$commit"; rc=$?
check "commit during a merge: allowed" '[ $rc -eq 0 ]'
git -C "$E" merge --abort
LIM_COMMIT_GATE=observe bash_ev s7-$$ "$commit"; rc=$?
check "observe mode logs instead of blocking" '[ $rc -eq 0 ] && grep -q no-verify "$E/.git/lim-commit-gate.log"'
printf '#!/bin/sh\necho boom; exit 1\n' > "$E/.claude/verify.sh"; git -C "$E" commit -qam failing-check
bash_ev s8-$$ "git push"; rc=$?
check "failing check blocks push (rc=2)" '[ $rc -eq 2 ] && grep -q boom "$T/e.err"'
skill_ev s9-$$ verify; bash_ev s9-$$ "$commit && git push"; rc=$?
check "commit && push in one command: push still gated" '[ $rc -eq 2 ] && grep -q "Push blocked" "$T/e.err"'
mkdir -p "$E/.github/workflows"; touch "$E/.github/workflows/ci.yml"; bash_ev s10-$$ "git push"; rc=$?
check "repo with CI: push not gated" '[ $rc -eq 0 ]'
rm -r "$E/.github"
runs(){ wc -l < "$T/e.runs" | tr -d ' '; }
printf '#!/bin/sh\necho run >> "%s"\n' "$T/e.runs" > "$E/.claude/verify.sh"; git -C "$E" commit -qam counting
bash_ev s11-$$ "git push"; bash_ev s11-$$ "git push"; rc=$?
check "same files after a pass: checks run once" '[ $rc -eq 0 ] && [ "$(runs)" = 1 ]'
echo y > "$E/new"; bash_ev s11-$$ "git push"
check "changed files: checks run again" '[ "$(runs)" = 2 ]'
"$R/lim.sh" uninstall "$E" > "$T/e2.out" 2>&1
check "uninstall keeps user verify.sh" '[ -x "$E/.claude/verify.sh" ] && grep -q "is yours" "$T/e2.out"'
rm -f "${TMPDIR:-/tmp}"/claude-commit-gate-s*-$$*

echo "== F. guards =="
"$R/lim.sh" install "$R" > "$T/f.out" 2>&1; rc=$?
check "refuses to install into itself" '[ $rc -ne 0 ] && grep -q "into itself" "$T/f.out"'
"$R/lim.sh" install "$T/does-not-exist" > "$T/f2.out" 2>&1; rc=$?
check "bad path stops before writing" '[ $rc -ne 0 ] && grep -q "not a directory" "$T/f2.out" && ! grep -q "== install" "$T/f2.out"'
"$R/lim.sh" bogus > /dev/null 2>&1; rc=$?
check "unknown command exits non-zero" '[ $rc -ne 0 ]'

echo "== G. no temp files left behind =="
G="$T/g"; mkrepo "$G"; git -C "$G" commit -q --allow-empty -m init
GT="$T/gtmp"; mkdir "$GT"
TMPDIR="$GT" "$R/lim.sh" install "$G" >/dev/null 2>&1; TMPDIR="$GT" "$R/lim.sh" uninstall "$G" >/dev/null 2>&1
check "normal install and uninstall leave none" '[ -z "$(ls -A "$GT")" ]'
H="$T/h"; mkrepo "$H"; git -C "$H" commit -q --allow-empty -m init; mkdir "$H/.claude"; touch "$H/.claude/hooks"   # fails after temp files exist
TMPDIR="$GT" "$R/lim.sh" install "$H" >/dev/null 2>&1; rc=$?
check "failed install leaves none" '[ $rc -ne 0 ] && [ -z "$(ls -A "$GT")" ]'
TMPDIR="$GT" "$R/lim.sh" install "$G" 2>/dev/null | head -1 >/dev/null; rc=${PIPESTATUS[0]}
check "install cut off by a closed pipe dies by SIGPIPE (141)" '[ $rc -eq 141 ]'
check "install cut off by a closed pipe leaves none" '[ -z "$(ls -A "$GT")" ]'
TMPDIR="/nonexistent" "$R/lim.sh" --help >/dev/null 2>&1; rc=$?
check "--help needs no temp dir" '[ $rc -eq 0 ]'

echo "== H. called through a symlink =="
L2="$T/lim2"; mkdir "$L2"; (cd "$R" && tar cf - --exclude .git .) | (cd "$L2" && tar xf -); git init -q "$L2"; ln -s "$L2" "$T/limlink"
"$T/limlink/lim.sh" install "$T/limlink" > "$T/h.out" 2>&1; rc=$?
check "refuses to install into itself through a symlink" '[ $rc -ne 0 ] && grep -q "into itself" "$T/h.out" && [ ! -e "$L2/AGENTS.md" ]'

echo "== I. the checkout a command works in, ways of writing git commit, updates to a PR =="
I="$T/i"; mkrepo "$I"; git -C "$I" symbolic-ref HEAD refs/heads/main
"$R/lim.sh" install "$I" >/dev/null 2>&1
printf '#!/bin/sh\nexit 0\n' > "$I/.claude/verify.sh"; chmod +x "$I/.claude/verify.sh"
echo a > "$I/f"; git -C "$I" add -A; git -C "$I" commit -qm setup
W="$T/i-wt"; git -C "$I" worktree add -q -b work "$W"
S="$T/i sp"; git -C "$I" worktree add -q -b spaced "$S"
icmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$I/.claude/settings.json")
# In a worktree session, Claude Code's project folder is the main checkout; the command runs in the worktree.
ihook(){ CLAUDE_PROJECT_DIR="$I" sh -c "$icmd" 2>"$T/i.err"; }
iev(){ jq -n --arg s "$1" --arg c "$2" --arg m "$3" '{hook_event_name:"PreToolUse", session_id:$s, cwd:$c, tool_name:"Bash", tool_input:{command:$m}}' | ihook; }
iskill(){ jq -n --arg s "$1" '{hook_event_name:"PostToolUse", session_id:$s, tool_name:"Skill", tool_input:{skill:"verify"}}' | ihook; }
n=0; fresh(){ n=$((n+1)); sid="i$n-$$"; }   # a new session in $sid, with no blocks counted yet
echo side > "$W/f"; git -C "$W" commit -qam side; echo main > "$I/f"; git -C "$I" commit -qam main
git -C "$W" merge main >/dev/null 2>&1; echo merged > "$W/f"; git -C "$W" add f
fresh; iev "$sid" "$W" "git commit --no-edit"; rc=$?
check "merge commit in a worktree: allowed" '[ $rc -eq 0 ]'
git -C "$W" merge --abort
fresh; s=$sid; iskill "$s"; echo "# x" >> "$W/.claude/verify.sh"
iev "$s" "$W" "git commit -am x"; r1=$?; iev "$s" "$I" "git -C $W commit -am x"; r2=$?
check "verify.sh edited in the worktree: blocked, also through git -C" '[ $r1 -eq 2 ] && [ $r2 -eq 2 ] && grep -q "verify.sh has uncommitted" "$T/i.err"'
git -C "$W" checkout -q -- .claude/verify.sh; echo "# mine" >> "$I/.claude/verify.sh"
iev "$s" "$W" "git commit -m x"; rc=$?
check "the user's verify.sh edit in the main checkout does not block the worktree" '[ $rc -eq 0 ]'
git -C "$I" checkout -q -- .claude/verify.sh
git -C "$W" rm -q .claude/verify.sh; iev "$s" "$W" "git commit -m x"; r1=$?; git -C "$W" reset -q --hard
git -C "$W" mv .claude/verify.sh .claude/v.bak; iev "$s" "$W" "git commit -m x"; r2=$?; git -C "$W" reset -q --hard
check "deleting or renaming verify.sh: blocked" '[ $r1 -eq 2 ] && [ $r2 -eq 2 ]'
for form in '/usr/bin/git commit -m x' "bash -c 'git commit -m x'" "git -C \"$S\" commit -m x" \
            'git -c user.name="A B" commit -m x' 'git commit;git push' '(git commit)'; do
  fresh; iev "$sid" "$W" "$form"; rc=$?
  check "gated: $form" '[ $rc -eq 2 ] && grep -q "has not run the verify skill" "$T/i.err"'
done
fresh; iev "$sid" "$W" 'git commit-tree HEAD^{tree} -m x'; r1=$?; fresh; iev "$sid" "$W" 'git log --grep commit'; r2=$?
check "not gated: git commit-tree, git log --grep commit" '[ $r1 -eq 0 ] && [ $r2 -eq 0 ]'
printf 'Docs\n\nVerified: none (docs only)\n' > "$W/msg"; printf 'Docs\n' > "$W/bare"
fresh; iev "$sid" "$W" "git commit -F msg"; r1=$?; fresh; iev "$sid" "$W" "git commit --file=msg"; r2=$?
fresh; iev "$sid" "$W" "git commit -F bare"; r3=$?; fresh; iev "$sid" "$W" "git commit -aF msg"; r4=$?
check "Verified: none in a -F message file: allowed; a file without it: blocked" '[ $r1 -eq 0 ] && [ $r2 -eq 0 ] && [ $r3 -eq 2 ] && [ $r4 -eq 0 ]'
fresh; iev "$sid" "$W" "git commit -am x && grep -n -F AGENTS.md README.md"; rc=$?
check "a -F of another command is not read as the message" '[ $rc -eq 2 ]'
rm -f "$W/msg" "$W/bare"
fresh; iskill "$sid"; iev "$sid" "$W" 'git commit -m g -m "Verified: cargo test -q passed"'; r0=$?
echo w > "$W/g"; git -C "$W" add g; git -C "$W" commit -qm g -m "Verified: cargo test -q passed"
fresh; iev "$sid" "$W" 'git commit -m fix -m "Verified: the related tests passed"'; rc=$?
check "update, in a new session, to a branch a verified session committed on: allowed" '[ $r0 -eq 0 ] && [ $rc -eq 0 ]'
echo d > "$S/d"; git -C "$S" add d; git -C "$S" commit -qm d -m "Verified: cargo test -q passed"
fresh; iev "$sid" "$S" "git commit -m y"; rc=$?
check "a branch whose trailers no verified session wrote: blocked" '[ $rc -eq 2 ]'
git -C "$I" update-ref refs/remotes/origin/main "$(git -C "$W" rev-parse HEAD)"   # merged; local main is stale
git -C "$W" checkout -q -b next origin/main; fresh; iev "$sid" "$W" "git commit -m start"; r1=$?
git -C "$W" checkout -q work; git -C "$W" reset -q --hard origin/main; fresh; iev "$sid" "$W" "git commit -m start"; r2=$?
check "new work from the merged default branch, on a new or a reused branch: blocked" '[ $r1 -eq 2 ] && [ $r2 -eq 2 ]'
fresh; iev "$sid" "$W" "GIT_DIR=/elsewhere git commit -m x"; r1=$?; fresh; iev "$sid" "$W" 'cd "$(mktemp -d)" && git commit -m x'; r2=$?
check "a checkout that cannot be told: blocked" '[ $r1 -eq 2 ] && [ $r2 -eq 2 ] && grep -q "cannot tell which checkout" "$T/i.err"'
fresh; iskill "$sid"
iev "$sid" "$I" "git commit -m 'Explain why we cd to the repo root' && git push"; r1=$?
iev "$sid" "$I" 'git commit -m "Document git -C dir commit in the guide"'; r2=$?
iev "$sid" "$I" 'git add -A && git commit -m "Stop setting GIT_DIR= in the smoke script" && git push'; r3=$?
iev "$sid" "$I" $'git commit -F - <<\'EOF\'\nWe cd into the project folder.\nEOF\ngit push'; r4=$?
check "words in a commit message are not read as commands" '[ $r1 -eq 0 ] && [ $r2 -eq 0 ] && [ $r3 -eq 0 ] && [ $r4 -eq 0 ]'
fresh; LIM_COMMIT_GATE=observe iev "$sid" "$W" "git commit -m x"
check "observe log from a worktree goes to the main .git" 'grep -q no-verify "$I/.git/lim-commit-gate.log"'
printf '#!/bin/sh\necho worktree-check; exit 1\n' > "$W/.claude/verify.sh"; git -C "$W" commit -qam failing
fresh; iev "$sid" "$W" "git push"; rc=$?
check "push from a worktree runs that worktree's checks" '[ $rc -eq 2 ] && grep -q worktree-check "$T/i.err"'
rm -f "${TMPDIR:-/tmp}"/claude-commit-gate-i*-$$*
J="$T/j"; mkrepo "$J"; git -C "$J" commit -q --allow-empty -m init
"$R/lim.sh" install "$J" > "$T/j.out" 2>&1
mkdir -p "$J/.github/workflows"; touch "$J/.github/workflows/ci.yml"
"$R/lim.sh" install "$J" > "$T/j2.out" 2>&1
check "install says to require CI only in a repo with CI" '! grep -q "required status check" "$T/j.out" && grep -q "required status check" "$T/j2.out"'

echo
echo "passed $pass, failed $fail"
rm -rf "$T"
[ "$fail" -eq 0 ]
