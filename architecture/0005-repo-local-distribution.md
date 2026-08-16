# ADR 0005 — Repo-local distribution: governance travels with the repo, never touches $HOME

- Status: Accepted
- Date: 2026-08-03
- Deciders: rodrigo@enkinex.com
- Supersedes: ADR-0003 (two-layer distribution: global home layer + per-repo overlay)
- Superseded by: —

## Context

ADR-0003 distributed the shared opencode layer by syncing it from
enkinex-aiops into each developer's **global** opencode config
(`~/.config/opencode/`), with thin per-repo overlays. Reviewing the
landed Phase 1 implementation exposed a fundamental flaw in that
shape:

1. **Contributor sovereignty.** The global config is the developer's
   personal layer — their model defaults, their other projects, their
   own agents. Overwriting it assumes every contributor wants enkinex
   governance bleeding into *everything* else they work on.
2. **Governance by opt-in ritual.** The permission posture and shared
   instructions only exist on a machine after someone manually runs
   the sync. A fresh clone has no governance until then.
3. **Invisible to review.** Home-dir state is not versioned in the
   repo it governs; drift between contributors is undetectable by the
   repo itself.

Empirical check (opencode 1.18.11, `--print-logs`): config loads in
order `~/.config/opencode/` → repo-root `opencode.jsonc` →
`.opencode/opencode.jsonc`, later files winning. Repo-root `AGENTS.md`
auto-loads; extra instruction files come from the `instructions`
config list. Project-local config is therefore a complete carrier for
everything ADR-0003 put in the home layer.

## Decision

**All enkinex governance is repo-local.** The developer's
`~/.config/opencode/` is never written by enkinex tooling (the Phase 1
installation there has been reverted to a pristine stub).

1. **Source of truth** stays in enkinex-aiops `opencode/`:
   `opencode.jsonc` (baseline config), `shared/AGENTS.md` (shared
   instructions), and `agent/ command/ tool/ plugin/` (executable
   artefacts as they land).
2. **Sync targets are the sibling repos**, via `just sync-opencode`
   (checksum-verified by `just verify-opencode`):
   - `opencode/opencode.jsonc` → `<repo>/opencode.jsonc` (GENERATED
     header: do not edit in target).
   - `opencode/shared/AGENTS.md` → `<repo>/.opencode/shared/AGENTS.md`
     (wired in via the baseline config's `instructions` list).
   - `opencode/<dir>/` → `<repo>/.opencode/<dir>/`.
3. **Synced files are committed in the target repo** through its
   normal branch/PR workflow. Distribution to contributors happens
   through `git clone`, not through home-dir mutation.
4. **Repo overlays stay hand-owned**: `<repo>/.opencode/opencode.jsonc`
   (loaded last, wins) carries repo-specific deltas — LSP servers,
   model overrides; repo-root `AGENTS.md` carries repo-specific
   instructions.
5. enkinex-aiops dogfoods: it receives its own generated files like
   every other repo.

## Rationale

- **Governance on clone.** Permission posture, shared instructions,
  and agents are active the moment a contributor clones — no ritual,
  no opt-in.
- **Reviewable and versioned.** Every governance change is a diff in a
  repo, reviewed per ADR-0004's executable-governance rules, and
  covered by golden-set regression.
- **Zero collateral damage.** A contributor's other projects and
  personal opencode setup are untouched; enkinex rules apply only
  inside enkinex repos.
- **Drift still detectable.** The verify recipe checksums source vs
  installed copies across all repos — the property ADR-0003 wanted
  from the home-layer design, now achieved inside version control.

## Consequences

### Positive

- Fresh clones are fully governed; onboarding is `git clone` + work.
- Contributors keep ownership of their global config.
- The generated/owned split (root `opencode.jsonc` vs
  `.opencode/opencode.jsonc`) makes it mechanically obvious what may
  be edited where.

### Negative

- The same files are duplicated across N repos (accepted: they are
  generated artefacts with a single source and a drift checker —
  duplication with verification, not divergence).
- Adding a repo means appending it to the `REPOS` list in the aiops
  Justfile and one synced-files PR in the new repo.

## References

- ADR-0003 (superseded; record removed in the `.project` cleanup —
  this ADR carries the full context), ADR-0004 (executable governance
  boundary).
- Empirical config-loading check: opencode 1.18.11 `--print-logs`,
  2026-08-03 (load order and override semantics).
- Plan: `enkinex-pm/plan/enkinex-aiops/refactor/loop.md` §4 (distribution
  model) and its Phase 1 status (private). A historical record held as
  legacy, not current planning — see ADR-0002's References for what that
  means and why it is named rather than linked.
