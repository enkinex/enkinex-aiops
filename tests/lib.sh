#!/usr/bin/env bash
# Shared assertions for the enkinex governance regression suite.
#
# ADR-0004 makes the hooks, the policy guard and the permission posture the
# definition of the workflow — not documentation of it. That makes them code,
# and code that enforces things needs a regression suite: two real bugs in this
# layer (a grep pattern parsed as options, so the secret scan never ran; and a
# plugin spawning the wrong binary, so every guard call silently allowed) both
# passed review and were caught only by executing them.

set -uo pipefail

_PASS=0
_FAIL=0
_FAILED_NAMES=()

if [ -t 1 ]; then _G=$'\033[32m'; _R=$'\033[31m'; _D=$'\033[2m'; _Z=$'\033[0m'
else _G=""; _R=""; _D=""; _Z=""; fi

section() { printf '\n%s── %s ──%s\n' "$_D" "$1" "$_Z"; }

ok() {
    _PASS=$((_PASS + 1))
    printf '  %sok%s   %s\n' "$_G" "$_Z" "$1"
}

no() {
    _FAIL=$((_FAIL + 1))
    _FAILED_NAMES+=("$1")
    printf '  %sFAIL%s %s\n' "$_R" "$_Z" "$1"
    [ -n "${2:-}" ] && printf '       %s\n' "$2"
    return 0
}

# assert_ok <label> <command...> — command must exit 0
assert_ok() {
    local label="$1"; shift
    local out
    if out="$("$@" 2>&1)"; then ok "$label"; else no "$label" "exit $?: $(head -2 <<<"$out")"; fi
}

# assert_fails <label> <command...> — command must exit non-zero
assert_fails() {
    local label="$1"; shift
    local out
    if out="$("$@" 2>&1)"; then no "$label" "expected failure, got success"; else ok "$label"; fi
}

# assert_contains <label> <haystack> <needle>
assert_contains() {
    case "$2" in
        *"$3"*) ok "$1" ;;
        *) no "$1" "expected to contain: $3" ;;
    esac
}

summary() {
    printf '\n'
    if [ "$_FAIL" -eq 0 ]; then
        printf '%s%d passed%s\n' "$_G" "$_PASS" "$_Z"
        exit 0
    fi
    printf '%s%d failed%s, %d passed\n' "$_R" "$_FAIL" "$_Z" "$_PASS"
    for n in "${_FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
    exit 1
}

# new_repo <githooks-dir> — a throwaway git repo with an enkinex origin and the
# hooks installed. Echoes the path; the caller owns cleanup via trap.
new_repo() {
    local hooks="$1" dir
    dir="$(mktemp -d)"
    git init -q -b main "$dir"
    git -C "$dir" remote add origin git@github.com:enkinex/enkinex-test.git
    git -C "$dir" config user.email test@enkinex.invalid
    git -C "$dir" config user.name "enkinex tests"
    cp -r "$hooks" "$dir/.githooks"
    chmod +x "$dir"/.githooks/*
    git -C "$dir" config core.hooksPath .githooks
    printf '%s' "$dir"
}

# try_commit <repo> <message> — stages a unique file and commits. Exit status
# is the hook verdict.
try_commit() {
    local repo="$1" msg="$2" n
    n="$(ls "$repo" | grep -c '^probe' || true)"
    echo "$n" >"$repo/probe$n"
    git -C "$repo" add "probe$n" >/dev/null 2>&1
    printf '%s\n' "$msg" >"$repo/.commitmsg"
    if git -C "$repo" commit -q -F "$repo/.commitmsg" >/dev/null 2>&1; then
        return 0
    fi
    git -C "$repo" reset -q
    return 1
}
