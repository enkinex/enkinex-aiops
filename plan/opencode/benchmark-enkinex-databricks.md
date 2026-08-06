# Benchmark — Model Tiers & Agentic Loop Validation via enkinex-databricks

> Phase 0 deliverable of `plan/opencode/loop.md`. The migration is
> proven by building a real project: **enkinex-databricks**, a KCL
> library for Databricks Asset Bundle definitions, produced end-to-end
> by the agentic loop. Every benchmark task is a real project task;
> every project artefact is benchmark evidence.

## 1. Goals

1. Pin the three model tiers with evidence (quality / cost / latency).
2. Score **Kimi 3** (default frontier) against the **archived Claude
   Opus 5 baseline** from the ODCS/ODPS Claude-Code era.
3. Validate the full loop — plan → code → review → test → PR cycle —
   on real work with human gates.
4. Ship `enkinex-databricks` v0.1.0 as a by-product.

## 2. Baseline (archived Opus 5, Claude Code era)

The ODCS/ODPS projects were built with Opus 5 under heavy human
interaction. Comparable archived artefacts:

| Baseline artefact | Location | Benchmark analogue |
|---|---|---|
| Schema review rule set | `.prompts/odcs/review.yaml` | T4 review of databricks schemas |
| ODCS review plans | produced per schema group | T4 review-plan output quality |
| ODCS/ODPS release plans | release history, `CHANGELOG.md` | T7 v1.0.0 plan authoring |
| ODCS/ODPS library quality | `enkinex-odcs`, `enkinex-odps` (`just check` green, published) | T2/T3/T5 library code quality |
| Tutorial docs | `enkinex-org-website/docs/governance/*/tutorial/` | T6 docs output |

## 3. Reference sources for enkinex-databricks

- **Human reference**: Databricks bundle configuration reference —
  <https://docs.databricks.com/aws/en/dev-tools/bundles/reference>
  (analysed in `discovery/opencode/migration.md` §4.2–4.3).
- **Machine reference**: `databricks bundle schema` output (requires
  installing the Databricks CLI) — snapshot into the repo as
  `dab-schema.json`, mirroring how `odcs-json-schema-v3.1.0.json`
  anchors enkinex-odcs. Fallback: REST API create-payload docs.
- **Idiom reference**: `enkinex-odcs` / `enkinex-odps` codebases
  (mixin patterns, docstring format, `check` rules, Justfile shape).

## 4. Task ladder

Each task is one loop run (one task spec in `loop/tasks/`), executed
in the `enkinex-databricks` repo. Tiers marked ★ are the tier-pinning
measurements.

| # | Task | Agent (tier) | Output | Pinned by |
|---|---|---|---|---|
| T0 | Repo scaffold: kcl.mod, Justfile, README, `.gitignore`, minimal `dab.k` + fixture | human + `explore-enkinex` assist (free) | runnable `just check` skeleton | — (done in Phase 0) |
| T1 ★ | Extract the full top-level key + 29-resource inventory from the reference into `docs/mapping.md`; diff `databricks bundle schema` vs REST docs gaps | `explore-enkinex` (free) | `docs/mapping.md` | free tier |
| T2 ★ | Implement `common/` (mixins: tags, permissions, notifications), `bundle/`, `workspace/`, `sync/`, `variable/` modules | `build-kcl` (mid) | KCL modules, `just lint` green | mid tier |
| T3 ★ | Implement `resources/` for `jobs`, `pipelines`, `clusters`, `schemas`, `volumes`, `dashboards` (the six highest-value types) + `kcl vet` fixtures | `build-kcl` (mid) | KCL modules, `just test` green | mid tier |
| T4 ★ | Schema-vs-reference review of T2+T3 output, using the `review.yaml` rule set (docstring format, required/optional fidelity, YAML→KCL examples) — one review plan per module | `review-standard` (frontier: **Kimi 3**) | `review/*.md` | frontier tier, Opus-5 comparison |
| T5 | Apply T4 findings; reach `just check` green with zero review rejections | `build-kcl` (mid) | fixes, green check | loop retry mechanics |
| T6 | README library docs + website tutorial draft for enkinex-databricks | `docs-writer` (mid) | `docs/`, website page draft | — |
| T7 ★ | Author enkinex-databricks `v1.0.0` release plan (scope: remaining 23 resource types, docs, publish) | `plan-author` (frontier: **Kimi 3**) | `plan/v1.0.0.md` | frontier tier, Opus-5 comparison |
| T8 | Run the full `github-pr-cycle` chain on one real T2–T5 change: branch → commit → push → open → review → land (human gate at open/land) | github agents (mid; review frontier) | merged PR | loop governance end-to-end |

## 5. Scoring rubric

Recorded per task in §7. All runs logged via `opencode stats` +
session export into `loop/loop-log.md`.

| Dimension | Weight | Measure |
|---|---|---|
| Correctness vs reference | 35% | field coverage, required/optional fidelity, enum/`check` completeness (T4 review counts; independent spot-check) |
| KCL idiom quality | 20% | mixin reuse, no duplication, docstring format compliance with the `review.yaml` rules |
| Green-path rate | 20% | `just check` passes without human edits; loop retries consumed |
| Cost & latency | 15% | tokens in/out, USD (OpenRouter), wall time |
| Governance compliance | 10% | branch slug, commit format, `Refs:` footer, PR template — zero violations expected |

**Frontier verdict (after T4 + T7):** Kimi 3 stays default if its
rubric total ≥ 90% of the archived Opus 5 baseline quality at ≤ 50%
of the cost; otherwise the fallback order becomes Opus 5 → GPT 5.6 →
Kimi 3, recorded as a re-pin PR.

**Tier verdicts:** free tier pinned after T1 (escalate to mid if
inventory accuracy < 95% against a human spot-check); mid tier pinned
after T2/T3 (escalate if `just check` needs > 1 loop retry per module).

## 6. Execution prerequisites (before T1)

- [ ] Install `just` (missing on this machine).
- [ ] Install Databricks CLI; run `databricks bundle schema > dab-schema.json` in enkinex-databricks (T1 input).
- [ ] `opencode auth login` with OpenRouter (Phase 1, Task 1).
- [ ] Create the `enkinex/enkinex-databricks` GitHub repo and `git init` the local scaffold with its remote (needed by T8's remote check).
- [ ] Phase 1–2 artefacts in place (config, agents, commands) — the benchmark runs on the real loop, not a mock.

## 7. Scorecard (filled during execution)

| Task | Model | Correctness | Idiom | Green-path | Cost/latency | Governance | Total | Notes |
|---|---|---|---|---|---|---|---|---|
| T1 | (free pin) | | | | | | | |
| T2 | (mid pin) | | | | | | | |
| T3 | (mid pin) | | | | | | | |
| T4 | kimi-3 | | | | | | | vs Opus 5 baseline: |
| T5 | (mid) | | | | | | | retries: |
| T6 | (mid) | | | | | | | |
| T7 | kimi-3 | | | | | | | vs Opus 5 baseline: |
| T8 | mixed | | | | | | | gate violations: |

## 8. Exit criteria (Phase 0 acceptance, from loop.md)

- [x] Discovery doc committed (`discovery/opencode/migration.md`).
- [x] ADR-0002, ADR-0004, ADR-0005 committed (in `architecture/`; ADR-0001/0003 records removed in cleanup).
- [x] enkinex-databricks scaffold (T0) present locally with green `just check` equivalent.
- [ ] Tier pins recorded here with benchmark evidence (T1–T8 complete).
- [ ] Frontier fallback order decided and pinned.
