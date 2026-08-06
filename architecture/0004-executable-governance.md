# ADR 0004 — Executable governance: workflows are code, ADRs record only one-way decisions

- Status: Accepted
- Date: 2026-08-03
- Deciders: rodrigo@enkinex.com
- Supersedes: —
- Superseded by: —

## Context

In the Claude Code era, enkinex governance lived in documents:
`.project/conventions/git.md` and `pr.md` defined the branch/commit/
PR/merge rules in prose, `.claude/skills/` *pointed at* those docs,
and ADRs (ADR-0001) recorded decisions. Enforcement was partly
mechanical (settings.json) but the **definition** of the workflow was
prose — a document cannot execute, and prose rules drift from what
agents actually do.

opencode collapses the describe/execute gap: agents, commands, loop
task specs, and plugin hooks are simultaneously human-readable
definitions **and** the machinery that executes and enforces them.

## Decision

1. **Workflows are defined once, as executable artefacts.** The entire
   CI/CD workflow (branch → commit → PR → review → land) and every
   other procedural convention live in `.opencode/agent/*.md`,
   `.opencode/command/*.md` (the `/ci-*` chain),
   `loop/tasks/*.yaml` (notably `github-pr-cycle.yaml`), and
   `enkinex-governance` plugin hooks. These artefacts are the single
   source of truth.
2. **ADRs record only one-way decisions and their rationale** — the
   kind that cannot be expressed as code (vendor/posture choices,
   distribution shape, tier policy, this boundary). An ADR is one
   page: context, decision, rationale, consequences, references. It
   links to executable artefacts; it never re-specifies their
   behaviour.
3. **Convention docs become derivative.** Human-readable summaries of
   the rules live in each repo's CONTRIBUTING guide and the shared
   `AGENTS.shared.md`; they describe what the executable artefacts
   enforce and link to them. A workflow change lands as a PR against
   the artefact first; docs follow in the same PR.
4. **This ADR is self-limiting.** ADR-0004 is the last ADR that
   describes a process. Future ADRs require the human gate and must
   argue why the decision cannot be an executable artefact.

## Rationale

- **Drift elimination.** When the definition is the thing that runs,
  "docs say X, agent does Y" becomes impossible by construction.
- **Testability.** Executable artefacts are covered by the golden-set
  regression (Phase 6): a workflow change that alters behaviour fails
  a diff. Prose changes fail nothing.
- **Reviewability.** A workflow change becomes a normal code PR with
  diff, review agent, and `just check` — strictly more rigorous than
  editing Markdown rules.
- **ADRs stay scarce and meaningful.** Their value is durable *why*,
  which is exactly what code cannot carry.

## Consequences

### Positive

- One source of truth per workflow; docs, ADRs, and behaviour cannot
  silently diverge.
- Workflow evolution gains the full engineering apparatus: branches,
  review, regression fixtures, loop-log audit.
- ADR reading time stays near zero; governance onboarding is "read the
  agents directory".

### Negative

- Executable artefacts are less approachable to non-technical readers
  than prose — mitigated by keeping the derivative convention docs
  current in the same PR (a check the review agent performs).
- Plugin hooks encode rules in TypeScript; contributors need minimal
  TS literacy (mitigated: hooks are small, and `kcl-vet`-style tools
  are the extension pattern).

## References

- Discovery: `discovery/opencode/migration.md` (§6.3).
- Plan: `plan/opencode/loop.md` (§3.1 Executable governance, §8
  boundaries 6–7).
- ADR-0002 (the first ADR written under this boundary).
