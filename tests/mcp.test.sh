#!/usr/bin/env bash
# Regression suite for mcp/enkinex.mjs.
#
# The stdio transport is unforgiving in ways that fail silently: one stray byte
# on stdout corrupts the stream, and exiting while a tool call is in flight
# returns nothing at all. Both happened while building this server, so both are
# frozen here.
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

summary
