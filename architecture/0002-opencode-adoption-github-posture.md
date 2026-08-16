# ADR 0002 — Adopt opencode + OpenRouter; keep gh-CLI-only GitHub posture

- Status: Accepted
- Date: 2026-08-03
- Deciders: rodrigo@enkinex.com
- Supersedes: ADR-0001 (gh-CLI-only; record removed in the `.project`
  cleanup — its durable content is absorbed into this ADR)
- Superseded by: —

## Context

The enkinex control plane (ADR-0001) was built on Claude Code: five
`.claude/skills/`, a `.claude/settings.json` permission posture, and
`.prompts/*.yaml` task specs, all driven through heavy human
interaction. Two forces require a change:

1. **Vendor lock-in.** Skills, settings, and prompt machinery are
   Claude-Code-only. Model choice is Anthropic-only.
2. **Autonomy ceiling.** The plan → code → review → test loop is
   manual; there is no headless runner, no model routing by task
   complexity, no mechanical governance beyond settings.json.

ADR-0001 decided the GitHub surface (gh-CLI only, no MCP, no Actions)
for Claude Code. That decision must be re-examined for opencode,
whose MCP and permission models differ.

## Decision

1. **Adopt opencode (pinned v1.18.11) as the agent runtime** and
   **OpenRouter as the sole model gateway**, with three tiers
   (free / mid / frontier) pinned per agent. Frontier tier is locked
   to Claude Opus 5, the GPT 5.6 family, and Kimi 3 (default).
2. **Reaffirm gh-CLI for every GitHub mutation.** The five GitHub
   operations (branch, commit, push, PR create/view, squash-merge) are
   ported to opencode agents and remain Bash-driven `gh` calls.
3. **No GitHub MCP server in v0.2.0** — not even read-only. ADR-0001's
   token-economy rationale is unchanged: an MCP server's tool catalog
   is ambient per-session cost, and every read we need is a bounded
   `gh pr view --json ... --jq ...` call. Revisit per concrete unmet
   need, per service, never as a blanket reversal.
4. **No GitHub Actions, no Issues, no Projects, no Releases.** The
   no-Actions corollary stands as a hard cost-control rule. CI/CD runs
   locally: the opencode loop runner (`just loop`) *is* the pipeline,
   executing `loop/tasks/github-pr-cycle.yaml` (see ADR-0004).
5. **Permission posture ports to `opencode.jsonc`** with the same
   allow/ask/deny semantics; `gh issue|project|workflow|run|release`
   stays denied.

## Rationale

- **Lock-in reversal without surface change.** opencode reads the same
  Markdown-skill format, supports per-agent models and permissions,
  and speaks to any OpenRouter model. The five workflow skills port
  verbatim; only frontmatter changes.
- **ADR-0001's core arguments survive the migration.** Token economy,
  surface match, deny-by-default, replay/isolation, reversibility —
  all five apply identically to opencode's MCP model. Nothing about
  opencode weakens them.
- **Cost governance is architectural, not aspirational.** OpenRouter
  spend caps + per-agent tier pins + `opencode stats`/session-export
  ledger give the cost control that Actions-for-CI would destroy.
- **Reversibility.** Adding an MCP server later is a config block, not
  a rewrite — same as ADR-0001's reversibility argument.

## Consequences

### Positive

- Model choice per task complexity; frontier spend confined to plan /
  review / ADR work.
- Every enkinex convention survives as a portable artefact
  (agents/commands/permissions), not a vendor feature.
- `opencode run` + `opencode serve` + `@opencode-ai/sdk` unlock the
  headless loop.

### Negative

- Two config layers to keep coherent (shared baseline + per-repo
  overlays) — mitigated by ADR-0005's sync/verify recipes.
- `opencode pr`/`opencode github` built-ins exist but are deliberately
  unused; agents must route GitHub through `gh` — enforced by
  permission rules and the governance plugin.

### Locked corollaries

- GitHub MCP may be introduced only via a new ADR naming the concrete
  read (never mutation) it enables that `gh --json/--jq` cannot.
- CI-triggered headless loop runs (e.g. from a self-hosted runner)
  require their own ADR; v0.2.0 runs loops locally via `just loop`.
- `opencode stats` / session exports are the cost-ledger source for
  Phase 6; no third-party observability stack in v0.2.0.

## References

- ADR-0001 (gh-CLI-only verdict; reaffirmed here, record removed).
- Discovery: `enkinex-pm/plan/enkinex-aiops/refactor/migration.md` §3
  (capability validation) and §6.1 (private).
- Plan: `enkinex-pm/plan/enkinex-aiops/refactor/loop.md` Phases 0–7, and
  `enkinex-pm/plan/enkinex-aiops/refactor/benchmark-enkinex-databricks.md`
  (private).

**Those three are a historical record, not current planning.** They were
written for the 2026-08 migration, relocated to the private planning
repository on 2026-08-13, and are held there as legacy — to be replanned or
deleted rather than kept current. Their phase and task numbering describes
work that has been superseded, so it should not be read as work in flight or
cited as a commitment. This ADR carries its own context accordingly: nothing
above depends on reading them, and the decision stands on the Context and
Decision recorded here.

They are named without a leading `../` deliberately: the path would promise a
link that resolves only for someone holding the private clone, and the name
alone identifies the document without making that promise
(`enkinex-pm/plan/README.md`, the redaction convention).
