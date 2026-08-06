# Discovery — Harness-Agnostic Agentic Governance: review of v0.2.0 Phases 1–3 and research

- Status: Draft for review
- Date: 2026-08-04 (rev. 2 — adds §8, OKF as the knowledge layer)
- Reviews: `plan/opencode/loop.md` (Phases 0–7), `plan/opencode/benchmark-enkinex-databricks.md`,
  ADR-0002, ADR-0004, ADR-0005, the landed `opencode/` artefacts, the four sibling repos, and
  `enkinex-okf` (`v0.2-draft`).
- Feeds: proposed ADR-0006 (harness-agnostic artefact layer), proposed ADR-0007 (OKF as the
  knowledge substrate), revision of `plan/opencode/loop.md` Phases 3–7.
- Method: filesystem + git inspection of all six repos; empirical probes of the installed
  opencode 1.18.11 binary and its published JSON schema; empirical probes of KCL 0.12.7 codegen
  capability; documentation research against official sources (opencode.ai, code.claude.com,
  openai/codex, openrouter.ai, agentskills.io, GoogleCloudPlatform/knowledge-catalog, GitHub docs).

---

## 1. Executive summary

The v0.2.0 migration is directionally right and the executable-governance principle (ADR-0004) is
the correct organising idea. Three things need to change.

1. **Phase 3 has not landed.** No sibling repo contains a `.opencode/opencode.jsonc` overlay, and
   no LSP or MCP block exists anywhere in the shared config. The plan and `AGENTS.md` should not
   record Phase 3 as done.
2. **The current setup governs opencode only.** In every repo, all enkinex rules reach the model
   through `opencode.jsonc` → `instructions: ["AGENTS.shared.md"]`. Claude Code reads neither file
   and there is no `CLAUDE.md`; Codex reads `AGENTS.md` but not `AGENTS.shared.md`. So **Claude
   Code currently runs completely ungoverned in all five repos, and Codex runs partially
   governed.** This is the direct cause of the vendor-neutrality problem the user is asking about,
   and it is fixable with three near-empty adapter files per repo.
3. **Enforcement is in the wrong layer.** Phase 2 discovered empirically that prompt guards are
   advisory; Phase 4 answers with an opencode-only TypeScript plugin. That re-creates lock-in at
   the exact point where lock-in hurts most. The enforcement that is genuinely agnostic — and that
   also binds humans — is **git hooks plus the provider-side controls at OpenRouter**, with
   per-harness hook adapters as a second line.

A fourth point was added after reviewing `enkinex-okf`:

4. **OKF is the right substrate for the governance corpus, and it closes a gap the first three
   points leave open.** §5 makes the *artefacts* portable but leaves the rules themselves as
   undated, unattributed, unverifiable prose in `AGENTS.md`. OKF's `generated` / `verified` /
   `status` / `stale_after` / `sources` families make a governance document self-describing, and
   its `Attested Computation` type is — almost exactly — the executable-governance contract
   ADR-0004 asks for. Generating skills and docs from an OKF/KCL bundle is feasible (proven
   empirically in §8.3) and worth doing, with one correction to the proposed design: **generate at
   build time and commit the output**, not at session start.

Everything else in this document elaborates those points and lists the concrete defects found.

---

## 2. Verified state (2026-08-04)

| Claim | Verified? | Evidence |
|---|---|---|
| Phase 1 — shared baseline config + sync/verify recipes | ✅ | `just verify-opencode` → "shared layer in sync across all sibling repos" |
| Phase 2 — 10 agents + 5 `/ci-*` commands, synced | ✅ | `opencode agent list` shows all 10 project agents alongside 7 built-ins |
| aiops symlinks `.opencode/agent|command` → `../opencode/…` | ✅ | `ls -la enkinex-aiops/.opencode` |
| Phase 3 — KCL LSP registered in repo overlays | ❌ **not implemented** | no `.opencode/opencode.jsonc` in odcs, odps, databricks, website |
| Phase 3 — context7 + Playwright MCP in the baseline | ❌ **not implemented** | no `mcp` key in `opencode.jsonc` |
| Model pins resolve on OpenRouter | ✅ | `opencode models openrouter` lists `moonshotai/kimi-k2`, `moonshotai/kimi-k3`, `nvidia/nemotron-3-nano-30b-a3b:free` |
| `just` installed (benchmark prerequisite) | ✅ | `/usr/bin/just` — the prerequisite checklist in the benchmark plan is stale |
| `databricks` CLI installed (benchmark prerequisite) | ❌ | not on `PATH`; T1 input `dab-schema.json` still blocked |
| All Phase 1/2 work pushed | ❌ | aiops on `proj/aiops-opencode-foundation`, siblings on `docs/opencode-agents-stub`, nothing pushed, no PRs |

Note on the branch state: the four siblings each carry four commits on `docs/opencode-agents-stub`
whose subjects describe Phase-1/Phase-2 adoption work, not a docs stub. The branch slug no longer
matches its content, which the `pr-open` agent's slug check would flag at PR time.

---

## 3. Defects in the landed implementation

### D1 — `just sync-opencode` copies `tool/`, but opencode discovers `.opencode/tools/`

`Justfile:23` and `:44` iterate `agent command tool plugin`. Extracting the config path strings
from the installed binary gives:

```
.opencode/agent   .opencode/agents
.opencode/command .opencode/commands
.opencode/plugin  .opencode/plugins
.opencode/skill   .opencode/skills
.opencode/tools                        ← plural only; no singular form present
```

The official custom-tools documentation agrees: "Custom tools reside in `.opencode/tools/`".
Agent, command, plugin and skill accept both spellings — tools does not. Phase 4's three tools
would be synced into a directory opencode never reads, and would fail silently.

**Fix:** change the sync/verify loop to `agent command tools plugin skills`.

### D2 — the permission posture dissolves in headless mode

Every mutation guard in `opencode.jsonc` is `ask`: `git add`, `git commit`, `git push`,
`git push --force`, `git reset --hard`, `git rebase`, `gh pr create`, `gh pr merge`. The
permissions documentation states that `--auto` "approves requests not explicitly denied" and that
only explicit `deny` survives it. Phase 2's own status note records the complementary failure
(headless `ask` auto-rejects without `--auto`).

So the Phase 5 loop runner has exactly two doors, and both are wrong as currently specified:
without `--auto` it cannot commit; with `--auto` it can **squash-merge a PR unattended** — the one
action ADR-0002 §3 and plan §8.3 declare permanently human-gated.

**Fix (two parts):**

1. Split the posture into an interactive profile and a headless profile. In the headless profile
   the irreversible operations (`git push*`, `gh pr create*`, `gh pr merge*`, `git push --force*`,
   `git reset --hard*`, `git rebase*`) are `deny`, not `ask`. `deny` is the only value with
   headless meaning.
2. Where the loop legitimately needs a gate rather than a wall, answer the permission through the
   SDK instead of `--auto` — `opencode serve` exposes a permission-response endpoint
   (`postSessionByIdPermissionsByPermissionId`), which lets the runner apply policy per request and
   log the decision. Also evaluate `experimental.continue_loop_on_deny` so a denied call degrades
   into a reported gate rather than a dead session.

### D3 — `"just *": "allow"` is an unbounded shell escape

`just` executes arbitrary shell from a file inside the repository. Granting `just *` therefore
grants everything the bash rules below it deny: a recipe can run `git push --force`,
`curl … | sh`, or read a denied path. The same reasoning applies to any wrapper the agent may
invoke.

**Fix:** enumerate the recipes instead — `just check`, `just fmt`, `just lint`, `just test`,
`just docs`, `just init`. opencode's matcher is last-match-wins, so a `"just *": "ask"` catch-all
followed by the specific allows expresses this exactly.

### D4 — `git push --force` and `git reset --hard` are `ask`, not `deny`

`AGENTS.shared.md` says "Never force-push to `main`; never rewrite history." The config gives that
rule no mechanical backing — it is the same `ask` as an ordinary commit. Under `--auto` (D2) it
becomes an allow.

**Fix:** `deny`, and let the rare legitimate case be a human running git directly.

### D5 — the enkinex-remote guard is prose in ten agent files

Phase 2 established empirically that a mid-tier model ignores the "FIRST tool call must be
`git remote get-url origin`" instruction. The guard is currently duplicated verbatim across five
agents and enforced by none of them. Section 5 proposes moving it to a `pre-push`/`pre-commit`
hook, where it is not a request but a precondition — and where it also covers Claude Code, Codex,
and a human with a stale clone.

### D6 — `AGENTS.shared.md` is invisible to every harness except opencode

The shared rules — branch grammar, commit format, `Refs:` footer, the never-push rule, model
tiers, KCL standards — are loaded only because `opencode.jsonc` names the file in `instructions`.
Claude Code reads `CLAUDE.md` and `.claude/rules/` and explicitly does not read `AGENTS.md`; Codex
reads `AGENTS.md` and `AGENTS.override.md`. Neither reads `AGENTS.shared.md`.

Since the 2026-08-03 cleanup deleted `CLAUDE.md` from every repo, **a Claude Code session in any
enkinex repo today receives no enkinex instructions at all.** Section 5.2 fixes this without
adding a Claude-specific configuration layer.

### D7 — plan/prose drift on the frontier model id

The plan and benchmark documents call the default frontier model `moonshotai/kimi-3`; the agent
frontmatter pins `openrouter/moonshotai/kimi-k3`. The frontmatter is the correct one (confirmed
against `opencode models openrouter`). Only the prose needs correcting, but the benchmark
scorecard rows key off the prose spelling.

### D8 — no fallback chains anywhere

Plan §5 requires "OpenRouter provider routing + fallback chains per agent (fallbacks stay inside
the same tier)". Nothing implements this: each agent pins one bare model id. Free-tier rate
limiting is already an observed failure mode (the `gemma-4-31b-it:free` note in `opencode.jsonc`),
so this is the gap most likely to break a long unattended run. See §6.1.

---

## 4. Research findings that change the design

All of the following were verified against primary sources; the confidence column flags what still
needs a hands-on check.

| # | Finding | Confidence |
|---|---|---|
| R1 | `AGENTS.md` is an open standard under the Linux Foundation's Agentic AI Foundation, read natively by Codex, opencode, Copilot, Cursor, Gemini CLI and ~28 other tools. Claude Code does **not** read it, and the official documented bridge is a `CLAUDE.md` containing `@AGENTS.md`, or `ln -s AGENTS.md CLAUDE.md`. | High — code.claude.com/docs/en/memory §AGENTS.md |
| R2 | **Agent Skills (`SKILL.md`) is the portable capability format.** Anthropic published it as an open standard (agentskills.io, Dec 2025), now stewarded by the same foundation. opencode discovers skills at `.opencode/skills/`, `.claude/skills/` **and `.agents/skills/`** (confirmed in the binary's path table). Claude Code discovers `.claude/skills/` and follows symlinks for individual skill directories. Claude Code has merged custom commands into skills — `.claude/commands/deploy.md` and `.claude/skills/deploy/SKILL.md` both produce `/deploy`. | High — opencode.ai/docs/skills, code.claude.com/docs/en/skills, binary strings |
| R3 | **Hook shapes have converged.** Claude Code hooks (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`, `Stop`, `PreCompact`, …) take a JSON payload on stdin and return a decision on stdout — `hookSpecificOutput.permissionDecision: allow\|deny\|ask` for `PreToolUse`, `{"decision":"block","reason"}` elsewhere, exit code 2 as the blocking error. Codex CLI shipped a hooks engine using the same event names, the same stdin/stdout JSON contract, and the same `{"decision":"block"}` response, configured in `.codex/hooks.json` / `~/.codex/hooks.json`. opencode expresses the same interception as a TypeScript plugin hook `tool.execute.before` that throws to abort. | High for Claude Code (official docs); **medium for Codex** — the hooks engine is documented across secondary sources and corroborated by `allow_managed_hooks_only` in the official `requirements.toml` docs, but verify event names and enablement (`[features] codex_hooks = true`) against the installed version before depending on it |
| R4 | **MCP is the only tool-extension surface all three CLIs share.** opencode (`mcp` config key, local/remote), Claude Code (project-scope `.mcp.json`, committed and team-shared), Codex (`mcp_servers` in `config.toml`). Custom tools written as `.opencode/tools/*.ts` are opencode-only by construction. | High |
| R5 | opencode's `references` config (git or local) **cannot distribute agents, commands or plugins** — the v2 documentation states this explicitly. It attaches directories for reading only. So it is not a replacement for `just sync-opencode`. | High — opencode.ai/v2/docs/references |
| R6 | opencode supports **`experimental.openTelemetry`** (OTel spans for every model call) and **`experimental.policies`** (declarative `provider.use` allow/deny statements). Neither is used. OTel is a far better Phase 6 cost/latency ledger than parsing `opencode stats`, and it is the same telemetry surface Claude Code exposes. | High — opencode config JSON schema, `$defs.Config.properties.experimental` |
| R7 | **OpenRouter Guardrails** enforce budgets, model/provider restrictions, ZDR and DLP at the workspace, member-group and API-key level, server-side. Per-key spend limits with daily/weekly/monthly resets are provisioned via `/api/v1/keys`. Model-tier policy is therefore enforceable **outside every CLI**, which makes it harness-agnostic by construction. | High — openrouter.ai/docs/guides/features/guardrails |
| R8 | OpenRouter request-level routing controls: `models` (fallback array), `provider.order`, `provider.allow_fallbacks`, `provider.only` / `ignore`, `provider.sort`, `provider.require_parameters`, `provider.data_collection`, `provider.zdr`, `provider.max_price`. These are the mechanism plan §5's "fallback chains" needs, reachable from opencode through `provider.openrouter.options`. | High |
| R9 | `subagent_depth` defaults to **1** — subagents cannot launch subagents. A loop runner that expects `plan-author` to delegate will silently get nothing. | High — config schema |
| R10 | Claude Code can be driven entirely from flags with no repo footprint: `--settings <path\|json>`, `--setting-sources user,project,local`, `--system-prompt-file`, `--append-system-prompt`, `--mcp-config`, `--agents`, `--permission-mode`, `-p --output-format stream-json`. A harness-neutral repo can therefore be made Claude-governed by a launcher rather than by committed `.claude/` content, if that is preferred to the symlink. | High — code.claude.com/docs/en/cli-reference |
| R11 | The `wshobson/agents` marketplace is a working reference for the multi-harness pattern: one Markdown source-of-truth in `plugins/`, a `make generate HARNESS=<target>` step, harness-native output per target (`.opencode/`, `.gemini/` generated and gitignored; `.agents/plugins/` and `.cursor-plugin/` committed), and downlevelling where a harness lacks a concept (commands → skills). | High |
| R12 | promptfoo is the mature model-agnostic option for golden-set regression in CI (`promptfooconfig.yaml`, pass-rate thresholds, LLM-as-judge assertions). Note for a vendor-neutrality-driven project: OpenAI announced an agreement to acquire it in March 2026; the project remains open source. | Medium-high |
| R13 | opencode ships a first-party GitHub Action (`opencode github install`, `/oc` comment triggers). ADR-0002 forbids Actions, so this is correctly unused — but see §7.2, because the no-Actions rule also removes the only enforcement layer an agent cannot bypass. | High |

---

## 5. The recommended agnostic architecture

The design rule is **one substantive artefact per concern, plus a near-empty adapter per harness.**
An adapter is allowed to exist only if it contains no rules — just a pointer. Judged that way, the
setup below adds three adapter files per repo, totalling roughly ten lines.

```
<repo>/
  AGENTS.md                     ← the only instruction file. Complete, self-contained.
                                  Read natively by opencode + Codex.
  CLAUDE.md                     ← adapter, 1 line: "@AGENTS.md"   (or a symlink)
  .agents/                      ← neutral home for everything portable
    skills/<name>/SKILL.md      ← procedures. Read natively by opencode; symlinked into
                                  .claude/skills for Claude Code.
    policy/guard.mjs            ← ONE enforcement script (stdin JSON → stdout decision)
    policy/rules.json           ← the rules it enforces, as data
  .githooks/                    ← universal enforcement: commit-msg, pre-commit, pre-push
  .mcp.json                     ← MCP servers, Claude Code's native project-scope format
  opencode.jsonc                ← adapter + opencode-only settings (models, permissions, lsp)
  .claude/
    settings.json               ← adapter: hooks → .agents/policy/guard.mjs
    skills -> ../.agents/skills ← symlink
  .codex/
    hooks.json                  ← adapter: hooks → .agents/policy/guard.mjs
```

### 5.1 Layer map

| Concern | Agnostic artefact | opencode | Claude Code | Codex |
|---|---|---|---|---|
| **Knowledge / rule corpus** | **OKF bundle (`enkinex-docs`)** | — source, not consumed directly — | — | — |
| Instructions | `AGENTS.md` | native | `CLAUDE.md` → `@AGENTS.md` | native |
| Procedures / workflows | `.agents/skills/*/SKILL.md` | native (`.agents/skills` is a discovery path) | `.claude/skills` symlink | native skills |
| Tools (`kcl-vet`, `kcl-docs`, `project-state`) | one MCP server | `mcp` key | `.mcp.json` | `mcp_servers` |
| Hard enforcement (git) | `.githooks/*` | — universal — | — universal — | — universal — |
| Hard enforcement (tool calls) | `.agents/policy/guard.mjs` | plugin shells out | `PreToolUse` hook | `PreToolUse` hook |
| Model tier policy & spend | OpenRouter Guardrails + per-key limits | — provider-side — | — provider-side — | — provider-side — |
| Cost/latency telemetry | OpenTelemetry | `experimental.openTelemetry` | `CLAUDE_CODE_ENABLE_TELEMETRY` | OTel exporter |
| Regression | promptfoo suite | — CLI-agnostic — | — | — |
| Model routing per task | *not portable* | agent frontmatter `model` | subagent frontmatter | profiles |

The last row is the honest boundary: per-task model tiering is expressed differently in each
harness and there is no standard for it. Keep it in `opencode.jsonc` and accept that Claude Code
and Codex sessions run on whatever the human picked. Do not build a translation layer for it — the
cost/benefit is bad, and OpenRouter Guardrails already caps the financial downside.

### 5.2 Fixing the instruction gap (D6) concretely

1. Merge `AGENTS.shared.md` into `AGENTS.md` as a delimited generated block, so `AGENTS.md` is
   complete on its own:

   ```markdown
   <!-- BEGIN GENERATED: enkinex-aiops/AGENTS.shared.md — do not edit, run `just sync-opencode` -->
   …shared rules…
   <!-- END GENERATED -->
   ```

   `just sync-opencode` rewrites the block; `just verify-opencode` checksums it. This removes a
   file from every repo root, removes the `instructions` indirection, and makes Codex fully
   governed for free. Keep it under ~200 lines — both Claude Code and opencode degrade in
   adherence on long instruction files.

2. Add `CLAUDE.md` containing exactly `@AGENTS.md` (plus, optionally, a short Claude-specific
   section). This is the mechanism Anthropic documents for repos that standardise on `AGENTS.md`.
   A symlink is the zero-content alternative but breaks on Windows without Developer Mode.

Both options add Claude-named files. If that is unacceptable, R10's launcher route is the
alternative: a `just claude` recipe invoking
`claude --setting-sources user --system-prompt-file AGENTS.md --settings .agents/claude/settings.json`.
It keeps the repo pristine at the cost of the rules only applying when the launcher is used — which
is the same "governance by ritual" failure ADR-0005 rejected. **Recommendation: take the one-line
`CLAUDE.md`.** A file whose entire content is a pointer to the neutral source is not a vendor
layer; it is the absence of one.

### 5.3 Moving enforcement to git hooks

This is the highest-value change in the document. The rules that Phase 2 proved unenforceable as
prompt text are all naturally expressible as git hooks, where they bind every agent and every
human identically:

| Rule (today: prose in 5 agent files) | Hook | Check |
|---|---|---|
| origin must be `github.com:enkinex/` | `pre-commit`, `pre-push` | `git remote get-url origin` |
| branch slug `<type>/<short-slug>` | `pre-push` | regex on `git symbolic-ref` |
| Conventional Commits subset, subject ≤72 | `commit-msg` | regex |
| `Refs:` footer present | `commit-msg` | regex; escape hatch documented and logged |
| no `Closes:`/`Fixes:`/`Resolves:` | `commit-msg` | regex |
| never force-push, never rewrite `main` | `pre-push` | reject non-fast-forward to `main` |
| no secrets staged | `pre-commit` | `gitleaks protect --staged`, or a path/entropy scan |
| `just check` green | `pre-push` | run it |

Wire with `git config core.hooksPath .githooks` in a `just init` recipe — no dependency, works on
every platform git works on, and the hooks are versioned in the repo like any other executable
governance artefact (which is exactly ADR-0004's principle, applied one layer lower).

Two honest limitations: hooks require the one-time `core.hooksPath` bootstrap, and `--no-verify`
bypasses them. Both are answered by a server-side backstop — see §7.2.

`.agents/policy/guard.mjs` then covers what git hooks cannot see: tool calls that never reach git
(reading a denied path, `git add -A`, invoking `gh pr merge`). One script, three adapters:

```jsonc
// .claude/settings.json
{ "hooks": { "PreToolUse": [ { "matcher": "Bash",
  "hooks": [ { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.agents/policy/guard.mjs" } ] } ] } }
```

```json
// .codex/hooks.json  — same script, same stdin/stdout contract
{ "hooks": { "PreToolUse": [ { "matcher": "Bash",
  "hooks": [ { "type": "command", "command": ".agents/policy/guard.mjs" } ] } ] } }
```

```js
// .opencode/plugin/guard.js — adapter only; all logic stays in guard.mjs
export const Guard = async ({ $ }) => ({
  "tool.execute.before": async (input, output) => {
    const payload = JSON.stringify({ hook_event_name: "PreToolUse", tool_name: input.tool, tool_input: output.args })
    const res = await $`node .agents/policy/guard.mjs`.stdin(payload).json()
    if (res?.hookSpecificOutput?.permissionDecision === "deny") throw new Error(res.hookSpecificOutput.permissionDecisionReason)
  },
})
```

This replaces Phase 4's `enkinex-governance.ts` with something that is the same amount of work and
covers three harnesses instead of one.

### 5.4 Porting `.prompts/` to skills, not to loop-task YAML

Plan §Phase 2 marks `.prompts/*.yaml` for deletion after becoming loop task specs. `.prompts/odcs/
review.yaml` in particular is 248 lines of hard-won, schema-by-schema review rules with recorded
design decisions — the most valuable prompt asset in the repo, and currently the seed for exactly
one opencode agent.

As a `SKILL.md` bundle (`.agents/skills/review-odcs-schema/` with the rule set in `references/`)
it becomes: loadable by all three CLIs, progressively disclosed so it costs ~40 tokens until
needed, and versionable. Recommend porting the durable rule sets to skills and keeping loop-task
YAML for genuinely run-specific parameters only.

§8 proposes the layer above this: authoring those skills as an OKF bundle in KCL rather than as
hand-written `SKILL.md` files, so one source produces both the skills and the human documentation.

---

## 6. Improvements to the plan

### 6.1 Phase 3 (LSP & MCP) — redo, and widen

- Register the KCL LSP. `lsp` is a first-class config key: `{"lsp": {"kcl": {"command":
  ["kcl-language-server"], "extensions": [".k"]}}}`. Put it in the **shared** baseline, not in
  per-repo overlays — three of four repos need identical config, and the overlay indirection buys
  nothing.
- Declare MCP servers in `.mcp.json` **as well as** `opencode.jsonc`, so Claude Code and Codex get
  the same tools. `.mcp.json` is Claude Code's committed project-scope format; opencode has no
  importer, so the two files are maintained by the sync recipe from one source.
- Add the fallback chains that plan §5 already requires but nothing implements, via
  `provider.openrouter.options` → `models` array and `provider.order` / `allow_fallbacks`
  (R8). Frontier agents fall back across `kimi-k3` → `claude-opus-5` → `gpt-5.6`; free-tier
  agents fall back to the next free id, then to mid.

### 6.2 Phase 4 (tools & plugin) — restructure

- Fix the sync directory name first (D1) or nothing in this phase loads.
- Build `kcl-vet` / `kcl-docs` / `project-state` as **one MCP server** (`@enkinex/mcp-kcl`), not as
  `.opencode/tools/*.ts`. Same TypeScript, three harnesses, and it becomes publishable.
- Replace `enkinex-governance.ts` with `.agents/policy/guard.mjs` + three adapters (§5.3).
- Move the "log session cost/model" event hook to `experimental.openTelemetry` (R6).

### 6.3 Phase 5 (loop runner) — resolve the permission model before writing code

The runner's correctness hinges entirely on D2. Specify, before implementation:

- which profile it runs under (headless-deny, per §D2),
- whether it answers permissions via the SDK endpoint or refuses them,
- what `subagent_depth` it needs (default 1 blocks nested delegation — R9),
- what it does on a denied call (`experimental.continue_loop_on_deny`).

Also reconsider `github-pr-cycle.yaml` chaining the five git agents. With §5.3's hooks in place,
most of those agents are wrappers around a `git` command whose rules are now enforced elsewhere.
`git-branch` and `git-commit` in particular reduce to "propose a slug / draft a message" — worth
collapsing to one `ci` skill with the hooks as the guarantee.

### 6.4 Phase 6 (observability & regression) — concrete substitutions

- Ledger: OTel spans → any collector, instead of scraping `opencode stats`. Cross-check against
  OpenRouter's per-key usage so the ledger has an independent source of truth.
- Budget: OpenRouter Guardrails with per-key limits (R7), one key per agent tier. This turns
  "monthly spend caps in the dashboard" from a manual convention into an enforced control, and it
  holds for Claude Code and Codex sessions too.
- Golden set: promptfoo with a pass-rate threshold (R12), fixtures under
  `.agents/evals/`. Three fixtures as planned is thin for gating agent changes; aim for one
  fixture per agent, and make `just eval` the gate on any change under `.agents/` or `opencode/`.
- Secrets: `gitleaks protect --staged` in `pre-commit` beats a plugin scan — it also covers humans.

### 6.5 Benchmark plan

Refresh the prerequisites (`just` is installed; Databricks CLI is not) and correct the `kimi-3` /
`kimi-k3` spelling in §4 and §7 so the scorecard rows key off the real model id. Consider adding a
fourth scoring dimension — **portability** — recording whether each task's artefact ended up in a
neutral format or a harness-specific one; that is the property this whole migration exists to buy,
and nothing currently measures it.

---

## 7. Decisions for the human

These change locked ADRs, so they are proposals, not recommendations to apply.

### 7.1 ADR-0006 — harness-agnostic artefact layer

If §5 is accepted it is a one-way decision and belongs in an ADR: `.agents/` is the neutral home;
`AGENTS.md` is the single instruction file; skills are the portable procedure format; MCP is the
portable tool format; per-harness files may contain pointers only, never rules. This is the ADR
that makes "no vendor lock-in" checkable rather than aspirational — `git grep` for rules outside
`.agents/` becomes the test.

### 7.2 Revisiting the no-Actions rule in ADR-0002

The rule is sound as cost control for *agent runs*. But combined with §5.3 it leaves a gap: local
git hooks are bypassable with `--no-verify`, and there is no server-side check. Two options that
do not reopen the Actions surface meaningfully:

- **GitHub rulesets** (branch protection's successor) can restrict what lands on `main` without
  consuming Actions minutes. Whether they can enforce commit-message and branch-name patterns on
  this plan tier needs checking — `gh api repos/enkinex/<repo>/rulesets` will answer it. Worth
  confirming before assuming.
- **One minimal Actions workflow** running only the deterministic gate (`just check`, `gitleaks`,
  commit-message lint, `promptfoo eval`). No model calls, seconds of runtime, free on public
  repos. This is categorically different from ADR-0002's concern, which was agent runs and MCP
  token economy.

Recommendation: confirm the rulesets capability first; if it covers commit metadata, take it and
leave the no-Actions rule untouched. If it does not, a deterministic-only workflow is a narrower
amendment than it looks.

### 7.3 Should ADR-0002's OpenRouter-only rule extend to Claude Code?

Not addressed by the current ADRs. If Claude Code is to keep being used in these repos, either it
routes through OpenRouter (needs verification that `ANTHROPIC_BASE_URL` can target OpenRouter's
Anthropic-compatible endpoint — untested here) or it is an acknowledged second billing and
governance path outside the Guardrails perimeter. Worth writing down either way, because "no
vendor lock-in" and "one governed gateway" are different goals and this is where they diverge.

---

## 8. OKF as the knowledge substrate — review of `enkinex-okf` and the `enkinex-docs` proposal

### 8.1 What OKF actually is (verified upstream)

The Open Knowledge Format is an open specification published by Google Cloud on 12 June 2026 in
[`GoogleCloudPlatform/knowledge-catalog`](https://github.com/GoogleCloudPlatform/knowledge-catalog)
(Apache-2.0, ~8.3k stars, explicitly "not an official Google product"). Upstream is at **v0.2**;
`enkinex-okf` vendors the spec verbatim at pinned commit `3fcbb9f` — good practice, and it makes
the drift question answerable by diff.

A bundle is a directory of markdown files with YAML frontmatter. The only required key is a
non-empty `type`, deliberately unregistered. Everything else is optional and grouped into families:

| Family | Keys | What it answers |
|---|---|---|
| Identity | `type`, `title`, `description`, `resource`, `tags` | what is this |
| Provenance | `sources[]` (`id`, `resource`, `author`, `usage_count`, `last_modified`), `usage_window` | what was it made from |
| Trust | `generated {by, at}`, `verified[] {by, at}` | who wrote it, who confirmed it |
| Lifecycle | `status` (`draft\|stable\|deprecated`), `stale_after` | is it current, is it still true |
| Computation | `runtime`, `parameters[]`, `computation`, `executor {resource, receipt}`, `attester {resource}` | was this produced the sanctioned way |

Reserved filenames `index.md` (progressive disclosure) and `log.md` (change history). Actors follow
`human:<id>` / `process:<id>` / `<producer>/<version>`, and consumers derive a trust tier
(unverified → machine-confirmed → human-reviewed) from the `human:` prefix. Conformance is
deliberately permissive: consumers MUST NOT reject a bundle for unknown types, unknown keys,
broken links, or missing `index.md`.

**What upstream ships is not what it appears to ship.** `okf/` contains `SPEC.md`, four sample
bundles, and `src/reference_agent/` — a Google ADK agent (`google-adk>=2.0`,
`google-cloud-bigquery`) that *produces* bundles from BigQuery, plus an HTML viewer. There is
**no validator, no linter, and no JSON Schema**. An official CLI/validator and MCP-based bundle
serving are on the stated roadmap, not in the repo. That is precisely the gap `enkinex-okf` fills
today, and it is also the reason to treat the KCL library as a complement with a shelf life on the
validation half — when the official validator lands, enkinex-okf's differentiator narrows to
*authoring* (composition, inheritance, generation), which is the more durable half anyway.

### 8.2 Review of `enkinex-okf` (`v0.2-draft`)

The library is careful, faithful work. Verified: `just test` → **23/23 KCL unit tests pass**, plus
`kcl vet` over 14 positive fixtures, 14 negative fixtures that must be rejected, and a
profile test asserting the permissive schema accepts what the typed schema rejects.

What it gets right, and worth preserving as the house pattern:

- **Two profiles, matching §11 conformance.** `document.Frontmatter` (permissive — `type` only) for
  consuming arbitrary OKF; `Concept` / `AttestedComputationMetadata` (typed) for producing. Most
  schema libraries model one and then fight the spec; this one models the spec's own asymmetry.
- **`[str]: any` on every schema.** Unknown keys survive validation, which is the difference
  between conforming to OKF and merely resembling it.
- **Derivations as pure lambdas, not defaults.** `effectiveStatus`, `isStale`, `deriveTrustTier`,
  `normalizeVerified`, `actorKind` compute read-time semantics without materialising `status:
  stable` into producer output. Materialising it would silently change every document's meaning.
- **`VerifiedType = VerificationEvent | [VerificationEvent]`** implements the "bare mapping is a
  one-element list" MUST directly in the type system.
- The `check` blocks encode the spec's few hard constraints (`type != ""`, date/datetime patterns,
  `usage_count >= 0`, `from <= to`) and nothing more.

Gaps, in the order they block the `enkinex-docs` proposal:

| # | Gap | Consequence |
|---|---|---|
| G1 | **Frontmatter only — no bundle model.** No schema for a bundle tree, `index.md`, `log.md`, or the link graph. | The doc generator has nothing to emit *into*. This is the main v0.3 work item. |
| G2 | **No conformance check over a directory.** `kcl vet` validates one YAML file at a time against a schema; nothing walks a bundle, parses frontmatter out of `.md` files, or reports §11 conformance. | Cannot answer "is `enkinex-docs` a conformant bundle?" |
| G3 | **No renderer.** Nothing turns typed data into `---\n<yaml>\n---\n<body>` files. | See §8.3 — solvable, and smaller than it looks. |
| G4 | **No link validation.** OKF says consumers MUST tolerate broken links, but a *producer* generating its own bundle should not emit them. | Silent rot in generated docs. |
| G5 | **`Concept.type` is `str`, unconstrained.** Correct for the spec; insufficient for a generator, which needs a closed producer vocabulary. | Typos in `type` produce silently-unroutable concepts. |

G5 is a design note rather than a defect: the fix is an enkinex *producer* vocabulary
(`type StatusType`-style union: `Convention | Playbook | Template | Reference | Skill | Attested
Computation | …`) layered above `Concept`, never replacing it. The permissive profile must keep
accepting unknown types.

### 8.3 Is the doc-generation idea feasible? Yes — verified

The proposal is to declare README / CONTRIBUTING / `docs/**` once in KCL, compose per-repo bundles
from shared building blocks, and emit the real files. Two things had to be true. Both were tested
against the installed KCL 0.12.7:

**(a) KCL can compose the content.** A schema `Doc {path, frontmatter, body}` with bodies built by
string interpolation over comprehensions evaluates and emits structured output as expected —
i.e. the "repeat what is common, template what is reusable, customise what is specific" split
is exactly KCL's inheritance + mixin model, which is the same model `enkinex-odcs` already proves
at scale.

**(b) KCL can write the file tree itself.** The `file` module provides `read`, `write`, `mkdir`,
`glob`, `exists`, `modpath`, `workdir`. Verified end-to-end on 0.12.7: a `.k` program created
`out/governance/` and wrote a well-formed frontmatter+body markdown file. **No external emitter is
required** — the generator is pure KCL, invoked by a Justfile recipe.

Two consequences worth designing around:

- **Keep prose in markdown, not in `.k` string literals.** `file.read("partials/commit.md")` loads
  a real markdown file that renders in an editor and diffs cleanly. KCL should own *structure,
  composition and frontmatter*; markdown partials own *prose*. Writing paragraphs inside `"""`
  blocks would be the fastest way to make this unmaintainable.
- **KCL cannot check the bodies.** To KCL a body is an opaque string, so `just check` proves
  nothing about the generated markdown. The gate needs a markdown/link lint step next to
  `kcl lint` — otherwise the generator's output is the one part of enkinex with no test.

The generated-output discipline already exists in this codebase and should be reused verbatim:
`enkinex-okf`'s `just check` runs `just docs` then `git diff --exit-code -- docs/library` and fails
if the committed output is stale. Apply the same rule to every generated doc.

**What not to generate.** `LICENSE` should be excluded — templating legal text carries real risk
and zero maintenance benefit, since licences do not change. `AUTHORS.md` is better derived from git
history than declared. The honest target list is: `README.md` (structure and the repeated sections,
not the narrative), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `.github/` templates,
`docs/schemas/*`, and the governance corpus. That is still the large majority of the duplication
visible across the five libraries today.

### 8.4 Is the skills-generation idea feasible? Yes — but generate at build time, not session start

The projection itself is clean, and cleaner than expected. A `SKILL.md` requires frontmatter `name`
(1–64 chars, lowercase alphanumeric + hyphens) and `description` (1–1024 chars). An OKF concept
requires `type` and permits any additional keys. **A single document can therefore be simultaneously
a conformant OKF concept and a valid `SKILL.md`** — emit `type`, `name`, `description` and the two
standards compose rather than convert. Skill generation becomes a projection with a filter
(`type: Skill`), not a transformation, and conformance to both specs is mechanically checkable.

The delivery half of the proposal needs one correction and carries two implementation traps.

**The correction.** Generating skills at session start and never committing them contradicts
ADR-0005's central argument. ADR-0005 rejected the home-layer design because governance became "an
opt-in ritual" and "invisible to review" — state that is not versioned in the repo it governs
cannot be diffed, reviewed, or regression-tested. Session-start generation reintroduces exactly
that: the effective rule set becomes a function of when you last launched, and a governance change
lands with no reviewable diff. It also breaks §6.4's golden-set regression, which needs a stable
input to diff against.

The synthesis that keeps both goals: **generate at build time, commit the output, gate with
`git diff --exit-code`.** The bundle in `enkinex-docs` is the source; `just sync-opencode` (or a
new `just gen-skills`) is the compiler; the committed `.agents/skills/` tree is the artefact.
Contributors get governance on clone, every change is a reviewable diff, and nothing depends on a
hook having fired on the right machine. This is the same relationship `docs/library/odcs.md` already
has with the KCL docstrings that produce it — a pattern already proven in this codebase.

Reserve runtime materialisation for the case that genuinely needs it: cross-repo distribution where
committing would duplicate. There, opencode has a **native** mechanism — `skills.urls` fetches
skills from a `.well-known/skills/` endpoint, so `enkinex-docs` could serve the bundle and opencode
would need no generation step at all. (A discovery RFC for `.well-known/agent-skills/` exists but is
not yet a ratified standard; opencode's `skills.urls` works today.)

**Trap 1 — Claude Code's skill directory must pre-exist.** The documentation states that skills load
from `.claude/skills/` at startup and that "if you create a top-level skills directory that didn't
exist when the session started, restart Claude Code so it can watch the new directory." A
`SessionStart` hook that *creates* `.claude/skills/` therefore fires too late. If runtime generation
is used anyway, commit a `.claude/skills/.gitkeep` so the directory exists and let the hook only
populate it. Claude Code does watch for changes to an existing directory mid-session.

**Trap 2 — regenerating on every launch is a latency tax.** If a runtime path is kept, gate it on a
content hash of the bundle, or move it to `post-checkout` / `post-merge` git hooks, which fire when
the source actually changes.

### 8.5 The strongest fit: `Attested Computation` is the ADR-0004 contract

This is the finding most likely to be under-valued, because it sits in the part of the spec that
looks like it is only about finance metrics.

OKF §10 specifies a standalone concept type carrying `runtime`, typed `parameters`, a
`computation` the agent **"MUST NOT author or edit"**, an `executor` that runs it and returns a
`receipt` of declared fields, and an `attester` — explicitly **deterministic, no-LLM code** — that
inspects the receipt and returns a verdict, run consumer-side. §10.6 draws the line this document
has been circling since §3: `verified` confirms the *definition* is still policy-compliant (slow,
doc-level, stored); attestation confirms a *single run* did the sanctioned thing (per-call,
runtime, not stored).

Map that onto enkinex governance and the pieces already line up:

| OKF §10 | enkinex equivalent |
|---|---|
| `computation` the agent may parameterise but not rewrite | `just check`, `.githooks/commit-msg`, the commit template |
| `parameters` | the branch slug, the scope, the `Refs:` target |
| `executor` + `receipt` | the hook invocation and its output (exit code, matched pattern, staged paths) |
| `attester` (deterministic, no-LLM, consumer-side) | `.agents/policy/guard.mjs` from §5.3 |
| `verified: {by: human:rodrigo, at: …}` | the human sign-off ADR-0004 leaves implicit |
| `stale_after` | the missing expiry on every governance rule in the repo today |

ADR-0004 asserts that workflows must be executable artefacts and that ADRs record only one-way
decisions. It does not say what the *contract* of an executable artefact is — how it is invoked,
what evidence it returns, or how a consumer decides it actually ran. OKF §10 specifies exactly
that, in a vendor-neutral published format, and the spec even names Skills as a candidate
packaging for `executor.resource` (`references/skills/run-on-bq.md` in the normative example).
Adopting it means enkinex's executable governance gets a standard shape instead of a bespoke one.

The secondary win is smaller but immediate: `AGENTS.shared.md` today is undated, unattributed,
unverified prose. The same rules as OKF concepts carry who wrote them, who confirmed them, when
they expire, and what they derive from — and `deriveTrustTier` / `isStale` are already implemented
and tested in `enkinex-okf`. A governance corpus that can tell an agent "this rule is
`human-reviewed` and fresh" versus "this one is `unverified` and stale since June" is a materially
different artefact from a markdown file.

### 8.6 Risks and honest counter-arguments

| Risk | Assessment |
|---|---|
| **Over-extension.** Six repos, Phase 3 not landed, nothing pushed, no PRs open. Adding a seventh repo plus a generator plus skill projection is a lot of unfinished work in flight. | Real, and the biggest risk here. Mitigation in §9: prove the generator on **one** artefact that aiops needs anyway (the governance skill set), before generalising to README/CONTRIBUTING/docs. |
| **OKF is v0.2 of a young spec, ~7 weeks old.** A major bump can rename required fields. | Contained: the spec is vendored at a pinned commit, the library tracks one version, and OKF's own conformance rules force consumers to be permissive. Low blast radius. |
| **Upstream will ship an official validator and MCP serving.** | Reduces the value of enkinex-okf's validation half. Argues for weighting v0.3 toward *authoring and generation* (G1/G3), where KCL is differentiated, over building a competing validator. |
| **Generation reduces per-repo expressiveness.** Docs that are 90 % generated invite the 10 % that matters to be squeezed into a template. | Design for escape hatches from day one: every generated file needs a hand-owned region or a full-override path. `enkinex-odcs` and `enkinex-databricks` READMEs are not the same document. |
| **Circular dependency.** `enkinex-docs` generates docs for `enkinex-okf`, which is the library `enkinex-docs` imports. | Manageable via bootstrap ordering, but it should be a stated constraint, not a discovery made at build time. |
| **A second source of truth for rules.** §5 makes `AGENTS.md` the single instruction file; §8 makes an OKF bundle the source that generates it. | Not a conflict as long as the direction is one-way and enforced: bundle → generated `AGENTS.md` → committed, with `git diff --exit-code` proving no one hand-edited the output. It becomes a conflict the moment `AGENTS.md` is editable in place. Make it a GENERATED file. |
| **KCL literacy.** Contributors must read KCL to change a commit convention. | Mitigated by keeping prose in markdown partials (§8.3): changing the wording of a rule stays a markdown edit; only structure requires KCL. |

One counter-argument deserves stating plainly: none of §8 is required for §§1–7 to be worth doing.
The harness-agnostic fixes stand alone and are cheaper. OKF is the right *next* layer, not a
prerequisite — and if the choice is between landing Phase 3 properly and starting `enkinex-docs`,
land Phase 3.

### 8.7 Verdict and recommended scope

**Feasible, well-aligned, and worth doing — after the §§1–7 work lands.** The strategic argument is
strong: enkinex already models data contracts (ODCS), data products (ODPS), and platform config
(Databricks). Knowledge is the missing surface, it is the one AI agents consume directly, and OKF
is a published vendor-neutral standard for it with no competing implementation in KCL. "Semantic &
Governance as Code for agentic projects" becomes a claim the repo demonstrates rather than asserts:
the framework governs its own agents with the same libraries it publishes.

Proposed scope, smallest useful increments first:

**`enkinex-okf` v0.3 — bundle model** (closes G1–G4)
- `bundle/` module: `Bundle`, `Directory`, `IndexEntry`, `LogEntry`, concept-ID derivation.
- `render/` module: `Doc {path, frontmatter, body}` → `file.write` emitter with deterministic YAML
  key ordering (byte-stable output is what makes `git diff --exit-code` usable as a gate).
- `conform/` module: walk a bundle, assert §11, report broken links and unknown-but-preserved keys.
- Fixtures: a conformant bundle and a deliberately non-conformant one under `test/`.

**`enkinex-docs` v0.1 — one bundle, one consumer**
- Author the *governance* corpus only: commit convention, branch grammar, PR template, review
  rules, the `.prompts/odcs/review.yaml` rule set. Roughly 10 concepts.
- Producer vocabulary as a KCL union (G5), with `Skill` and `Attested Computation` among the types.
- Emit two artefacts from that one bundle: the `.agents/skills/` tree (§5.2 / §8.4) and the shared
  block of `AGENTS.md` (§5.2). Both committed, both gated by `git diff --exit-code`.
- Acceptance: `just gen` is idempotent; the emitted skills load in all three CLIs; the emitted
  `AGENTS.md` block is byte-identical to what `just sync-opencode` distributes.

**Deferred until v0.1 proves itself**
- README / CONTRIBUTING / `docs/**` generation for the five libraries.
- Serving the bundle over MCP or `.well-known/skills/` for cross-repo distribution.
- `Attested Computation` concepts wrapping `just check` and the git hooks (§8.5) — the highest-value
  item, but it should follow the hooks actually existing (§5.3).

If this is accepted it is a one-way decision about where enkinex's rules live, and belongs in
**ADR-0007 — OKF as the knowledge substrate**, recording: the bundle is the source of truth for
governance prose; generated files are GENERATED and never hand-edited; generation happens at build
time and output is committed; and the producer vocabulary is closed while the consumer profile
stays permissive.

---

## 9. Suggested sequence

1. **Correct the record** — mark Phase 3 not-done in `plan/opencode/loop.md` and `AGENTS.md`.
2. **D1, D3, D4** — one-line fixes to `Justfile` and `opencode.jsonc`, no design debate.
3. **D6 / §5.2** — merge `AGENTS.shared.md` into `AGENTS.md`, add the one-line `CLAUDE.md`.
   Smallest change with the largest governance effect.
4. **§5.3** — `.githooks/` + `.agents/policy/guard.mjs` + three adapters. This retires D5 and most
   of Phase 4's plugin scope.
5. **D2** — settle the headless permission profile before any Phase 5 code.
6. **§6.1** — redo Phase 3 properly, including fallback chains.
7. **ADR-0006** (§7.1), then the Phase 4–7 plan revision.

Then, and only then, the OKF track (§8.7): `enkinex-okf` v0.3 bundle model → `enkinex-docs` v0.1
governance bundle → ADR-0007. Steps 3 and 4 above deliberately hand-write the first `AGENTS.md`
merge and the first skills; `enkinex-docs` later replaces those hand-written artefacts with
generated ones. Writing them by hand first is not wasted work — it is the specification the
generator has to reproduce, and the golden fixture that proves it did.

---

## 10. Sources

opencode: [config](https://opencode.ai/docs/config/) ·
[rules](https://opencode.ai/docs/rules/) ·
[permissions](https://opencode.ai/docs/permissions/) ·
[agents](https://opencode.ai/docs/agents/) ·
[commands](https://opencode.ai/docs/commands/) ·
[custom tools](https://opencode.ai/docs/custom-tools/) ·
[plugins](https://opencode.ai/docs/plugins/) ·
[skills](https://opencode.ai/docs/skills/) ·
[MCP servers](https://opencode.ai/docs/mcp-servers/) ·
[SDK](https://opencode.ai/docs/sdk/) ·
[CLI](https://opencode.ai/docs/cli/) ·
[GitHub agent](https://opencode.ai/docs/github/) ·
[references (v2)](https://opencode.ai/v2/docs/references/) ·
[config schema](https://opencode.ai/config.json)

Claude Code: [memory / AGENTS.md](https://code.claude.com/docs/en/memory) ·
[hooks](https://code.claude.com/docs/en/hooks) ·
[skills](https://code.claude.com/docs/en/skills) ·
[CLI reference](https://code.claude.com/docs/en/cli-reference) ·
[plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)

Codex CLI: [config](https://raw.githubusercontent.com/openai/codex/main/docs/config.md) ·
[hooks guide (secondary)](https://codex.danielvaughan.com/2026/04/15/codex-cli-hooks-complete-guide-events-policy-patterns/) ·
[sandbox & approvals (secondary)](https://anomity.ai/blog/securing-openai-codex-sandbox-and-approvals-guide/)

Standards: [Agent Skills spec](https://github.com/agentskills/agentskills) ·
[AGENTS.md guide](https://www.morphllm.com/agents-md-guide) ·
[multi-harness reference implementation](https://github.com/wshobson/agents)

OpenRouter: [provider routing](https://openrouter.ai/docs/features/provider-routing) ·
[guardrails](https://openrouter.ai/docs/guides/features/guardrails) ·
[BYOK](https://openrouter.ai/docs/use-cases/byok)

Evaluation: [promptfoo in CI](https://medium.com/@alexrodriguesj/testing-llm-prompts-like-code-regression-evals-in-ci-cd-with-promptfoo-5242b4dcb9be) ·
[spec-driven development survey](https://arxiv.org/pdf/2606.04967)

OKF: [knowledge-catalog repo](https://github.com/GoogleCloudPlatform/knowledge-catalog) ·
[OKF v0.2 SPEC.md](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) ·
[Google Cloud announcement](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing) ·
[OKF, RAG, MCP and Agent Skills](https://www.opti-software.com/post/open-knowledge-format-okf-ai-agents/) ·
[KCL `file` module](https://www.kcl-lang.io/docs/reference/model/file) ·
[Cloudflare `.well-known/agent-skills` discovery RFC](https://github.com/cloudflare/agent-skills-discovery-rfc)
