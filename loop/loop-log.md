# Loop cost ledger

Appended by `just ledger` (enkinex-aiops `scripts/ledger.sh`). OpenRouter
`/api/v1/key` is the source of truth; the opencode columns are an independent
cross-check. Both cost columns are cumulative: `opencode stats --days N`
does not window cost on this build, so comparing it to OpenRouter's *daily*
usage would invent a discrepancy. A persistent negative Δ is spend on this key
that opencode did not produce — another harness, or a stray script.

| Date (UTC) | OR total | OR daily | OR weekly | OR monthly | Key limit | Remaining | oc sessions | oc total | Δ |
|---|---|---|---|---|---|---|---|---|---|
| 2026-08-04 | 13.3848 | 6.1587 | 13.3848 | 13.3848 | none | - | 29 | 13.35 | -0.0348 |
