#!/usr/bin/env bash
# Regression suite for the MCP layer: mcp/enkinex.mjs, and the context7
# declaration that ships beside it.
#
# The stdio transport is unforgiving in ways that fail silently: one stray byte
# on stdout corrupts the stream, and exiting while a tool call is in flight
# returns nothing at all. Both happened while building this server, so both are
# frozen here.
#
# context7 fails silently in a different way — it is remote, so it can move or
# stop answering without any local file changing. The cases here cover the part
# of that this repo owns (the declarations agreeing, and opencode loading them);
# they deliberately stop short of asserting the endpoint answers, so the gate
# does not ride on a third party's uptime.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

SERVER="$ROOT/mcp/enkinex.mjs"

# rpc <cwd> <json-line...> — feeds lines to the server, echoes stdout.
rpc() {
    local cwd="$1"; shift
    printf '%s\n' "$@" | (cd "$cwd" && timeout 300 node "$SERVER" 2>/dev/null)
}

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

jq_field() { node -e '
  let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
    const [id, path] = process.argv.slice(1);
    for (const line of s.split("\n").filter(Boolean)) {
      let m; try { m = JSON.parse(line); } catch { continue; }
      if (String(m.id) !== id) continue;
      let v = m;
      for (const k of path.split(".")) v = v?.[k];
      console.log(typeof v === "object" ? JSON.stringify(v) : String(v));
    }
  });' "$1" "$2"; }

section "handshake"
OUT="$(rpc "$ROOT" "$INIT")"
assert_contains "responds to initialize"      "$OUT" '"serverInfo"'
assert_contains "echoes the client protocol"  "$OUT" '"protocolVersion":"2025-06-18"'
assert_contains "advertises the tools capability" "$OUT" '"tools"'

# An unknown protocol version must not be echoed blindly.
OUT="$(rpc "$ROOT" '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"banana"}}')"
assert_contains "falls back on a bogus protocol version" "$OUT" '"protocolVersion":"2025-06-18"'

section "stdout carries only MCP messages"
# Every line on stdout must be parseable JSON-RPC. A child process writing to
# an inherited stdout would corrupt the stream and break the client silently.
OUT="$(rpc "$ROOT" "$INIT" "$LIST" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"project_state","arguments":{}}}')"
BAD="$(node -e '
  let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
    let bad = 0;
    for (const l of s.split("\n").filter(x=>x.trim())) {
      try { const m = JSON.parse(l); if (m.jsonrpc !== "2.0") bad++; } catch { bad++; }
    }
    console.log(bad);
  });' <<<"$OUT")"
[ "$BAD" = "0" ] && ok "every stdout line is valid JSON-RPC" ||
    no "every stdout line is valid JSON-RPC" "$BAD malformed line(s)"

section "catalog is derived from the repo"
catalog_of() { rpc "$1" "$LIST" | jq_field 2 result.tools; }

AIOPS="$(catalog_of "$ROOT")"
assert_contains "aiops exposes project_state" "$AIOPS" 'project_state'
case "$AIOPS" in *kcl_vet*) no "aiops hides the KCL tools" "aiops has no kcl.mod" ;; *) ok "aiops hides the KCL tools" ;; esac

KCL_REPO="$ROOT/../enkinex-odcs"
if [ -f "$KCL_REPO/kcl.mod" ]; then
    ODCS="$(catalog_of "$KCL_REPO")"
    assert_contains "a KCL repo exposes kcl_vet"  "$ODCS" 'kcl_vet'
    assert_contains "a KCL repo exposes kcl_docs" "$ODCS" 'kcl_docs'
else
    ok "skipped: enkinex-odcs not present"
fi

# The token-economy property: a repo with neither kcl.mod nor plan/ pays nothing.
EMPTY="$(mktemp -d)"; trap 'rm -rf "$EMPTY"' EXIT
[ "$(catalog_of "$EMPTY")" = "[]" ] && ok "an unrelated repo gets an empty catalog" ||
    no "an unrelated repo gets an empty catalog" "got $(catalog_of "$EMPTY")"

section "tool calls"
OUT="$(rpc "$ROOT" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"project_state","arguments":{}}}')"
assert_contains "project_state returns content" "$OUT" '"content"'
assert_contains "project_state finds the loop plan" "$OUT" 'plan/opencode/loop.md'
[ "$(jq_field 3 result.isError <<<"$OUT")" = "false" ] && ok "project_state is not an error" ||
    no "project_state is not an error"

section "a tool call outliving stdin still answers"
# Regression: the server used to exit on stdin EOF, killing an in-flight child
# and returning nothing. Only reproducible with a tool that takes real time.
if [ -f "$KCL_REPO/kcl.mod" ]; then
    OUT="$(rpc "$KCL_REPO" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"kcl_vet","arguments":{}}}')"
    [ -n "$OUT" ] && ok "kcl_vet answers after stdin closes" ||
        no "kcl_vet answers after stdin closes" "no response: the server exited mid-call"
    assert_contains "kcl_vet reports a verdict" "$OUT" 'kcl vet fixtures'
else
    ok "skipped: no KCL repo to exercise a slow tool"
fi

section "errors"
OUT="$(rpc "$ROOT" '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}')"
assert_contains "unknown tool is a JSON-RPC error" "$OUT" '"error"'
# A tool the repo does not qualify for must be refused, not run.
OUT="$(rpc "$ROOT" '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"kcl_vet","arguments":{}}}')"
assert_contains "a tool outside the catalog is refused" "$OUT" '"error"'
OUT="$(rpc "$ROOT" '{"jsonrpc":"2.0","id":5,"method":"nonsense/method"}')"
assert_contains "unknown method is -32601" "$OUT" '-32601'
OUT="$(rpc "$ROOT" 'this is not json' "$LIST")"
assert_contains "an unparseable line does not kill the server" "$OUT" '"tools"'

section "notifications take no response"
OUT="$(rpc "$ROOT" '{"jsonrpc":"2.0","method":"notifications/initialized"}')"
[ -z "$(tr -d '[:space:]' <<<"$OUT")" ] && ok "notification produces no output" ||
    no "notification produces no output" "got: $OUT"

# ── context7 ───────────────────────────────────────────────────────────────
# The other server in the baseline, and the only third-party HTTP dependency
# the shared layer ships to every repo in REPOS. Nothing else in the suite
# would notice its endpoint moving, or the opencode and Claude Code
# declarations drifting apart and pointing at different servers.
C7_URL="https://mcp.context7.com/mcp"
BASELINE="$ROOT/opencode.jsonc"
ADAPTER="$ROOT/mcp/adapters/mcp.json"

section "context7 is declared the same way to every harness"
grep -Fq "$C7_URL" "$BASELINE" &&
    ok "the opencode baseline declares the endpoint" ||
    no "the opencode baseline declares the endpoint" "expected $C7_URL in opencode.jsonc"

grep -Fq "$C7_URL" "$ADAPTER" &&
    ok "the Claude Code adapter declares the same endpoint" ||
    no "the Claude Code adapter declares the same endpoint" \
        "opencode and .mcp.json would reach different servers"

if node -e 'const c = require(process.argv[1]);
  const s = c.mcpServers || {};
  process.exit(s.enkinex && s.context7 ? 0 : 1);' "$ADAPTER" 2>/dev/null; then
    ok "the adapter is valid JSON carrying both servers"
else
    no "the adapter is valid JSON carrying both servers" \
        "mcpServers must parse and declare enkinex and context7"
fi

section "opencode resolves context7 as a declared server"
# Presence, deliberately NOT reachability. Asserting "connected" would put a
# free unauthenticated third-party endpoint on the critical path of `just
# check`, so an outage or a rate-limit would redden a gate that has nothing to
# do with the change under test — and a flaky gate is one people learn to
# ignore. What is asserted is that opencode parses the declaration and
# registers the server, which is the part this repo controls.
#
# The accepted gap: an endpoint that has moved or gone away still passes here,
# because opencode lists a declared server whether or not it answers. That risk
# is carried by the two declaration cases above plus a human noticing docs
# lookups failing, not by this suite.
#
# Guarded like the model pins in agents.test.sh: an absent binary is
# environmental (CI runs without it) and skips.
if ! command -v opencode >/dev/null 2>&1; then
    ok "skipped: opencode not installed, so the server list is unavailable"
else
    MCP_LIST="$(cd "$ROOT" && timeout 120 opencode mcp list 2>/dev/null |
        sed -e 's/\x1b\[[0-9;]*m//g' || true)"
    if [ -z "$MCP_LIST" ]; then
        no "opencode reports the server list" "opencode mcp list returned nothing"
    elif grep -q 'context7' <<<"$MCP_LIST"; then
        ok "context7 is registered"
    else
        no "context7 is registered" \
            "declared in opencode.jsonc but opencode did not load it — check the mcp block parses"
    fi
fi

summary
