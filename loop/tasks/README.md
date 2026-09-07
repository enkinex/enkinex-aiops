# Loop task specs

One YAML file per task, run with `just loop <name>`.

```yaml
task: One line describing the outcome.       # required
repo: ../enkinex-odcs                        # required, relative to enkinex-aiops
gate: just check                             # optional, default `just check`
retries: 1                                   # optional, default 1 repair attempt
steps:                                       # required, ordered, at least one
  - agent: explore-enkinex                   # must be mode: all (see below)
    prompt: |
      ...
  - agent: build-kcl
    prompt: |
      ...
```

Each step is a separate `opencode run`, so each gets a fresh context — which
is what makes a review step worth running at all. After the last step the gate
runs; if it fails, the last step's agent gets one repair attempt with the gate
output, then the loop stops.

## Coverage

One spec per repository in `REPOS`, across both gate types. The runner is what
this control plane exists to operate, and until 2026-09-06 it was exercised
against two repositories out of seven (AIOPS-21).

| Repo | Spec | Gate |
|---|---|---|
| `enkinex-odcs` | `odcs-check-rule-audit.yaml` | `just check` |
| `enkinex-odps` | `odps-check-rule-audit.yaml` | `just check` |
| `enkinex-okf` | `okf-bundle-inventory.yaml` | `just check` |
| `enkinex-ossie` | `ossie-schema-coverage.yaml` | `just check` |
| `enkinex-databricks` | `databricks-bundle-coverage.yaml` | `just check` |
| `enkinex-org-website` | `org-website-tutorial-drift.yaml` | `npm run typecheck` |
| `enkinex-pm` | **none, deliberately** | — |

`enkinex-pm` has no spec and needs none: it holds no library code to audit, its
own gate is a shell regression suite over the governance scripts, and the
material a loop agent would read there is the private planning surface. A spec
that pointed an agent at it would be inventing loop work for a repository
nobody loops.

`enkinex-databricks` is included on its own merits. It was excluded as "the
benchmark vehicle", a framing the org retired on 2026-09-05, and an exclusion
whose only reason has been withdrawn is not an exclusion.

**A repair step will change the repository to make a red gate green.** That is
what "one repair" means, and it is worth knowing before pointing the loop at a
repo whose gate is red for environmental reasons. The first run of
`org-website-tutorial-drift` found `tsc` missing — `node_modules` is gitignored
and the checkout had none — correctly diagnosed it, and then rewrote that
repository's `typecheck` script to work around it. The edit was reverted and
the prerequisite is now stated in the spec. **Check the gate passes by hand
before the first run of a new spec**; the loop is not the place to discover
that a repo needs `npm ci`.

**Writing a spec costs nothing; only running one does.** The recorded range is
$0.0050 to $0.1215 per run, so the set is complete on disk and run selectively
— `just loop <task>` takes one at a time on purpose.

## Agents must be `mode: all`

`opencode run --agent <name>` **silently falls back to the default agent** when
the target is `mode: subagent` — the run then uses the wrong model under the
wrong permissions and still reports success. The runner detects the fallback
warning and aborts, but the fix is in the agent definition: the five loop
agents (`explore-enkinex`, `build-kcl`, `docs-writer`, `review-standard`,
`plan-author`) are `mode: all`. The five github workflow agents stay
`mode: subagent` because they are driven interactively through `/ci-*`.

## What the loop will not do

It never commits, pushes, opens a PR or merges. That is not politeness in the
prompt: runs execute under `opencode.headless.json`, where `git push`,
`git rebase`, `gh pr create` and `gh pr merge` are **denied**. The loop leaves
a dirty working tree for you to review and commit.
