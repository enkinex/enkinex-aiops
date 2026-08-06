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
  `Refs:` footer pointing at the plan section delivered, no `Closes:`/
  `Fixes:`/`Resolves:` (there are no GitHub Issues).
- **No repo-name scope.** A scope is optional and names a *module inside
  this repo* (`catalog`, `quality`, `trust`, `githooks`), never the repo
  itself: `feat(odcs):` inside enkinex-odcs says nothing the repository
  does not already say. Package-name scopes are a monorepo device; these
  are separate repos. The `commit-msg` hook rejects a redundant scope.
- **Never push, merge, or open PRs unless the user explicitly asks.** The
  iteration ends at a local commit. `gh` CLI is the only GitHub surface
  (ADR-0002): no GitHub MCP, no Actions, no Issues/Projects/Releases.
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

Repos plan at the root level: `plan/` (active plans; finished work moves
to `plan/done/`), `discovery/` (analysis feeding plans), `architecture/`
(ADRs). ADRs record one-way decisions only — procedural workflows are
defined as executable artefacts (agents, commands, loop tasks, plugin
hooks), never as ADR prose (ADR-0004, executable governance). Commit
`Refs:` footers point at the delivered `plan/` section.

### Model tiers (OpenRouter)

| Tier | Models | Use |
|---|---|---|
| Free | `:free` suffixed IDs | explore/triage, formatting, titles |
| Mid | `moonshotai/kimi-k2`, `deepseek/deepseek-v3.2`, `google/gemini-3.5-flash` | code edits, docs, tests |
| Frontier | `moonshotai/kimi-k3` (default), `anthropic/claude-opus-5`, `openai/gpt-5.6` family | plans, reviews, ADRs |

Do not switch tiers silently; model pins change only via PR.

### Code standards

- KCL libraries: one module per concern, docstrings on every schema and
  field (they feed `just docs`), `check` rules for enums/constraints,
  `kcl vet` fixtures under `test/`. Gate: `just check` (fmt + lint + test).
- Stage explicit paths only — never `git add -A` / `git add .`; skip
  anything that looks like a secret.
