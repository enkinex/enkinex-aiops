# enkinex-aiops

The **control plane** of the enkinex project (Semantic & Governance as
Code). This repo authors the shared agentic-loop artefacts consumed by
every sibling; it writes no product code itself.

## Sibling projects (flat clones under `~/Develop/enkinex/`)

| Repo | What it is |
|---|---|
| [enkinex-odcs](../enkinex-odcs) | KCL library for the Open Data Contract Standard (ODCS v3.1.0) — published |
| [enkinex-odps](../enkinex-odps) | KCL library for the Open Data Product Standard (ODPS v1.0.0) — published |
| [enkinex-okf](../enkinex-okf) | KCL library for Google's Open Knowledge Format (OKF v0.2) — `v0.2-draft`; frontmatter families only |
| [enkinex-databricks](../enkinex-databricks) | KCL library for Databricks Asset Bundles — v0.1.0 scaffold; benchmark vehicle of the opencode migration |
| [enkinex-ossie](../enkinex-ossie) | KCL library for Apache Ossie (0.2.0.dev0) — earliest in its lifecycle; `SemanticModel` and one field so far |
| [enkinex-knowledge-base](../enkinex-knowledge-base) | KbDev. Public and empty; the OKF corpus is built in Phase 3 of the successor plan |
| [enkinex-odcs-tutorial](../enkinex-odcs-tutorial) | Worked ODCS example, pinned to the library version it teaches |
| [enkinex-odps-tutorial](../enkinex-odps-tutorial) | Worked ODPS example, pinned to the library version it teaches |
| [enkinex-org-website](../enkinex-org-website) | enkinex.org — Docusaurus 3 + TypeScript, deployed via Wrangler. Private; its pre-publication scan found no Cloudflare or analytics secrets |
| [.github](../.github) | Org profile. WebDev; protection but no CI — a profile README has nothing to gate |

## Repo map

| Path | Purpose |
|---|---|
| `opencode.jsonc` | **Shared baseline config — source of truth** (ADR-0005): model tiers, permission posture. Synced to every sibling's repo root via `just sync-opencode`; drift reported by `just verify-opencode`. Active in this repo as-is. |
| `AGENTS.shared.md` | **Shared enkinex-wide instructions — source of truth.** Not distributed as a file: its content is injected into every repo's `AGENTS.md` as a delimited generated block, so opencode, Codex and Claude Code all read the same rules. |
| `AGENTS.md` | This file — repo-specific instructions (auto-loaded) plus the generated shared block. Edit outside the markers only. |
| `CLAUDE.md` | Generated Claude Code adapter — a single `@AGENTS.md` import, no rules of its own. |
| `opencode.headless.json` | **Headless permission overlay — source of truth.** Plain JSON (opencode rejects comments inline); no `ask` actions, so unattended runs behave the same with or without `--auto`. Rationale in `scripts/opencode-headless.sh`. |
| `githooks/` | **Git hook sources** — `commit-msg`, `pre-commit`, `pre-push`. The mechanical form of the rules AGENTS.md states; synced to every repo's `.githooks/` and activated via `core.hooksPath`. |
| `.githooks/` | Symlink → `githooks/` so the sources are live here without duplication. |
| `policy/` | **Policy guard — source of truth.** `guard.mjs` (all rules) plus `adapters/` for Claude Code and Codex; the opencode adapter is `opencode/plugin/enkinex-guard.js`. Synced to `.agents/policy/`, `.claude/settings.json`, `.codex/hooks.json`. See `policy/README.md`. |
| `.agents/` | Harness-neutral artefact root; `policy` is a symlink → `../policy`. |
| `.claude/` `.codex/` | Generated pointer-only adapters — a hook entry each, no rules. |
| `loop/` | Loop runner inputs and logs: `tasks/*.yaml` specs, `runs.md` (per-run), `loop-log.md` (cumulative cost). `just loop <task>`, `just loop-status`. |
| `tests/` | **Golden-set regression** over the executable governance artefacts — 223 cases, no token cost. `just test`; gated by `just check`. Hermetic except one section: model pins are validated against the live OpenRouter catalog when the `opencode` binary is present, and skipped when it is not (CI). |
| `loop/loop-log.md` | Cost ledger, appended by `just ledger` (OpenRouter `/api/v1/key` as source of truth, `opencode stats` as cross-check). |
| `mcp/` | **enkinex MCP server — source of truth.** `enkinex.mjs` (kcl_vet, kcl_docs, project_state) plus the Claude Code `.mcp.json` adapter. Catalog is derived from the repo, so an unrelated repo pays nothing; `project_state` reaches the private planning sibling only when `ENKINEX_PM_ROOT` is set. See `mcp/README.md`. |
| `scripts/shared-layer.sh` | Distribution helpers sourced by the Justfile (block injection, hook install, policy install, drift checks). |
| `scripts/ledger.sh` | Cost snapshot writer; warns while the OpenRouter key has no spend limit. |
| `scripts/opencode-headless.sh` | Launcher for unattended runs (`just headless <repo> …`); documents why the headless profile exists and how it is delivered. |
| `opencode/` | Executable-artefact sources: `agent/` (10 agents — 5 github workflow + 5 loop), `command/` (`/ci-*` chain); later `tools/`, `plugin/`, `skills/` (loop.md Phase 4). Synced to siblings' `.opencode/`. Note `tools` is plural: opencode never reads `.opencode/tool`. |
| `.opencode/` | **Symlinks only** (`agent`, `command` → `../opencode/…`) so the sources are live in this repo without duplication. |
| `architecture/` | ADRs — one-way decisions only (ADR-0004): 0002 opencode + OpenRouter adoption, 0004 executable governance, 0005 repo-local distribution. **The only planning surface left in this repo.** |

### Planning lives elsewhere

The shared block below states the rule. What is specific to this repo:
`plan/`, `discovery/` and `.prompts/` were here and are gone, and this
repo's folder is `../enkinex-pm/plan/enkinex-aiops/`, with the five
relocated documents under its `refactor/` awaiting triage.

Two consequences worth knowing before you act on them. Paths into
`../enkinex-pm/` resolve only for someone holding that clone, which is why
`README.md` — written for a public reader — names no path into it. And
`project_state` reads those plans only when `ENKINEX_PM_ROOT` is set; unset,
it reports this repo's ADRs and nothing more (`mcp/README.md`).

## Workflow (locked)

1. `git fetch origin`, confirm sync with `main`, branch
   `<type>/<short-slug>`.
2. Work; commit with `<type>: <imperative ≤72>` + `Refs:` footer
   (plan section) at the end of the iteration.
3. **Never push or open a PR unless explicitly asked.** Squash-merge +
   `--delete-branch` is the only merge path.
4. GitHub via `gh` CLI only — no MCP, no Actions, no Issues/Projects
   (ADR-0002). Permission posture is mechanical in `opencode.jsonc`.

## Current state

- v0.2.0 — opencode + OpenRouter agent loop (`../enkinex-pm/plan/enkinex-aiops/refactor/loop.md`),
  Phases 0–6 done. Phase 7 dogfooding is partial: proven against
  `enkinex-okf`, blocked in `enkinex-odcs` by a loop hang tracked in
  `../enkinex-pm/plan/enkinex-aiops/refactor/harness-and-dogfooding.md` §2.1.
- **Commit `Refs:` footers changed shape on 2026-08-13** (AIOPS-10). Before
  that date they are repo-relative paths into `plan/`, `discovery/` or
  `../enkinex-lab/` — directories that have since moved or gone, so those
  footers resolve for nobody. After it they are task IDs (`AIOPS-10`)
  resolving under `../enkinex-pm/plan/<repo>/`, and `commit-msg` enforces the
  shape rather than merely checking the line is non-blank. History is not
  rewritten and the old footers are not errors; the discontinuity is recorded
  here so it is explained rather than discovered. Note `enkinex-manager` holds
  a copy of the hook but is outside `REPOS`, so its copy stays permissive
  until [MGR-12](../enkinex-pm/plan/enkinex-manager/12-adr-0001-repoint.md)
  settles that repo's conventions.
- **This repository was recreated from a clean root commit on 2026-08-06**
  and published. The previous forty-commit history carried agent-memory and
  task-spec files describing a private system; the disposition is recorded in
  the successor plan §1.3. The decisions survive in `architecture/`, in the
  relocated plans and this file; the `Refs:` chain does not.
- **Successor-plan Phase 1 is applied.** Ten public repositories, all with
  `main` protected: merge restricted, code-owner review, linear history, and
  a required `test` check on the seven that have code. `v*` tags protected on
  the versioned libraries and tutorials; secret scanning, push protection and
  Dependabot alerts on; 2FA required org-wide; four teams at `write`. Applied
  and drift-checked by `governance/apply-governance.sh` in the private
  `enkinex-pm`, which discovers public repos rather than listing them.
- **The shared layer is live in all six repos** — the five library and
  website adoption PRs merged 2026-08-06. `enkinex-ossie` joined last: it had
  never been in `REPOS`, so the sync had never targeted it.
- Open: `enkinex-org-website` is still private (scanned clean, publication is
  a decision not a blocker); `enkinex-knowledge-base` is empty until Phase 3;
  retrospective credential scans are owed on `enkinex-databricks` and
  `enkinex-odps-tutorial`, both published before a scan was run.
- Known-open harness items are §2 of
  `../enkinex-pm/plan/enkinex-aiops/refactor/harness-and-dogfooding.md`: the odcs loop hang,
  free-tier viability, agent-output evals, OpenRouter model-level fallback,
  and the ledger's spend-limit check.
- opencode is the primary agent runtime; Claude Code and Codex are supported
  through pointer-only adapters that carry no rules of their own.

<!-- BEGIN GENERATED: enkinex-aiops/AGENTS.shared.md — do not edit here; run "just sync-opencode" in enkinex-aiops -->
## Shared enkinex rules

> GENERATED from enkinex-aiops `AGENTS.shared.md` (ADR-0005). Do not edit
> this block in a sibling repo — change the source in enkinex-aiops and run
> `just sync-opencode`.

Enkinex is an open-source **Semantic & Governance as Code** project: KCL
libraries that implement open standards (ODCS, ODPS, OKF) and platform
configuration surfaces (Databricks Asset Bundles) as typed, modular code.

### Git workflow (locked)

- Branch slug: `<type>/<short-slug>`; `type` ∈ `feat · fix · refactor ·
  docs · chore · test · infra · proj`; slug kebab-case, ≤6 words,
  imperative (e.g. `feat/output-port-retry-policy`).
- Commits: Conventional Commits subset `<type>: <imperative ≤72>`,
  `Refs: <TASK-ID>` footer naming the task delivered, no `Closes:`/
  `Fixes:`/`Resolves:` — issues are closed by hand after the squash merge,
  not as a side effect of a commit message (ADR-0006).
- **No repo-name scope.** A scope is optional and names a *module inside
  this repo* (`catalog`, `quality`, `trust`, `githooks`), never the repo
  itself: `feat(odcs):` inside enkinex-odcs says nothing the repository
  does not already say. Package-name scopes are a monorepo device; these
  are separate repos. The `commit-msg` hook rejects a redundant scope.
- **Never push, merge, or open PRs unless the user explicitly asks.** The
  iteration ends at a local commit. `gh` CLI is the only GitHub surface
  (ADR-0002): no GitHub MCP, no Actions, no Projects, no Releases.
  **Issues are open** (ADR-0006): read them freely, creating or editing one
  is a prompt, and `gh issue delete`/`transfer` are denied outright.
- Never force-push to `main`; never rewrite history.
- Before any repo edit: `git fetch origin`, confirm sync with `main`,
  create the branch. Commit at the end of the iteration.

### Mechanical enforcement

The rules above are enforced by git hooks in `.githooks/`, not by your
compliance: `commit-msg` checks the subject grammar and the `Refs:` footer,
`pre-commit` checks the enkinex remote and scans staged content for
credentials, `pre-push` checks the branch slug and refuses direct pushes to
`main` and history rewrites.

A second layer, `.agents/policy/guard.mjs`, covers what git hooks cannot see:
hook bypasses (`--no-verify`, `core.hooksPath` edits), `git add -A`, `gh pr
merge`, and reads of credential paths. One script; opencode, Claude Code and
Codex each call it through a pointer-only adapter.

- **Never pass `--no-verify`.** If a hook refuses, fix the cause.
- Stage explicit paths. `git add -A`, `git add .` and `git add -u` are denied.
- Hooks are inert until a clone is pointed at them. If
  `git config --get core.hooksPath` is empty, run
  `git config core.hooksPath .githooks` before committing.
- Unattended runs use the headless profile (`opencode.headless.json`), where
  push, rebase, PR creation and PR merge are denied outright rather than
  prompted. Launch through `scripts/opencode-headless.sh` in enkinex-aiops.

### Project lifecycle

**Planning is centralised and private.** Plans live in the sibling
`enkinex-pm`, one folder per repository — `../enkinex-pm/plan/<repo>/`
from a repo checkout — as small numbered task files. **A repo with no
local `plan/` is correct, not misconfigured**; do not create one, and do
not plan in the repo you are editing.

There is no `discovery/` stage. Analysis feeding a plan is an input to
planning and belongs in `enkinex-pm`, not beside the code.

`architecture/` stays at each repo root. ADRs record one-way decisions
only — procedural workflows are defined as executable artefacts (agents,
commands, loop tasks, plugin hooks), never as ADR prose (ADR-0004,
executable governance). A repo's ADRs are public with its code, so an ADR
citing a plan cites something the reader may not be able to open: say so
at the citation rather than leaving a path that resolves for nobody.

A commit's `Refs:` footer names the task it delivers by its **stable task
ID** — a project prefix plus the task's file number, `AIOPS-10`, `MGR-16`,
`PM-04` — resolving to `../enkinex-pm/plan/<repo>/<NN>-<slug>.md`.
Separate several with commas. Never write the path: the ID survives a file
being renamed or re-numbered, and a path encodes one machine's checkout
layout into permanent history. The ID resolves only for someone holding the
`enkinex-pm` clone — a cost this org has accepted deliberately.

Use `No-Plan-Ref: <reason>` when a commit advances no task. It is the
**correct footer, not a bypass** — repo hygiene, tooling and dependency
bumps legitimately advance no plan, and inventing a task ID to satisfy the
hook is the failure this escape hatch prevents.

`commit-msg` enforces both shapes. **Footers changed shape on 2026-08-13**
(AIOPS-10): commits before that date point at `plan/…` paths that no longer
resolve, commits after name task IDs. Both are readable; neither is
machine-resolvable across the boundary. History is not rewritten and old
footers are not errors — the hook validates only the message being written.

### Model tiers (OpenRouter)

| Tier | Models | Use |
|---|---|---|
| Free | `:free` suffixed IDs | **interactive, bounded lookups only** — never an agent in the loop |
| Mid | `moonshotai/kimi-k2`, `deepseek/deepseek-v3.2`, `google/gemini-3.5-flash` | code edits, docs, tests, exploration |
| Frontier | `moonshotai/kimi-k3` (default), `anthropic/claude-opus-5`, `openai/gpt-5.6` family | plans, reviews, ADRs |

Do not switch tiers silently; model pins change only via PR.

**No agent is pinned to the free tier, and that is the decision, not an
oversight** (AIOPS-12). The row above said "explore/triage", and the one agent
that took it at its word could not do the job: it failed to finish a broad
exploration step in 10 minutes on two occasions, it spends its output budget
reasoning before it answers, and it returns `502 ResourceExhausted` from the
upstream provider often enough to have done so during unrelated work. The
first is a prompt problem; the other two are not, and a step that never
returns is the most expensive failure an unattended run has — nobody is
watching, and it has to be killed.

Free is therefore for questions **you** ask, bounded, with a human reading the
answer and nothing depending on it arriving. Anything the loop runs is mid or
frontier. The evidence sits at the pin in `explore-enkinex.md`, so re-pinning
to free means arguing with it rather than rediscovering it.

### Code standards

- KCL libraries: one module per concern, docstrings on every schema and
  field (they feed `just docs`), `check` rules for enums/constraints,
  `kcl vet` fixtures under `test/`. Gate: `just check` (fmt + lint + test).
- Stage explicit paths only — never `git add -A` / `git add .`; skip
  anything that looks like a secret.
<!-- END GENERATED -->
