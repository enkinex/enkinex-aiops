#!/usr/bin/env bash
# Regression suite for the gates themselves.
#
# The other suites assert what the governance artefacts do. This one asserts
# that the machinery reporting on them cannot report success by not running —
# the defect AIOPS-24 fixed in two places at once, after `tests/config.test.sh`
# had skipped 48 assertions on every pull request since it was written and
# `just verify-opencode` had claimed seven repos were in sync while examining
# none of them.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

section "a skip is counted apart from a pass"
# In a subshell, so this suite's own counters are untouched.
COUNTS="$(
    unset ENKINEX_TEST_REPORT
    # shellcheck source=lib.sh
    source "$HERE/lib.sh"
    ok "one" >/dev/null
    skip "two" 5 >/dev/null
    printf '%s %s %s' "$_PASS" "$_FAIL" "$_SKIP"
)"
[ "$COUNTS" = "1 0 5" ] && ok "skip does not inflate the pass count" ||
    no "skip does not inflate the pass count" "got '$COUNTS', wanted '1 0 5'"

REPORT="$(mktemp)"
trap 'rm -f "$REPORT"' EXIT
(
    unset _PASS _FAIL _SKIP
    # shellcheck source=lib.sh
    source "$HERE/lib.sh"
    skip "nothing ran" 3 >/dev/null
    ENKINEX_TEST_REPORT="$REPORT" summary >/dev/null 2>&1
) || true
assert_contains "summary reports the counts a caller can read" "$(cat "$REPORT")" "0 0 3"

section "a suite that cannot run says what it cost"
# The branch every pull request takes: CI installs `just` and nothing else.
NO_OC="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '\.opencode/bin' | paste -sd:)"
OUT="$(PATH="$NO_OC" bash "$ROOT/tests/config.test.sh" 2>&1)"
ST=$?
assert_contains "the skip names its cause" "$OUT" "opencode is not on PATH"
assert_contains "the skip states what it cost" "$OUT" "49 skipped"
[ "$ST" -eq 0 ] && ok "exit stays 0, so CI is not forced into an install decision" ||
    no "exit stays 0" "got $ST"

section "verify-opencode cannot claim repos it never looked at"
OUT="$(cd "$ROOT" && ENKINEX_ROOT=/nonexistent just verify-opencode 2>&1)"
ST=$?
[ "$ST" -ne 0 ] && ok "an uncloned REPOS entry fails the check" ||
    no "an uncloned REPOS entry fails the check" "exited 0"
assert_contains "each missing repo is named" "$OUT" "MISSING: enkinex-odcs"
assert_contains "the shortfall is counted" "$OUT" "8 of 8 sibling repo(s) were never examined"
case "$OUT" in
    *"in sync across"*) no "no success line is printed" "claimed sync after examining nothing" ;;
    *) ok "no success line is printed" ;;
esac

# And the other direction: the line is only earned when every entry was read.
# CI checks out this repository alone, so there is nothing to examine there and
# the assertion skips rather than failing for a reason that says nothing about
# the commit — which is the same distinction the workflow itself draws by
# calling `just test` instead of `just check`.
OUT="$(cd "$ROOT" && just verify-opencode 2>&1)"
case "$OUT" in
    *MISSING:*) skip "a full workspace earns the line: no sibling clone is present here" ;;
    *) assert_contains "a full workspace earns the line, with its count" "$OUT" \
           "in sync across enkinex-aiops and all 8 sibling repos" ;;
esac

section "an ENFORCEMENT_ONLY repo is compared like any other, from a second list"
# enkinex-manager takes the mechanical enforcement layer — hooks, guard, and the
# guard's two adapters — without joining REPOS (MGR-17, MGR-18, MGR-19). The
# point of the list is that the copies are compared: a copy nothing compares is
# what left that repo's hooks drifted from their sources by one comment line and
# four, unnoticed for a month.
FAKE="$(mktemp -d)"
git init -q "$FAKE/enkinex-manager"

# A clone carrying none of the policy layer. Absence and drift are one signal.
OUT="$(cd "$ROOT" && ENKINEX_ROOT="$FAKE" just verify-opencode 2>&1)"; ST=$?
[ "$ST" -ne 0 ] && ok "an absent policy layer fails the check" ||
    no "an absent policy layer fails the check" "exited 0"
assert_contains "the missing guard is named" "$OUT" "DRIFT: enkinex-manager/.agents/policy/guard.mjs"
assert_contains "so is the Claude adapter"   "$OUT" "DRIFT: enkinex-manager/.claude/settings.json"
assert_contains "and the missing hooks"      "$OUT" "DRIFT: enkinex-manager/.githooks/"

# Installed, but one byte out of date — drift as opposed to absence.
mkdir -p "$FAKE/enkinex-manager/.agents/policy" "$FAKE/enkinex-manager/.claude" "$FAKE/enkinex-manager/.codex"
cp "$ROOT/policy/guard.mjs" "$FAKE/enkinex-manager/.agents/policy/guard.mjs"
cp "$ROOT/policy/README.md" "$FAKE/enkinex-manager/.agents/policy/README.md"
cp "$ROOT/policy/adapters/claude-settings.json" "$FAKE/enkinex-manager/.claude/settings.json"
cp "$ROOT/policy/adapters/codex-hooks.json"     "$FAKE/enkinex-manager/.codex/hooks.json"
cp -r "$ROOT/githooks" "$FAKE/enkinex-manager/.githooks"
printf '\n// stale\n' >>"$FAKE/enkinex-manager/.agents/policy/guard.mjs"

OUT="$(cd "$ROOT" && ENKINEX_ROOT="$FAKE" just verify-opencode 2>&1)"; ST=$?
[ "$ST" -ne 0 ] && ok "a drifted guard fails the check" ||
    no "a drifted guard fails the check" "exited 0"
assert_contains "the drifted file is named" "$OUT" "DRIFT: enkinex-manager/.agents/policy/guard.mjs"
case "$OUT" in
    *"DRIFT: enkinex-manager/.claude/settings.json"*)
        no "only the drifted file is named" "an up-to-date adapter was reported too" ;;
    *)  ok "only the drifted file is named" ;;
esac
case "$OUT" in
    *"DRIFT: enkinex-manager/.githooks/"*)
        no "up-to-date hooks are not reported" "hooks matching the source were flagged" ;;
    *)  ok "up-to-date hooks are not reported" ;;
esac

# A hook out of date by one comment line — the exact drift MGR-19 measured, and
# the one nothing reported for a month.
printf '\n# stale\n' >>"$FAKE/enkinex-manager/.githooks/commit-msg"
OUT="$(cd "$ROOT" && ENKINEX_ROOT="$FAKE" just verify-opencode 2>&1)"; ST=$?
[ "$ST" -ne 0 ] && ok "a drifted hook fails the check" ||
    no "a drifted hook fails the check" "exited 0"
assert_contains "the hook directory is named" "$OUT" "DRIFT: enkinex-manager/.githooks/"

# The install half. Without a case here, "sync carries the hooks" is a claim
# with nothing behind it — and a claim with nothing behind it is what AIOPS-24
# was about.
(cd "$ROOT" && ENKINEX_ROOT="$FAKE" just sync-opencode >/dev/null 2>&1)
if diff -rq "$ROOT/githooks" "$FAKE/enkinex-manager/.githooks" >/dev/null 2>&1; then
    ok "sync restores a drifted hook to its source"
else
    no "sync restores a drifted hook to its source" "the copy still differs"
fi
[ -x "$FAKE/enkinex-manager/.githooks/pre-commit" ] &&
    ok "and leaves the hooks executable" || no "and leaves the hooks executable"
[ "$(git -C "$FAKE/enkinex-manager" config --get core.hooksPath)" = ".githooks" ] &&
    ok "and points the clone at them" || no "and points the clone at them"
# Enforcement travels; configuration and artefacts do not.
for unwanted in opencode.jsonc opencode.headless.json AGENTS.shared.md .opencode .agents/mcp .mcp.json; do
    [ -e "$FAKE/enkinex-manager/$unwanted" ] &&
        no "sync carries nothing but enforcement" "$unwanted arrived" && break
done
[ -e "$FAKE/enkinex-manager/opencode.jsonc" ] || ok "sync carries nothing but enforcement"
rm -rf "$FAKE"

summary
