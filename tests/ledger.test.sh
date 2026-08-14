#!/usr/bin/env bash
# Regression suite for scripts/ledger.sh.
#
# The ledger is exercised against a STUB `curl` on PATH, so the cases are
# deterministic, free and offline. That matters more than usual here: this
# script's whole job is to be believed about money, and the defect it is being
# tested for (AIOPS-15) was a warning that had been reporting the OPPOSITE of
# the truth on every run since 2026-08-04 — a check nobody can verify by
# reading, because reading it is what missed it the first time.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"; mkdir -p "$BIN"

# Stub curl: answers the two endpoints the ledger reads, from env. Anything
# else returns empty, which is what an unreachable endpoint looks like.
cat >"$BIN/curl" <<'STUB'
#!/usr/bin/env bash
url="${@: -1}"
case "$url" in
  */api/v1/key)     printf '%s' "${STUB_KEY_JSON:-}" ;;
  */api/v1/credits) printf '%s' "${STUB_CREDITS_JSON:-}" ;;
  *)                : ;;
esac
STUB
chmod +x "$BIN/curl"

# The opencode cross-check is best-effort; keep it silent and deterministic.
cat >"$BIN/opencode" <<'STUB'
#!/usr/bin/env bash
echo "Sessions 0"
echo "Total Cost \$0.00"
STUB
chmod +x "$BIN/opencode"

export PATH="$BIN:$PATH"
export OPENROUTER_API_KEY="stub-key-not-real"
# Never append to the committed ledger.
export LEDGER_LOG="$WORK/loop-log.md"

key_json() { printf '{"data":{"usage":10,"usage_daily":1,"usage_weekly":2,"usage_monthly":10,"limit":%s,"limit_remaining":%s}}' "$1" "$2"; }
credits_json() { printf '{"data":{"total_credits":%s,"total_usage":%s}}' "$1" "$2"; }

run_ledger() { (cd "$ROOT" && bash scripts/ledger.sh 2>&1); }

# ── the two states the warning must tell apart ─────────────────────────────
#
# Both are executed, not reasoned about. The criterion for AIOPS-15 is
# explicitly that the check is verified by running it in both states, because
# the bug was that one of them had never been run.

section "a control IS in force — the ledger must not warn"

STUB_KEY_JSON="$(key_json 50 40)" STUB_CREDITS_JSON="$(credits_json 25 13.87)"
export STUB_KEY_JSON STUB_CREDITS_JSON
OUT="$(run_ledger)"
case "$OUT" in
    *WARNING*) no "per-key limit set → silent" "warned while a per-key limit was in force" ;;
    *) ok "per-key limit set → silent" ;;
esac
assert_contains "per-key limit is reported as the ceiling" "$OUT" "per-key limit"

# The exact false positive AIOPS-15 exists for: no per-key limit, but a real
# balance standing between this key and unbounded spend.
STUB_KEY_JSON="$(key_json null null)" STUB_CREDITS_JSON="$(credits_json 25 13.87)"
export STUB_KEY_JSON STUB_CREDITS_JSON
OUT="$(run_ledger)"
case "$OUT" in
    *WARNING*) no "credit balance only → silent" \
        "this is the false positive: it warned while \$11.13 of credit was the live ceiling" ;;
    *) ok "credit balance only → silent" ;;
esac
assert_contains "the remaining balance is reported" "$OUT" "11.1300"

section "NO control is in force — the ledger must warn"

# Neither dimension: no per-key limit, and credits unreadable. The warning has
# to survive the fix, or AIOPS-15 would have replaced a false positive with a
# false negative — strictly worse, because nothing would ever say so.
STUB_KEY_JSON="$(key_json null null)" STUB_CREDITS_JSON=""
export STUB_KEY_JSON STUB_CREDITS_JSON
OUT="$(run_ledger)"
assert_contains "neither control → warns"        "$OUT" "WARNING"
assert_contains "the warning names both misses"  "$OUT" "credit balance could not be read"

# A malformed body is not the same as an absent one, and must not be read as a
# ceiling. Money is the one place to fail loud on unparseable input.
STUB_KEY_JSON="$(key_json null null)" STUB_CREDITS_JSON='{"data":{"total_credits":"lots"}}'
export STUB_KEY_JSON STUB_CREDITS_JSON
OUT="$(run_ledger)"
assert_contains "unparseable credits → still warns" "$OUT" "WARNING"

section "the ledger still records a row"

STUB_KEY_JSON="$(key_json 50 40)" STUB_CREDITS_JSON="$(credits_json 25 13.87)"
export STUB_KEY_JSON STUB_CREDITS_JSON
: >"$LEDGER_LOG"; rm -f "$LEDGER_LOG"
run_ledger >/dev/null
[ -f "$LEDGER_LOG" ] && ok "a row is appended" || no "a row is appended" "no ledger file written"
assert_contains "the row carries the OpenRouter total" "$(cat "$LEDGER_LOG")" "10.0000"

summary
