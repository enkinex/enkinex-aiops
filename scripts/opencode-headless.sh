#!/usr/bin/env bash
# Run opencode non-interactively under the enkinex headless permission profile.
#
#   scripts/opencode-headless.sh <repo-dir> [opencode args...]
#   scripts/opencode-headless.sh ../enkinex-odcs run --agent build-kcl "…"
#
# WHY THIS EXISTS
# ---------------
# opencode's three permission actions do not all survive a run with no human
# attached. `allow` and `deny` are unambiguous; `ask` is not:
#
#   - without --auto, an `ask` call is auto-REJECTED and the session stalls;
#   - with    --auto, an `ask` call is auto-APPROVED, and only explicit `deny`
#     still holds.
#
# The interactive posture in opencode.jsonc puts every mutation behind `ask`,
# including `git push`, `gh pr create` and `gh pr merge`. Run headless with
# --auto and those become allows — so an unattended loop could squash-merge a
# PR — the one action ADR-0002 keeps permanently human-gated, on the grounds
# that an unattended run must never be able to land its own work.
#
# The fix is a profile with NO `ask` at all, so behaviour is identical with or
# without --auto:
#
#   "*": "deny"          the catch-all becomes an allowlist, not a prompt
#   git add/commit/checkout -> allow    local, recoverable, and separately
#                                       enforced by .githooks/
#   git push, git rebase, gh pr create, gh pr merge -> deny
#                                       irreversible or outward-facing; these
#                                       stay human actions in v0.2.0
#
# The profile is a thin OVERLAY: it names only the patterns whose action it
# changes, and every other rule in opencode.jsonc is inherited unchanged.
# It is delivered through OPENCODE_CONFIG_CONTENT because that is the only
# config source that loads AFTER the project's opencode.jsonc and therefore
# wins (verified against opencode 1.18.11). OPENCODE_CONFIG is loaded BEFORE
# the project config and would be silently overridden.
#
# Overriding an EXISTING pattern is safe under opencode's last-match-wins
# matching, because the pattern keeps its position in the rule order. Do not
# add new patterns to the overlay whose correctness depends on ordering.
#
# The overlay is plain JSON, not JSONC: opencode rejects comments in
# OPENCODE_CONFIG_CONTENT (verified). The rationale lives here instead.

set -euo pipefail

usage() {
    echo "usage: $(basename "$0") <repo-dir> [opencode args...]" >&2
    exit 2
}

[ "$#" -ge 1 ] || usage
repo="$1"
shift

[ -d "$repo" ] || { echo "not a directory: $repo" >&2; exit 1; }
repo="$(cd "$repo" && pwd)"

profile="$repo/opencode.headless.json"
[ -f "$profile" ] || {
    echo "no headless profile at $profile — run 'just sync-opencode' in enkinex-aiops" >&2
    exit 1
}

OPENCODE_CONFIG_CONTENT="$(cat "$profile")"
export OPENCODE_CONFIG_CONTENT

exec opencode --dir "$repo" "$@"
