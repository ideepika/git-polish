#!/bin/sh
# UserPromptSubmit + Stop -- open `git polish` in VS Code when a turn ends
# with new commits on the branch.
#
# On prompt submit, remember HEAD of the session's repo. On stop, if HEAD
# moved (and no rebase is in progress), run `git polish` so the branch's
# commits open in VS Code for editing. Disable with GIT_POLISH_ON_COMMIT=0.

[ "${GIT_POLISH_ON_COMMIT:-1}" = "0" ] && { cat >/dev/null; exit 0; }
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty')
sid=$(printf '%s' "$input" | jq -r '.session_id // "x"')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$cwd" ] || exit 0
cd "$cwd" 2>/dev/null || exit 0
head=$(git rev-parse -q --verify HEAD 2>/dev/null) || exit 0
mark="${TMPDIR:-/tmp}/git-polish-head.$sid"

case "$event" in
  UserPromptSubmit) echo "$head" > "$mark" ;;
  Stop)
    [ -f "$mark" ] || exit 0
    [ "$(cat "$mark")" = "$head" ] && exit 0
    echo "$head" > "$mark"
    gitdir=$(git rev-parse --absolute-git-dir)
    [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ] && exit 0
    case "$(git branch --show-current)" in main|master|"") exit 0 ;; esac
    GIT_POLISH_AUTO=1 nohup "$(dirname "$0")/../bin/git-polish" >/dev/null 2>&1 &
    ;;
esac
exit 0
