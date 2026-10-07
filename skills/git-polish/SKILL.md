---
name: git-polish
description: Open a branch's commits in the user's editor so they can edit code and commit messages, then fold the edits back into the commits they belong to (absorb + autosquash rebase, rewording edited messages). Use when the user asks to review, edit, polish, fix up or reword the commits on a branch, says "/git-polish", or says they finished editing ("apply", "done editing", "fold my changes in"), or asks to check commits for leaks, secrets or confidential names before pushing.
---

# Review and edit a branch's commits

The tool is `bin/git-polish` in this plugin (two directories above this
skill's base directory). Run it by that path, or as `git polish` if the user
has put it on PATH. It needs `git-absorb` (`brew install git-absorb` or
`cargo install git-absorb`); if missing, say so and offer to install it.

## Start

Run `git-polish [<base>]` in the repo. The base defaults to
`git config polish.base`, else the merge-base with the remote's default
branch. It refuses more than 40 commits — then ask the user for a base.

It opens the editor (`$GIT_POLISH_EDITOR`, `git config polish.editor`, or
VS Code) with every changed file plus `.git/polish/`: `00-INDEX.md`, and per
commit an editable `NN-<subject>.msg` and a read-only `NN-<subject>.diff`.

Tell the user in one line that it is open and to say "apply" when done.
Do not edit their files meanwhile.

## Step mode (Warp)

When the user reviews in Warp's code review panel (or any panel that only
shows uncommitted changes), or the editor is `warp`, run `git-polish step
[<base>]` instead. It stops on each commit with its diff uncommitted and its
message in a temporary `COMMIT_MSG` file at the top of the tree. Tell the user
which commit is shown and to say "next" (or "apply") when done with it; then
run `git-polish next`, which commits their edits and the message into that
commit and shows the next. Repeat until it prints "Done.", then report the
range-diff. A conflict from an earlier edit shows as markers in the next
commit; the user removes them, then `next`. Do not edit their files between
steps. `git rebase --abort` restores the original branch: ask first.

## Apply

Run `git-polish apply`. It:
1. stages tracked edits and runs `git absorb --and-rebase`, so each hunk goes
   into the commit that last touched those lines;
2. rewords each commit whose `.msg` file changed (commit-msg hooks run);
3. prints a `range-diff` summary and anything not absorbed.

Report which commits changed, which were reworded, and what is left.

- **"No commit owns these lines"**: ask which commit it belongs to (show the
  index), then `git-polish into <N>`. New files need `git add` first.
- **Rebase stopped** (conflict or a rejected message): show the error, fix it
  if it is mechanical, `git rebase --continue`, then re-run apply. Never
  `git rebase --abort` or reset without asking; the user's edits are in that
  state.
- `git-polish abort` removes `.git/polish/` only; edits stay.

## Leak check

`git-polish check [<rev>...]` scans commits (default: the review's, else the
unpushed ones) for secrets, names on the user's forbid list, machine-name
author emails, private IPs and home paths. It runs on start and after apply.
Report every LEAK line to the user verbatim and stop before any push until
they decide; for warnings, mention them. Never print an unmasked secret,
never add `polish:allow` or use `--no-verify` on your own, and never copy
the forbid list (`~/.config/git-polish/forbid`) into a repo, commit or
message. `git-polish install-hook` adds a pre-push hook to the repo.

## Rules

- Never push after applying. The user pushes, or asks you to.
- Run the project's build or tests before calling the rewritten branch good:
  a fixup can land in an earlier commit that then no longer builds alone.

## Automatic opening

The plugin's hook runs `git-polish` when a turn ends with new commits on a
branch other than main/master. `GIT_POLISH_ON_COMMIT=0` turns it off.
