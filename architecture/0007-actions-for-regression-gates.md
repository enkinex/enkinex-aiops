# ADR 0007 — GitHub Actions are open for the regression gate; Projects and Releases stay closed

- Status: Accepted
- Date: 2026-09-05
- Deciders: rodrigo@enkinex.com
- Supersedes: ADR-0002 Decision 4 and ADR-0006 Decision 4,
  **for Actions only**
- Superseded by: —

## Context

ADR-0002 §4 forbids Actions, Issues, Projects and Releases in one sentence
and calls the no-Actions corollary *"a hard cost-control rule"*. ADR-0006 §4
reopened Issues on 2026-08-16 and restated the other three *"so nobody
reopens them by analogy"*.

**The rule was already false when it was restated.**
`.github/workflows/test.yml` has run on every push and pull request to `main`
in this repository since 5711137, 2026-08-05 — eleven days before ADR-0006
was written, and committed to the same repository ADR-0006 lives in. Seven
sibling repositories carry the same workflow at the same path:
`enkinex-databricks`, `enkinex-odcs`, `enkinex-odcs-tutorial`,
`enkinex-odps`, `enkinex-odps-tutorial`, `enkinex-okf` and `enkinex-ossie`.
Nine files in all, one per repository, each triggered on push and pull
request to `main` plus `workflow_dispatch`. `enkinex-org-website` and
`enkinex-knowledge-base` have none — each `.github/` holds only `CODEOWNERS`
— and the org profile repository is not cloned here, so it was not checked.

**This is not drift; it is investment.** AIOPS-17, delivered, deliberately
widened what three of those workflows run — `just test` to `just check`, so
`kcl fmt` and `kcl lint` are gated rather than `kcl vet` alone — because
AIOPS-16 had found 53 unformatted files in `enkinex-odcs`, 14 in
`enkinex-odps` and 1 in `enkinex-databricks` that no CI run had ever
reported. The org did not fall into Actions by accident. It spent a task
making them certify more.

**The counter-argument, stated because the ban was not irrational.** Actions
consume billable compute, and ADR-0002's cost governance is real: OpenRouter
caps, per-agent tier pins, a session-export ledger. A pipeline that bills per
minute on somebody else's trigger is exactly the cost that is easy to start
and hard to see. What changed is not the argument but its scope. A regression
gate on a public repository is the one case where the compute is worth it: it
is the only check that runs on a contributor's pull request before anyone
with a local clone looks at it, and no local `just check` can be that.
ADR-0006 §4's ground for the ban — *"the local loop runner is the pipeline"*
— was true of the loop and never true of the gate. `just loop` runs on one
operator's machine, on work already in hand.

## Decision

1. **Actions are open for one purpose: a regression gate.** One workflow per
   repository, `.github/workflows/test.yml`, triggered on push and pull
   request to `main` plus `workflow_dispatch` for a manual re-run, running
   that repository's `just check`. enkinex-aiops is the exception and runs
   `just test`: `check` also runs `verify-opencode`, which reads the sibling
   clones from `../` and cannot resolve them in a single-repo checkout.

2. **Every other use of Actions stays closed.** No deploys, no publishing, no
   scheduled runs, and no agent or loop run on a runner — ADR-0002's locked
   corollary requiring a separate ADR for CI-triggered headless loops is
   untouched. A second workflow file in any repository is a decision, not a
   chore.

3. **Projects and Releases stay closed, and the cost argument still binds for
   them.** Neither buys what the gate buys. Projects would be a third view of
   work that `enkinex-pm/plan/backlog.md` (private) already orders and issues
   already publish — ADR-0006 accepted the second reluctantly, and a third
   gates nothing. Releases publishes nothing that needs publishing: a consumer
   takes a KCL library by git tag from the repository itself, the way
   `enkinex-odcs-tutorial/kcl.mod` names `tag = "v3.1.0"` against
   `enkinex-odcs`. **Actions are not a precedent for them.** Reopening either
   requires its own ADR naming the concrete need, exactly as ADR-0002 §3
   requires for GitHub MCP.

4. **The permission table does not change.** `gh workflow*` and `gh run*` stay
   `deny` in `opencode.jsonc`. Workflows are edited as files under normal
   review, and a gate result reaches an agent through `gh pr checks`, which is
   already `allow`. Opening the surface is not a reason to let an agent
   dispatch or cancel runs.

## Rationale

- **A gate is not a pipeline.** ADR-0002 wrote the corollary against CI/CD —
  build, deploy, publish — and the loop runner does replace that. A test run
  on a pull request is a narrower thing, and it is the only part of the ban
  anyone needed to break.
- **The record is corrected rather than left contradicted.** A rule that every
  workflow file in the org disproves teaches contributors to discount the
  rules that still hold. ADR-0006 §4 restated this one without checking the
  repository it was being committed to; that is the failure worth naming.
- **The shape is the bound.** Nine files, one trigger shape, one command
  each. Cost stays legible because anything growing past that shape shows up
  as a diff in `.github/workflows/`.

## Consequences

### Positive

- The nine workflows already on `main` are governed rather than
  undocumented, and AIOPS-17's widening has a decision behind it.
- A contributor's first pull request is checked by something that does not
  depend on the maintainer having a clone open.

### Negative

- **Billable compute now has a standing authorisation and nothing meters it.**
  The bound in Decision 1 is a review discipline, not a mechanism; no recipe
  or hook fails when a second workflow appears.
- **The gate is not uniform.** `enkinex-org-website` has none, and it is the
  repository with the most to gate — a Docusaurus build deployed through
  Wrangler. `enkinex-odcs-tutorial`, `enkinex-odps-tutorial` and
  `enkinex-ossie` still name the step *"Run tests"* while running
  `just check`, so the legibility AIOPS-17 bought in the three repositories
  it touched stops there.
- **`verify-opencode` is gated on no runner.** It is the drift check across
  all repos, and Decision 1's aiops exception means it runs only locally.

## References

- ADR-0002 (Decision 4, superseded here for Actions only; Decision 3's GitHub
  MCP denial and the CI-triggered-loop corollary are untouched).
- ADR-0006 (Decision 4, superseded here for Actions only; Issues as decided
  there, and the Projects/Releases denial, are unchanged).
- ADR-0004 (executable governance): the workflow files are the artefact; this
  ADR records only why the surface is open.
- `.github/workflows/test.yml` in this repository and in the seven siblings
  named in Context; commit 5711137 (2026-08-05) added the first.
- Plan: `enkinex-pm/plan/done/enkinex-aiops/17-ci-runs-the-full-gate.md`
  (private).
