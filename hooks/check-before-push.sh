#!/bin/sh
# PreToolUse:Bash -- before Claude runs `git push`, scan the commits it would
# push for leaks. Leaks turn the push into a permission prompt that shows
# them; warnings are passed to Claude to mention. Off: GIT_POLISH_PUSH_CHECK=0.

[ "${GIT_POLISH_PUSH_CHECK:-1}" = "0" ] && { cat >/dev/null; exit 0; }
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)' || exit 0
printf '%s' "$cmd" | grep -q -- '--dry-run' && exit 0

dir=$(printf '%s' "$cmd" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+)[[:space:]]+push.*/\1/p' | tr -d "'\"")
cd "${dir:-$cwd}" 2>/dev/null || cd "$cwd" 2>/dev/null || exit 0
git rev-parse -q --verify HEAD >/dev/null 2>&1 || exit 0

if git rev-parse -q --verify '@{upstream}' >/dev/null 2>&1; then
  set -- '@{upstream}..HEAD'
else
  set -- HEAD --not --remotes
fi
out=$("$(dirname "$0")/../bin/git-polish-scan" "$@" 2>&1); st=$?
[ -n "$out" ] || exit 0

if [ $st -ne 0 ]; then
  jq -n --arg r "$out" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("git-polish found possible leaks in the commits being pushed:\n" + $r)}}'
else
  jq -n --arg r "$out" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    additionalContext: ("git-polish leak check, warnings only (push allowed). Tell the user:\n" + $r)}}'
fi
exit 0
