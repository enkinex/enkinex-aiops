# Discovery — opencode Migration & Agent Loop Validation via enkinex-databricks

- Status: Complete (Phase 0 of `plan/opencode/loop.md`)
- Date: 2026-08-03
- Feeds: ADR-0002, ADR-0004, ADR-0005, `plan/opencode/benchmark-enkinex-databricks.md`

## 1. Purpose

Validate everything `plan/opencode/loop.md` assumes, and fix the
benchmark vehicle: the migration is proven by **building a real fifth
enkinex project — `enkinex-databricks`, a KCL library for Databricks
Asset Bundle definitions** — through the agentic loop itself, with
model tiers benchmarked on that real work.

## 2. Artefact inventory (migrated surface)

| Source (Claude Code era) | Destination (opencode) | Notes |
|---|---|---|
| `CLAUDE.md` | `AGENTS.md` + `instructions` globs | opencode reads `AGENTS.md` natively |
| `.claude/skills/` × 5 (branch/commit/open-pr/review-pr/land-pr) | `.opencode/agent/*.md` + `/ci-*` command chain | bodies port verbatim; frontmatter gains `mode`, `model`, `permission` |
| `.claude/settings.json` allow/ask/deny | `permission` rules in `opencode.jsonc` | same allow/ask/deny semantics, glob patterns |
| `.prompts/*.yaml` (odcs × 11, website × 4, plan, factored) | `loop/tasks/*.yaml` + `.opencode/command/*.md` | YAML specs become loop-runner inputs |
| `.project/` lifecycle | dissolved | root-level `plan/`, `discovery/`, `architecture/` (cleanup 2026-08-03) |
| — (new) | `.opencode/tool/*.ts`, `.opencode/plugin/*.ts` | `@opencode-ai/plugin` already vendored in `~/.config/opencode` |

## 3. opencode capability validation (this machine, 2026-08-03)

Verified against the installed binary:

| Capability required by loop.md | Status | Evidence |
|---|---|---|
| opencode installed, pinned version | ✅ v1.18.11 | `opencode --version` |
| Headless single-shot runs | ✅ | `opencode run [message..]` with `--agent`, `--model`, `--file`, `--format json`, `--attach` |
| Headless server for SDK loop runner | ✅ | `opencode serve` (+ `opencode web`, `opencode attach`) |
| Provider/auth management | ✅ | `opencode providers` (alias `auth`); `opencode models [provider]` to list OpenRouter catalog |
| Agent management | ✅ | `opencode agent` subcommand; `.opencode/agent/*.md` project agents; `~/.config/opencode/agent/` global agents |
| Plugin install path | ✅ | `opencode plugin <module>`; `@opencode-ai/plugin@1.18.11` present in global config |
| MCP management | ✅ | `opencode mcp` subcommand |
| Cost/token ledger | ✅ | `opencode stats` (usage + cost), `opencode export` (session JSON) — feeds the Phase 6 ledger |
| PR helpers | ✅ | `opencode pr <number>` exists but is **not used** (ADR-0002 keeps gh-CLI) |
| KCL language server | ✅ | `kcl-language-server` on PATH next to `kcl` 0.12.7 |

Gaps / prerequisites discovered:

- **`just` is NOT on PATH** — required by every sibling Justfile and by
  the loop recipes (`just loop`, `just sync-opencode`). Install before
  Phase 1.
- **`databricks` CLI is NOT installed** — optional but strongly
  recommended for the benchmark: `databricks bundle schema` emits the
  full JSON schema of every bundle resource (the machine-readable
  source the KCL library maps from, analogous to
  `odcs-json-schema-v3.1.0.json`).
- **No OpenRouter credentials** — `~/.config/opencode/auth.json` is
  empty; `opencode auth login` (or `OPENROUTER_API_KEY`) is Phase 1
  Task 1.
- Global `opencode.jsonc` is an empty `$schema`-only stub — clean
  slate for the shared baseline.

## 4. Benchmark vehicle — enkinex-databricks

### 4.1 Why this project

- **Identical shape to ODCS/ODPS**: map a vendor's YAML/JSON-schema
  configuration surface to a modular KCL schema library with
  docstrings, mixins, `check` rules, `kcl vet` fixtures, and generated
  docs. The Claude-Code-era ODCS/ODPS artefacts (review plans, release
  plans, docs) are the **archived Opus 5 baseline** the frontier-tier
  benchmark scores against.
- **Real deliverable value**: it extends the enkinex
  Governance-as-Code family from standards (ODCS/ODPS) to platform
  deployment (Databricks bundles).
- **Full loop coverage**: scaffolding, exploration, KCL schema work,
  schema-vs-reference review, docs, release planning, and the PR cycle
  — every agent and every tier gets exercised.

### 4.2 Reference surface (from the official configuration reference)

Source: <https://docs.databricks.com/aws/en/dev-tools/bundles/reference>
("Declarative Automation Bundles", formerly Databricks Asset Bundles).

Top-level mappings to model as KCL modules:

| Top-level key | Type | KCL module (proposed) |
|---|---|---|
| `bundle` | Map | `bundle/` — name, `databricks_cli_version` (semver constraints), `engine` (terraform/direct), `deployment` (+ lock), `git`, `cluster_id` (dev-only override) |
| `workspace` | Map | `workspace/` — host, paths (`root_path`, `artifact_path`, `file_path`, `state_path`), profile/auth |
| `artifacts` | Map | `artifact/` — build commands, `type` (whl/jar), `dynamic_version`, `files[].source` |
| `resources` | Map | `resources/` — one subpackage per resource type (§4.3) |
| `targets` | Map | `target/` — `mode` (development/production), `default`, per-target overrides of bundle/workspace/resources/variables/presets/permissions/sync/run_as |
| `variables` | Map | `variable/` — custom variables (default, description, type) |
| `presets` | Map | `preset/` — name_prefix, jobs_max_concurrent_runs, trigger_pause_status, tags, pipelines_development, source_linked_deployment |
| `permissions` | Seq | `permission/` — level + user/group/service_principal (top-level levels: CAN_VIEW, CAN_MANAGE, CAN_RUN) |
| `run_as` | Map | `permission/` (reused identity schema) |
| `sync` | Map | `sync/` — include/exclude globs (gitignore syntax), `paths` |
| `include` | Seq | root `dab.k` (file-inclusion globs) |
| `scripts` | Map | root `dab.k` (named `content` commands) |
| `python` | Map | `python/` — mutators, resources loaders, venv_path |
| `experimental` | Map | `experimental/` — feature flags; keep isolated so flags can churn without touching stable modules |
| `deployment modes` | enum | `target/` — development vs production semantics + presets interaction |

### 4.3 Resource types (29, per the reference)

`alerts`, `apps`, `catalogs`, `clusters`, `dashboards`,
`database_catalogs`, `database_instances`, `experiments`,
`external_locations`, `genie_spaces`, `jobs`,
`model_serving_endpoints`, `models` (legacy), `pipelines`,
`postgres_branches`, `postgres_catalogs`, `postgres_databases`,
`postgres_endpoints`, `postgres_projects`, `postgres_roles`,
`postgres_synced_tables`, `quality_monitors`, `registered_models`,
`schemas`, `secret_scopes`, `sql_warehouses`,
`synced_database_tables`, `vector_search_endpoints`,
`vector_search_indexes`, `volumes`.

Key mapping fact: each resource body is the **create-operation request
payload of the Databricks REST API**, expressed in YAML. Two
machine-readable sources exist:

1. `databricks bundle schema` — full JSON schema of every supported
   object (preferred; snapshot it into the repo like
   `odcs-json-schema-v3.1.0.json`).
2. The REST API reference — per-resource field docs for docstrings.

### 4.4 Design decisions carried over from ODCS/ODPS

- One KCL module per top-level concern; root `dab.k` composes them
  into the `Bundle` schema (mirrors `odcs.k`/`odps.k`).
- Mixins for repeated shapes (tags, permissions, notification
  settings) in a `common/` module.
- `check` rules for enums (`engine`, `mode`, permission levels,
  pause status) and semver-constraint strings.
- `kcl vet` fixtures in `test/*.yaml` validating real bundle examples
  against the schemas.
- `just docs` generated library reference.
- Version pinning: the library targets a **Databricks CLI version
  range** recorded via `bundle.databricks_cli_version` — the reference
  doc annotates fields with "Added in Databricks CLI version X", which
  the docstrings should preserve.

## 5. Open questions (resolved in benchmark, not here)

1. Does the free tier survive KCL exploration tasks, or does T1
   escalate to mid? (benchmark T1 decides)
2. Is Kimi 3 ≥ archived Opus 5 on schema-vs-standard review?
   (benchmark T4 decides → frontier fallback order)
3. Does `databricks bundle schema` output suffice as the single
   machine-readable source, or do we diff against the REST API docs?
   (benchmark T1/T2 decides)

## 6. Decisions locked here (carried to ADRs)

1. **GitHub surface** — gh-CLI for all mutations; no GitHub MCP in
   v0.2.0 (ADR-0001's token-economy rationale still holds under
   opencode); no GitHub Actions; the local loop runner *is* the CI/CD
   engine. → ADR-0002.
2. **Distribution** — flat siblings; aiops authors the shared layer,
   syncs to `~/.config/opencode/`; per-repo overlays; pseudo-multirepo
   nesting abandoned. → ADR-0003. **Superseded same-day by ADR-0005:**
   the home layer violated contributor sovereignty; distribution is
   repo-local (synced files committed in each sibling repo).
3. **Executable governance** — workflows defined once as agents /
   commands / loop tasks / plugin hooks; ADRs only for one-way
   decisions; convention docs derivative. → ADR-0004.
4. **Benchmark** — enkinex-databricks is the validation vehicle;
   scoring rubric and task ladder in
   `plan/opencode/benchmark-enkinex-databricks.md`.
