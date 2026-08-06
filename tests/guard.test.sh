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
