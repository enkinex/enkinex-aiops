#!/usr/bin/env bash
# Regression suite for githooks/. Frozen cases: each one is a rule the hooks
# are supposed to enforce, plus the near-misses that must NOT be blocked.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

REPO="$(new_repo "$ROOT/githooks")"
trap 'rm -rf "$REPO"' EXIT

REFS='Refs: plan/x.md#s1'

accepts() { if try_commit "$REPO" "$2"; then ok "$1"; else no "$1" "hook rejected a valid message"; fi; }
rejects() { if try_commit "$REPO" "$2"; then no "$1" "hook accepted an invalid message"; else ok "$1"; fi; }

section "commit-msg — grammar"
accepts "scopeless subject"            "feat: add a thing"$'\n\n'"$REFS"
accepts "module scope"                 "feat(catalog): add a thing"$'\n\n'"$REFS"
accepts "No-Plan-Ref opt-out"          "chore: tooling"$'\n\n'"No-Plan-Ref: repo hygiene"
accepts "merge subject exempt"         "Merge pull request #3 from enkinex/x"
rejects "no type prefix"               "add a thing"$'\n\n'"$REFS"
rejects "unknown type"                 "wibble: add a thing"$'\n\n'"$REFS"
rejects "trailing period"              "feat: add a thing."$'\n\n'"$REFS"
rejects "subject over 72 chars"        "feat: $(printf 'x%.0s' {1..70})"$'\n\n'"$REFS"
rejects "missing Refs footer"          "feat: add a thing"
rejects "Closes: footer"               "fix: thing"$'\n\n'"Closes: #12"$'\n'"$REFS"

section "commit-msg — no repo-name scope"
# The rule compares the scope against the repository's directory name, so the
# fixture has to be a directory literally named enkinex-odcs — not a mktemp
# name that merely starts with it.
NAMED_PARENT="$(mktemp -d)"
NAMED="$NAMED_PARENT/enkinex-odcs"
cp -r "$REPO" "$NAMED"
rejects_named() {
    if try_commit "$NAMED" "$2"; then no "$1" "accepted a repo-name scope"; else ok "$1"; fi
}
accepts_named() {
    if try_commit "$NAMED" "$2"; then ok "$1"; else no "$1" "rejected a valid scope"; fi
}
rejects_named "scope repeats repo suffix"   "feat(odcs): thing"$'\n\n'"$REFS"
rejects_named "scope repeats full repo name" "feat(enkinex-odcs): thing"$'\n\n'"$REFS"
accepts_named "module scope still fine"      "feat(quality): thing"$'\n\n'"$REFS"
rm -rf "$NAMED_PARENT"

section "pre-commit — secret-shaped paths"
path_case() {
    local label="$1" file="$2" expect="$3"
    printf 'x\n' >"$REPO/$file"
    git -C "$REPO" add -f "$file" >/dev/null 2>&1
    printf 'feat: stage %s\n\n%s\n' "$file" "$REFS" >"$REPO/.commitmsg"
    if git -C "$REPO" commit -q -F "$REPO/.commitmsg" >/dev/null 2>&1; then
        [ "$expect" = allow ] && ok "$label" || no "$label" "committed a secret-shaped path"
    else
        git -C "$REPO" reset -q
        [ "$expect" = deny ] && ok "$label" || no "$label" "blocked a legitimate path"
    fi
    rm -f "$REPO/$file"
}
path_case "server.key blocked"      "server.key"      deny
path_case ".env blocked"            ".env"            deny
path_case "id_rsa blocked"          "id_rsa"          deny
path_case ".env.example allowed"    ".env.example"    allow
path_case "ordinary markdown"       "notes.md"        allow

section "pre-commit — credential-shaped content"
content_case() {
    local label="$1" body="$2" expect="$3"
    printf '%s\n' "$body" >"$REPO/scan_probe.txt"
    git -C "$REPO" add scan_probe.txt >/dev/null 2>&1
    printf 'feat: scan probe\n\n%s\n' "$REFS" >"$REPO/.commitmsg"
    if git -C "$REPO" commit -q -F "$REPO/.commitmsg" >/dev/null 2>&1; then
        [ "$expect" = allow ] && ok "$label" || no "$label" "committed a credential"
        git -C "$REPO" rm -q scan_probe.txt >/dev/null 2>&1
        git -C "$REPO" commit -q -m "chore: drop probe" -m "$REFS" >/dev/null 2>&1
    else
        git -C "$REPO" reset -q
        [ "$expect" = deny ] && ok "$label" || no "$label" "blocked ordinary text"
    fi
    rm -f "$REPO/scan_probe.txt"
}
# Every fixture below is ASSEMBLED at runtime rather than written literally.
# A test file full of real credential shapes cannot be committed through the
# scanner it is testing — this suite blocked its own first commit on the PEM
# banner. Splitting the string keeps the file clean while the value handed to
# the hook is byte-identical to the real thing.
PEM_HEAD="-----BEGIN"
content_case "AWS access key id"  "aws AKIA$(printf 'ABCDEFGH12345678')"                   deny
content_case "GitHub PAT"         "ghp_$(printf 'a%.0s' {1..36})"                          deny
content_case "PEM banner"         "$PEM_HEAD RSA PRIVATE KEY-----"                         deny
content_case "OpenSSH PEM banner" "$PEM_HEAD OPENSSH PRIVATE KEY-----"                     deny
content_case "sk- style key"      "sk-$(printf 'b%.0s' {1..35})"                           deny
content_case "Slack token"        "xox""b-1234567890-abcdefghij"                           deny
content_case "prose about secrets" "notes on secrets, credentials and API keys"            allow

section "pre-commit — the hooks and guard pass their own scan"
# Regression: a literal PEM banner in the pattern list used to be matched by the
# general PEM pattern, so pre-commit could not commit its own source.
for f in "$ROOT"/githooks/* "$ROOT/policy/guard.mjs"; do
    base="$(basename "$f")"
    cp "$f" "$REPO/selfscan_$base"
    git -C "$REPO" add "selfscan_$base" >/dev/null 2>&1
    printf 'feat: self scan %s\n\n%s\n' "$base" "$REFS" >"$REPO/.commitmsg"
    if git -C "$REPO" commit -q -F "$REPO/.commitmsg" >/dev/null 2>&1; then
        ok "$base passes its own secret scan"
    else
        no "$base passes its own secret scan" "the scanner matched its own source"
        git -C "$REPO" reset -q
    fi
    rm -f "$REPO/selfscan_$base"
done

section "pre-commit — remote guard is advisory, not a wall"
# enkinex-odcs/odps/okf are public and take forks. A fork's origin is
# github.com/<contributor>/…, so blocking here would refuse every commit an
# outside contributor makes. pre-push is where the guard bites.
git -C "$REPO" remote set-url origin git@github.com:someoneelse/x.git
if try_commit "$REPO" "feat: thing from a fork"$'\n\n'"$REFS"; then
    ok "a fork can still commit"
else
    no "a fork can still commit" "pre-commit blocked a non-enkinex origin"
fi
git -C "$REPO" remote set-url origin git@github.com:enkinex/enkinex-test.git

section "pre-push"
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
ZERO=0000000000000000000000000000000000000000
push_case() {
    local label="$1" branch="$2" url="$3" expect="$4" remote_sha="${5:-$ZERO}" local_sha="${6:-$HEAD_SHA}"
    if printf 'refs/heads/x %s refs/heads/%s %s\n' "$local_sha" "$branch" "$remote_sha" |
        (cd "$REPO" && ./.githooks/pre-push origin "$url") >/dev/null 2>&1; then
        [ "$expect" = allow ] && ok "$label" || no "$label" "allowed a push it should block"
    else
        [ "$expect" = deny ] && ok "$label" || no "$label" "blocked a legitimate push"
    fi
}
E=git@github.com:enkinex/enkinex-odcs.git
push_case "conventional slug"        "feat/output-port-retry"  "$E" allow
push_case "proj slug"                "proj/aiops-foundation"   "$E" allow
push_case "https enkinex remote"     "feat/x-y"                "https://github.com/enkinex/x.git" allow
push_case "branch deletion"          "feat/gone"               "$E" allow "$HEAD_SHA" "$ZERO"
push_case "direct push to main"      "main"                    "$E" deny
push_case "slug without a type"      "my-branch"               "$E" deny
push_case "uppercase in slug"        "feat/Odcs-Thing"         "$E" deny
push_case "unrelated remote"         "feat/x-y"  "git@github.com:someoneelse/x.git" deny
# A fork of THIS repo is a legitimate push target for a public repo; only an
# unrelated repository is not. The fixture repo is a mktemp dir, so name the
# fork after it.
FORKURL="git@github.com:someoneelse/$(basename "$REPO").git"
push_case "a fork of this repo"      "feat/x-y"  "$FORKURL" allow

# History rewrite: a remote head that is not an ancestor of what we push.
git -C "$REPO" checkout -q -b feat/fork "$HEAD_SHA~1" 2>/dev/null || git -C "$REPO" checkout -q -b feat/fork
echo z >"$REPO/z"; git -C "$REPO" add z >/dev/null
git -C "$REPO" commit -q -m "feat: fork" -m "$REFS" >/dev/null 2>&1
FORK="$(git -C "$REPO" rev-parse HEAD)"
push_case "non-fast-forward rewrite" "feat/fork" "$E" deny "$HEAD_SHA" "$FORK"

summary
