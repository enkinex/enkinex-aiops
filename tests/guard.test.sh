#!/usr/bin/env bash
# Regression suite for policy/guard.mjs — the layer that covers what git hooks
# structurally cannot see. Frozen cases plus the near-misses that must stay
# allowed, because an over-eager guard gets disabled and then enforces nothing.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

GUARD="$ROOT/policy/guard.mjs"

# verdict <payload-json> — echoes "deny" or "allow"
verdict() {
    local out
    out="$(printf '%s' "$1" | node "$GUARD" 2>/dev/null)"
    if [ -n "$out" ] && grep -q '"permissionDecision":"deny"' <<<"$out"; then
        echo deny
    else
        echo allow
    fi
}

bash_case() {
    local label="$1" cmd="$2" expect="$3" cwd="${4:-$ROOT}"
    local payload got
    payload="$(node -e '
      const [cmd, cwd] = process.argv.slice(1);
      process.stdout.write(JSON.stringify({
        hook_event_name: "PreToolUse", tool_name: "Bash",
        tool_input: { command: cmd }, cwd,
      }));' "$cmd" "$cwd")"
    got="$(verdict "$payload")"
    [ "$got" = "$expect" ] && ok "$label" || no "$label" "expected $expect, got $got — $cmd"
}

file_case() {
    local label="$1" tool="$2" path="$3" expect="$4"
    local payload got
    payload="$(node -e '
      const [tool, p] = process.argv.slice(1);
      process.stdout.write(JSON.stringify({
        hook_event_name: "PreToolUse", tool_name: tool,
        tool_input: { file_path: p }, cwd: process.cwd(),
      }));' "$tool" "$path")"
    got="$(verdict "$payload")"
    [ "$got" = "$expect" ] && ok "$label" || no "$label" "expected $expect, got $got — $path"
}

section "guard — hook bypass (the rule that makes every other rule stick)"
bash_case "git commit --no-verify"       'git commit --no-verify -m x'          deny
bash_case "git commit -nm bundled flag"  'git commit -nm "x"'                   deny
bash_case "git push --no-verify"         'git push --no-verify'                 deny
bash_case "core.hooksPath tamper"        'git config core.hooksPath /dev/null'  deny
bash_case "rm -rf .githooks"             'rm -rf .githooks'                     deny
bash_case "chmod -x .githooks"           'chmod -x .githooks/pre-commit'        deny

# Git takes its global options between `git` and the verb, so every rule that
# matched a `git commit` prefix was one `-C .` away from allowed. Measured on
# dc6ea42, five of the six lines below returned allow. The two config spellings
# set core.hooksPath for a single command and leave nothing behind afterwards,
# so nothing later would notice the hooks had been redirected.
section "guard — global options do not move the verb out of reach"
bash_case "-C before commit"             'git -C . commit --no-verify -m x'     deny
bash_case "-C before add"                'git -C . add -A'                      deny
bash_case "--no-pager before add"        'git --no-pager add -A'                deny
bash_case "-P before push"               'git -P push --force'                  deny
bash_case "-C before reset"              'git -C . reset --hard'                deny
bash_case "--git-dir= before commit"     'git --git-dir=/tmp/x commit -n -m y'  deny
bash_case "--work-tree value form"       'git --work-tree /tmp commit -n -m y'  deny
bash_case "-c core.hooksPath"            'git -c core.hooksPath=/tmp/e commit -m x' deny
bash_case "GIT_CONFIG_KEY_n hooksPath" \
    'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/tmp/e git commit -m x' \
                                                                                deny
# The near-misses. Stripping the globals must not make ordinary work look
# denied, and an unrelated `-c` is not a hooks redirect.
bash_case "-C with a read-only verb"     'git -C /tmp status -sb'               allow
bash_case "--no-pager with log"          'git --no-pager log'                   allow
bash_case "-C with explicit paths"       'git -C . add AGENTS.md'               allow
bash_case "-c that is not hooksPath"     'git -c user.name=x commit -m "feat: thing"' allow
bash_case "hooksPath named in prose"     'git commit -m "docs: explain core.hooksPath"' allow
# A flag that does not take a separate value must not swallow the verb: listing
# --exec-path as value-taking would turn this line back into an allow.
bash_case "--exec-path does not eat the verb" 'git --exec-path commit --no-verify -m x' deny
# A quoted value with a space in it would split on whitespace and leave the
# walk pointing at the tail of the value instead of the verb — the same bypass
# one layer down from the one masking already closed for the segment split.
bash_case "quoted -c value with a space" \
    'git -c "user.name=A B" commit --no-verify -m x'                           deny
bash_case "quoted -C path with a space" \
    "git -C 'my repo' add -A"                                                  deny

section "guard — implicit staging"
bash_case "git add -A"                   'git add -A'                           deny
bash_case "git add ."                    'git add .'                            deny
bash_case "git add -u"                   'git add -u'                           deny
bash_case "git add with no args"         'git add'                              deny
bash_case "explicit paths allowed"       'git add AGENTS.md Justfile'           allow

section "guard — human-gated and destructive"
bash_case "gh pr merge"                  'gh pr merge 12 --squash'              deny
bash_case "git push --force"             'git push --force origin main'         deny
bash_case "git push -f"                  'git push -f'                          deny
bash_case "git reset --hard"             'git reset --hard HEAD~1'              deny
bash_case "git clean -fdx"               'git clean -fdx'                       deny

section "guard — chained commands are inspected per segment"
bash_case "chained deny after allow"     'just check && git add -A'             deny
bash_case "chained allow stays allowed"  'just fmt && git add AGENTS.md'        allow
# A single `|` is a separator too. The split covered `&&`, `||` and `;` but not
# a lone pipe, so every rule that scans segments could be evaded by piping.
bash_case "piped hook bypass"            'echo x | git commit --no-verify -m y' deny
bash_case "piped implicit staging"       'ls | git add -A'                      deny
bash_case "piped pr merge"               'echo y | gh pr merge 12 --squash'     deny
bash_case "ordinary pipe stays allowed"  'git log --oneline | head -5'          allow

# Splitting on a bare pipe to catch the cases above traded one bypass for
# another: a pipe inside a quoted argument split the command, so the segment
# carrying the flag no longer began with `git commit` and the rule never fired.
# Measured against the pre-change guard, `git commit -m "fix A|B" --no-verify`
# went from deny to allow. Quoted spans are masked before the split now, and
# these four cases pin both halves so neither can be traded for the other again.
bash_case "quoted pipe does not hide a bypass" \
    'git commit -m "fix the A|B table" --no-verify'                            deny
bash_case "quoted pipe does not hide staging" \
    'git add -A -- "a|b.txt"'                                                  deny
bash_case "a pipe in a commit message is allowed" \
    'git commit -m "docs: describe the a|b split" -a'                          allow
bash_case "a regex alternation in a search is allowed" \
    'grep -rE "foo|bar" .'                                                     allow

section "guard — must not over-block"
bash_case "normal commit"                'git commit -m "feat: thing"'          allow
bash_case "git status"                   'git status -sb'                       allow
bash_case "gh pr view"                   'gh pr view 12 --json state'           allow
bash_case "just check"                   'just check'                           allow
bash_case "grep mentions no-verify"      'grep -rn no-verify docs/'             allow
# Matching on the command's leading verb, not a substring: a command that only
# mentions a denied form stages nothing and must run.
bash_case "prose mentions git add -A"    'echo "never use git add -A"'          allow

section "guard — credential paths"
file_case "read .env"            Read  ".env"              deny
file_case "read a pem"           Read  "config/prod.pem"   deny
file_case "read id_rsa"          Read  "id_rsa"            deny
file_case "write .env.example"   Write ".env.example"      allow
file_case "edit AGENTS.md"       Edit  "AGENTS.md"         allow
file_case "write notes.key.md"   Write "notes.key.md"      allow

section "guard — remote guard"
FOREIGN="$(mktemp -d)"
trap 'rm -rf "$FOREIGN"' EXIT
git init -q "$FOREIGN"
git -C "$FOREIGN" remote add origin git@github.com:someoneelse/x.git
bash_case "gh pr create, foreign origin" 'gh pr create --fill' deny  "$FOREIGN"
bash_case "gh pr create, enkinex origin" 'gh pr create --fill' allow "$ROOT"
# -C names the repo the push actually writes to, so that is the origin to ask.
# Checking the session's cwd instead would give a wrong answer in both
# directions rather than no answer.
bash_case "push -C into a foreign repo"  "git -C $FOREIGN push" deny  "$ROOT"
bash_case "push -C into an enkinex repo" "git -C $ROOT push"    allow "$FOREIGN"
bash_case "push -C at a path that is gone" 'git -C /nonexistent/zz push' allow "$ROOT"
# A quoted path has to lose its quotes before it can be resolved, or the lookup
# silently misses and the rule allows.
SPACED="$FOREIGN/a dir"
git init -q "$SPACED"
git -C "$SPACED" remote add origin git@github.com:someoneelse/y.git
bash_case "push -C into a quoted foreign path" "git -C '$SPACED' push" deny "$ROOT"

section "guard — robustness (a broken payload must never block work)"
[ "$(printf '' | node "$GUARD" | wc -c)" -eq 0 ] &&
    ok "empty stdin allows" || no "empty stdin allows"
[ "$(printf '{not json' | node "$GUARD" | wc -c)" -eq 0 ] &&
    ok "malformed json allows" || no "malformed json allows"
[ "$(printf '{"tool_name":"WebFetch","tool_input":{"url":"https://x"}}' | node "$GUARD" | wc -c)" -eq 0 ] &&
    ok "unknown tool allows" || no "unknown tool allows"

section "guard — response carries both harness shapes"
OUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"git add -A"}}' | node "$GUARD")"
assert_contains "Claude Code shape present" "$OUT" '"permissionDecision":"deny"'
assert_contains "Codex shape present"       "$OUT" '"decision":"block"'

summary
