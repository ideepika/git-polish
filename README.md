# git-polish

Review a branch's commits in your editor, edit the code and the commit
messages in place, and fold the edits back into the commits they belong to.
No `git rebase -i`, no hand-written fixups.

```
git polish            # open the branch's commits in VS Code
# ...edit code anywhere, edit .git/polish/NN-*.msg to reword...
git polish apply      # each edit goes into the commit that last touched those lines
git polish into 3     # put lines no commit owns into commit 3
git polish abort      # drop the review files, keep your edits
git polish check      # scan the commits for leaks
git polish install-hook   # block pushes that leak (pre-push hook)
```

`git polish` opens every file the branch changed, plus `.git/polish/` with an
index, an editable message file and a read-only diff per commit. `apply`
stages your edits, runs [git-absorb](https://github.com/tummychow/git-absorb)
and an autosquash rebase, rewords any commit whose message file changed (your
commit-msg hook still runs), and prints a `range-diff`. It never pushes.

## Leak check

Every review, every `apply`, and every push (with the pre-push hook or the
Claude Code plugin) scans the commits' added lines, messages and author
identities:

| | |
|---|---|
| **LEAK** (blocks a push) | private keys; AWS, GitHub, Slack, Google and `sk-` API keys; JWTs; cephx keys; `password = "..."`-style credentials; URLs with a password; names on your forbid list; author emails that expose a machine name (`you@laptop.local`); authors other than `polish.email` when set |
| **warn** | private IP addresses, `/Users/<name>` and `/home/<name>` paths |

If [gitleaks](https://github.com/gitleaks/gitleaks) is installed its findings
are added. Secrets are shown masked. Mark an intended line with
`polish:allow`; bypass the hook once with `git push --no-verify`.

**Forbid list.** Put customer names, internal hostnames, project code names
and the like in `~/.config/git-polish/forbid`, one case-insensitive Perl
regex per line (or `git config --add polish.forbid <regex>`). Keep this file
out of every repo; the list itself is sensitive.

The Claude Code plugin checks before Claude runs `git push`: leaks turn the
push into a permission prompt that lists them.

## Install

Needs `git`, `perl` and `git-absorb` (`brew install git-absorb` or
`cargo install git-absorb`).

As a git command:

```
git clone https://github.com/ideepika/git-polish
ln -s "$PWD/git-polish/bin/git-polish" ~/.local/bin/git-polish   # any dir on PATH
```

As a Claude Code plugin (adds a skill, and opens the review automatically
when Claude finishes a task with new commits):

```
/plugin marketplace add ideepika/git-polish
/plugin install git-polish@git-polish
```

Then ask Claude to "polish the commits on this branch", edit, and say
"apply".

## Configuration

| Setting | Default |
|---|---|
| base | `git config polish.base`, else merge-base with `origin/HEAD`, `origin/main` or `origin/master`; or pass `git polish <base>` |
| editor | `$GIT_POLISH_EDITOR`, else `git config polish.editor`, else VS Code `code`; `none` just prints the paths |
| push check (plugin) | on; `GIT_POLISH_PUSH_CHECK=0` turns it off |
| author email | `git config polish.email <addr>` flags commits by any other address |
| auto-open (plugin) | on; `GIT_POLISH_ON_COMMIT=0` turns it off. Never on main/master or during a rebase |

## Limits

- Messages are matched to commits by position; don't reorder commits mid-review.
- Up to 40 commits per review; pass a closer base for more.
- An edit that moves lines can conflict during the rebase. `apply` stops and
  leaves you in the rebase to resolve it.

## Tests

```
sh tests/test.sh
```

## License

MIT
