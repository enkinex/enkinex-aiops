# enkinex MCP server

GENERATED into each repo as `.agents/mcp/`. Source of truth: enkinex-aiops
`mcp/`. Change it there and run `just sync-opencode`.

Phase 4's three tools as **one MCP server**, not three
`.opencode/tools/*.ts` files. Custom opencode tools are opencode-only by
construction; MCP is the one tool-extension surface opencode, Claude Code and
Codex all speak, so a single implementation serves every harness.

| Tool | Available when | Does |
|---|---|---|
| `kcl_vet` | `kcl.mod` exists | Runs the repo's own `just test` gate; returns pass/fail plus compiler diagnostics |
| `kcl_docs` | `kcl.mod` exists | Runs `just docs` and reports whether the **committed** reference was stale |
| `project_state` | `plan/`, `discovery/` or `architecture/` exists, **or** the planning sibling has a folder for this repo | Summarises plans and ADRs with their status lines |

## The catalog is derived from the repo

ADR-0002 denies GitHub MCP because a tool catalog is ambient per-session cost.
That applies to this server too, so it advertises only what the repo can
actually use: enkinex-odcs sees the two KCL tools, enkinex-aiops sees
`project_state`, and enkinex-org-website sees an **empty catalog** and pays
nothing.

## Plans that live somewhere else

Planning is centralised in a private sibling, one folder per repo, so the
repositories `project_state` is most useful in are exactly the ones with no
`plan/` of their own. Reaching for those plans is **opt-in**:

```bash
export ENKINEX_PM_ROOT=~/Develop/enkinex/enkinex-pm
```

Unset — the default, and the only thing a clone without that sibling can do —
this server is exactly what it was: local directories only, and a repo with
none of them still pays nothing. Set, `project_state` also reads
`$ENKINEX_PM_ROOT/plan/<repo>/`, keyed on the checkout's directory name, and
prefixes those paths with the sibling's name so they are not mistaken for
paths in the repo you are standing in.

Opt-in rather than hardcoded because this server ships inside **public**
repositories. A public tool that assumed a private path would fail for every
reader who does not hold that clone, and would leak the layout of a repo they
cannot see. The variable is also why this is not an ADR: the default behaviour
is unchanged, so the decision is reversible by unsetting it.

Two ways to get an empty answer, and they have different fixes — the tool says
which one applies rather than returning a bare "nothing found".

## Wiring

| Harness | Declared in | Form |
|---|---|---|
| opencode | `opencode.jsonc` → `mcp.enkinex` | `{"type":"local","command":["node",".agents/mcp/enkinex.mjs"]}` |
| Claude Code | `.mcp.json` (project scope, committed) | `mcpServers.enkinex` |
| Codex | `~/.codex/config.toml` → `[mcp_servers.enkinex]` | user-level; see below |

Codex reads MCP servers from its own config, which is user-level. enkinex
tooling never writes to `$HOME` (ADR-0005), so add this yourself once:

```toml
[mcp_servers.enkinex]
command = "node"
args = [".agents/mcp/enkinex.mjs"]
```

## Implementation notes

Zero dependencies, hand-rolled JSON-RPC over stdio, matching `.githooks/` and
`policy/guard.mjs`. The layer is distributed by file copy into repos with no
install step, so a server needing `npm install` before it runs would not be
governance that travels with the repo.

Two constraints the stdio transport imposes, both of which bit during
development:

- **stdout carries MCP messages and nothing else.** Every child process is
  captured, never inherited; diagnostics go to stderr.
- **A tool call can outlive stdin.** `just test` takes seconds, and exiting the
  moment the client closes stdin kills the child and returns nothing. The
  server drains in-flight requests before exiting.
