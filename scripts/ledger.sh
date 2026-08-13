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
LOG="$ROOT/loop/loop-log.md"

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

if [ "$limit" = "none" ]; then
    cat >&2 <<'WARN'

  WARNING: this OpenRouter key has NO spend limit.
  Per-key limits are the only cost control that holds regardless of which
  harness spends the money — opencode, Claude Code, Codex or a stray script.
  Set one at openrouter.ai/settings/keys, or provision per-tier keys via the
  management API.

  NOTE: a workspace-level limit (OpenRouter Guardrails) is NOT visible here —
  /api/v1/key exposes only the per-key limit. If one is set, this warning is a
  false positive. Tracked as AIOPS-15.
WARN
fi
