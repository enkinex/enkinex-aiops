#!/usr/bin/env bash
# Append a cost snapshot to loop/loop-log.md (loop.md Phase 6).
#
# SOURCES, and why there are two
# ------------------------------
# OpenRouter's /api/v1/key is the ledger's machine-readable source: it is JSON,
# and it is the billing system of record. `opencode stats` has no --json and
# renders a box-drawn table, so it is parsed best-effort and used only as an
# independent cross-check. When the two disagree by more than rounding, the
# discrepancy is the interesting signal — spend that opencode did not account
# for (another tool on the same key, or a harness other than opencode).
#
# This replaces the plan's original "opencode stats + session export" design:
# a ledger whose only source is the thing being measured cannot detect its own
# blind spots.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the regression suite never appends to the committed ledger,
# the same reason scripts/loop.sh takes LOOP_RUNLOG.
LOG="${LEDGER_LOG:-$ROOT/loop/loop-log.md}"

: "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY is not set — the ledger reads OpenRouter usage}"

key_json="$(curl -s -m 20 -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    https://openrouter.ai/api/v1/key || true)"

[ -n "$key_json" ] || { echo "ledger: no response from OpenRouter" >&2; exit 1; }

read -r total daily weekly monthly limit remaining < <(
    printf '%s' "$key_json" | node -e '
      let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
        const d = JSON.parse(s).data || {};
        const n = v => (v === null || v === undefined ? "-" : (+v).toFixed(4));
        console.log([n(d.usage), n(d.usage_daily), n(d.usage_weekly),
                     n(d.usage_monthly), d.limit === null ? "none" : n(d.limit),
                     d.limit_remaining === null ? "-" : n(d.limit_remaining)].join(" "));
      });'
)

# ── the second spend control: the credit balance ───────────────────────────
#
# AIOPS-15. The warning below used to fire whenever /api/v1/key reported no
# per-key limit, and it had been firing on every run since 2026-08-04 while a
# spend limit WAS in force — set at the workspace level, where that endpoint
# cannot see it. An alert that is wrong every time is read past, and then the
# true one is missed with it.
#
# The workspace guardrail itself stays invisible and that is settled, not
# pending: /api/v1/keys, /api/v1/guardrails and /api/v1/keys/guardrails all
# answer 401 "Invalid management key" to a normal API key. Reading it would
# mean provisioning a management key and holding a second, more powerful
# secret on every machine that runs the ledger — a worse trade than the
# warning it would fix.
#
# /api/v1/credits needs no such key, and on a prepaid account the balance is
# itself a hard ceiling: spend stops when it reaches zero. So the ledger no
# longer asks "is there a per-key limit", which was never the question, but
# "is anything at all stopping this key" — and a finite balance is.
credits_json="$(curl -s -m 20 -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    https://openrouter.ai/api/v1/credits || true)"
read -r credits_total credits_used < <(
    printf '%s' "$credits_json" | node -e '
      let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
        let d = {};
        try { d = JSON.parse(s).data || {}; } catch { /* unreadable is "-" */ }
        const n = v => (v === null || v === undefined || isNaN(+v) ? "-" : (+v).toFixed(4));
        console.log([n(d.total_credits), n(d.total_usage)].join(" "));
      });' 2>/dev/null || echo "- -"
)
credits_left="-"
if [ "$credits_total" != "-" ] && [ "$credits_used" != "-" ]; then
    credits_left="$(node -e 'const [a,b]=process.argv.slice(1);console.log(((+a)-(+b)).toFixed(4))' \
        "$credits_total" "$credits_used")"
fi

# Best-effort cross-check. A parse failure must not fail the ledger.
#
# Deliberately all-time, not windowed: `opencode stats --days N` returns an
# identical Total Cost for N = 1, 2 and 30, so the flag does not window cost on
# this build. Comparing an unwindowed opencode figure against OpenRouter's
# daily usage would manufacture a discrepancy that is not real, so both sides
# of the comparison are cumulative.
oc_stats="$(opencode stats 2>/dev/null || true)"
oc_cost="$(sed -n 's/.*Total Cost *\$\([0-9.]*\).*/\1/p' <<<"$oc_stats" | head -1)"
oc_sessions="$(sed -n 's/.*Sessions *\([0-9]*\).*/\1/p' <<<"$oc_stats" | head -1)"
oc_cost="${oc_cost:--}"
oc_sessions="${oc_sessions:--}"

# Δ = opencode's accounting minus OpenRouter's. A persistent negative gap is
# spend on this key that opencode did not produce.
if [ "$oc_cost" != "-" ] && [ "$total" != "-" ]; then
    delta="$(node -e 'const [a,b]=process.argv.slice(1);console.log(((+a)-(+b)).toFixed(4))' "$oc_cost" "$total")"
else
    delta="-"
fi

mkdir -p "$(dirname "$LOG")"
if [ ! -f "$LOG" ]; then
    cat >"$LOG" <<'HEADER'
# Loop cost ledger

Appended by `just ledger` (enkinex-aiops `scripts/ledger.sh`). OpenRouter
`/api/v1/key` is the source of truth; the opencode columns are an independent
cross-check. Both cost columns are cumulative: `opencode stats --days N`
does not window cost on this build, so comparing it to OpenRouter's *daily*
usage would invent a discrepancy. A persistent negative Δ is spend on this key
that opencode did not produce — another harness, or a stray script.

| Date (UTC) | OR total | OR daily | OR weekly | OR monthly | Key limit | Remaining | oc sessions | oc total | Δ |
|---|---|---|---|---|---|---|---|---|---|
HEADER
fi

printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$(date -u +%Y-%m-%d)" "$total" "$daily" "$weekly" "$monthly" \
    "$limit" "$remaining" "$oc_sessions" "$oc_cost" "$delta" >>"$LOG"

echo "ledger: appended to ${LOG#"$ROOT"/}"
printf '  OpenRouter total $%s · daily $%s · monthly $%s\n' "$total" "$daily" "$monthly"

if [ "$limit" != "none" ]; then
    printf '  spend ceiling: per-key limit $%s\n' "$limit"
elif [ "$credits_left" != "-" ]; then
    # A balance is a real ceiling, so this is not a warning. It is reported
    # every run because it is the number that decides when work stops, and
    # because it is the only ceiling the ledger can actually see.
    printf '  spend ceiling: $%s credits remaining (no per-key limit)\n' "$credits_left"
else
    cat >&2 <<'WARN'

  WARNING: nothing readable is stopping spend on this OpenRouter key.
  There is no per-key limit, and the credit balance could not be read — so
  neither control this ledger can see is in force. A cost control holds
  regardless of which harness spends the money: opencode, Claude Code, Codex
  or a stray script.

  Set a per-key limit at openrouter.ai/settings/keys.

  A workspace-level Guardrail would also hold, but it is invisible here — the
  management endpoints answer 401 to a normal API key — so it cannot silence
  this. That is deliberate: reading it would mean holding a second, more
  powerful secret on every machine that runs the ledger.
WARN
fi
