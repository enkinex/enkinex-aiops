# enkinex-aiops

The **control plane** of the [enkinex](https://enkinex.org) project (Semantic &
Governance as Code). This repo authors the shared agentic-loop artefacts every
sibling repo consumes; it ships no product code of its own.

Governance here is **executable** (ADR-0004): the workflow is defined by the
agents, hooks and policy that run it, not by prose describing them. And it is
**harness-agnostic**: one rule set governs opencode, Claude Code and Codex
through adapters that contain pointers and no rules.

## Layers

| Layer | Artefact | Enforced by |
|---|---|---|
| Instructions | `AGENTS.shared.md` → a generated block in every repo's `AGENTS.md` | the model reading it |
| Harness adapters | `CLAUDE.md` (one `@AGENTS.md` import), `.claude/settings.json`, `.codex/hooks.json`, `.opencode/plugin/` | — pointers only — |
| Permissions | `opencode.jsonc` (interactive), `opencode.headless.json` (unattended, no `ask`) | opencode |
| Git rules | `githooks/` — commit grammar, remote guard, secret scan, branch slug, no main pushes, no rewrites | git, for every author |
| Tool-call rules | `policy/guard.mjs` — hook bypasses, `git add -A`, `gh pr merge`, credential paths | all three harnesses |
| Agents & commands | `opencode/agent/`, `opencode/command/` | opencode |

Distribution is repo-local (ADR-0005): `just sync-opencode` installs the layer
into each sibling, where it is committed and reviewed like any other code.
Nothing is ever written to `$HOME`.

## Commands

| Recipe | What it does |
|---|---|
| `just check` | **The gate** — the regression suite plus a drift check |
| `just test` | 205 cases over hooks, guard, resolved permissions, agent definitions. Offline except the model-pin check, which skips without the `opencode` binary |
| `just sync-opencode` | Install the shared layer into every repo in `REPOS` |
| `just verify-opencode` | Report drift between the sources here and each repo's copy |
| `just ledger` | Append a cost snapshot to `loop/loop-log.md` |
| `just headless <repo> …` | Run opencode unattended under the deny-list profile |

## Repo map

`AGENTS.md` has the full map and the current state of the migration. Plans live
in `plan/`, one-way decisions in `architecture/`, and the analysis feeding both
in `discovery/` — start with
[`discovery/opencode/harness-agnostic-review.md`](discovery/opencode/harness-agnostic-review.md).

## Working here

Hooks are inert until a clone is pointed at them:

```bash
git config core.hooksPath .githooks
```

`just sync-opencode` does this for every repo it touches. Never pass
`--no-verify`; if a hook refuses, fix the cause.
