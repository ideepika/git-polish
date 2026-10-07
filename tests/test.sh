#!/bin/sh
# Run: sh tests/test.sh   (needs git and git-absorb)
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
polish="$here/bin/git-polish"
hook="$here/hooks/open-on-commit.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export GIT_POLISH_EDITOR=none GIT_CONFIG_GLOBAL=/dev/null
fail() { echo "FAIL: $*"; exit 1; }

cd "$t"
git init -q -b main; git config user.email t@example.com; git config user.name T
printf 'a1\na2\na3\n' > a.c; printf 'b1\nb2\n' > b.c
git add .; git commit -qm base
git checkout -qb feat
echo a4 >> a.c; git commit -qam "a: add a4"
echo b3 >> b.c; git commit -qam "b: add b3"

"$polish" main >/dev/null
[ "$(ls .git/polish/*.msg | wc -l | tr -d ' ')" = 2 ] || fail "message files"

# Edits go to the commits that own the lines; an edited message rewords.
sed 's/a4/a4-fixed/' a.c > x && mv x a.c
sed 's/b3/b3-fixed/' b.c > x && mv x b.c
sed 's/^b: add b3$/b: add b3, reworded/' .git/polish/02-*.msg > x && mv x .git/polish/02-*.msg
"$polish" apply >/dev/null 2>&1
[ "$(git log -1 --format=%s)" = "b: add b3, reworded" ] || fail "reword"
git show HEAD~1 | grep -q '^+a4-fixed' || fail "absorb into commit 1"
git show HEAD | grep -q '^+b3-fixed' || fail "absorb into commit 2"
[ "$(git rev-list --count main..)" = 2 ] || fail "commit count"

# A line no commit owns is left for `into`.
sed 's/^a1$/a1-new/' a.c > x && mv x a.c
"$polish" apply 2>&1 | grep -q 'Not absorbed' || fail "unowned lines reported"
"$polish" into 1 >/dev/null
git show HEAD~1 | grep -q '^+a1-new' || fail "into 1"
[ -z "$(git status --porcelain)" ] || fail "tree clean"

# Step mode: each commit is shown as uncommitted changes plus COMMIT_MSG;
# edits and a reworded COMMIT_MSG go into that commit.
git checkout -q -b steps main
echo s1 > s.txt; git add s.txt; git commit -qm "s: new file"
echo a4 >> a.c; git commit -qam "a: add a4"
touch junk.tmp                                  # untracked before: never committed
"$polish" step main | grep -q 'Commit 1/2: s: new file' || fail "step 1 shown"
git diff --name-only | grep -qx s.txt || fail "new file shown as a diff"
grep -qx 's: new file' COMMIT_MSG || fail "COMMIT_MSG"
echo s1-fixed > s.txt; echo extra > extra.txt
echo "s: new files, reworded" > COMMIT_MSG
"$polish" next | grep -q 'Commit 2/2: a: add a4' || fail "step 2 shown"
sed 's/a4/a4-fixed/' a.c > x && mv x a.c
"$polish" apply | grep -q 'Done' || fail "step done"
[ "$(git log -1 --format=%s HEAD~1)" = "s: new files, reworded" ] || fail "step reword"
git show HEAD~1 | grep -q '^+s1-fixed' || fail "step edit in commit 1"
git show --stat HEAD~1 | grep -q extra.txt || fail "new file in commit 1"
git show HEAD | grep -q '^+a4-fixed' || fail "step edit in commit 2"
git show --stat HEAD~1 HEAD | grep -q -e COMMIT_MSG -e junk.tmp && fail "COMMIT_MSG or junk committed"
[ "$(git log -1 --format=%an HEAD)" = T ] || fail "author kept"
[ ! -e COMMIT_MSG ] && [ ! -d .git/polish ] && [ ! -d .git/rebase-merge ] || fail "step cleanup"
rm junk.tmp; git checkout -q feat

# The hook opens a review only when HEAD moved.
"$polish" abort >/dev/null
ev() { printf '{"hook_event_name":"%s","session_id":"test-%s","cwd":"%s"}' "$1" $$ "$t"; }
ev UserPromptSubmit | "$hook"; ev Stop | "$hook"; sleep 1
[ ! -d .git/polish ] || fail "hook opened without new commits"
ev UserPromptSubmit | "$hook"; echo c > c.c; git add c.c; git commit -qm "c: new"
ev Stop | "$hook"; sleep 2
[ -d .git/polish ] || fail "hook did not open after a commit"

# Leak check.
scan="$here/bin/git-polish-scan"
export HOME="$t/home"; mkdir -p "$HOME"
git checkout -q main; git checkout -qb leaky
tok="ghp_$(printf 'a%.0s' $(seq 36))"            # built here so the repo holds no token
echo "token = \"$tok\"" > s.c; git add s.c; git commit -qm "s: add"
out=$("$scan" main..HEAD) && fail "token not flagged"
echo "$out" | grep -q 'LEAK.*GitHub token: ghp_\.\.\.' || fail "token report: $out"
echo "$out" | grep -q "$tok" && fail "token printed unmasked"

git reset -q --hard main
echo "host = 10.1.2.3" > ip.c; git add ip.c; git commit -qm "ip: add"
out=$("$scan" main..HEAD) || fail "a warning must not fail"
echo "$out" | grep -q 'warn.*private IP' || fail "IP not warned"

echo "secret plan for $(echo QWNtZUNvcnA= | base64 -d)" > n.c; git add n.c; git commit -qm "n: add"
"$scan" main..HEAD >/dev/null || fail "flagged a name with no forbid list"
git config polish.forbid 'acme ?corp'
"$scan" main..HEAD | grep -q 'LEAK.*forbidden: AcmeCorp' || fail "forbid list"
git config --unset polish.forbid

echo "x = \"$tok\" # polish:allow" > a2.c; git add a2.c; git commit -qm "a2: add"
"$scan" HEAD^! | grep -q LEAK && fail "polish:allow ignored"

git -c user.email=me@laptop.local commit -q --allow-empty -m "empty"
"$scan" HEAD^! | grep -q 'machine-name email' || fail "machine email"
git reset -q --hard HEAD^

# pre-push hook blocks a leak, allows a clean push.
git init -q --bare "$t/remote.git"; git remote add r "$t/remote.git"
"$polish" install-hook >/dev/null
git push -q r main 2>/dev/null || fail "clean push blocked"
echo "token = \"$tok\"" > s.c; git add s.c; git commit -qm "s: again"
git push -q r leaky >/dev/null 2>&1 && fail "leaky push allowed"

# Plugin hook asks before Claude pushes a leak.
pj=$(printf '{"tool_input":{"command":"git push r leaky"},"cwd":"%s"}' "$t")
printf '%s' "$pj" | "$here/hooks/check-before-push.sh" | grep -q '"ask"' || fail "push hook"

echo "all tests passed"
