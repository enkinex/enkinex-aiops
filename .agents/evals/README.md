# Agent-output evals

The golden set in `tests/` is deterministic and covers the **artefacts** — the
hooks, the config, the policy guard, agent frontmatter, the MCP server. It
covers nothing an agent actually produces. A model re-pin, a rewritten agent
instruction or a provider-side change can degrade every output in the org and
`just test` stays green, because it never asks a model anything
([AIOPS-13](../../../enkinex-pm/plan/enkinex-aiops/13-agent-output-evals.md)).

`just eval` is that missing half. It is **not** part of `just check`, and that
is deliberate: the gate stays free, fast and hermetic, and a gate that costs
money per run is one people learn to skip.

## The three decisions, and why

AIOPS-13 refused to start until these were settled, on the grounds that they
are the user's to make and an implementer picking them silently is how a suite
ends up measuring something nobody chose. Decided 2026-09-06.

**Each agent is evaluated on the model it pins.** Mid agents on
`moonshotai/kimi-k2`, frontier agents on `moonshotai/kimi-k3`, read from each
agent's own frontmatter rather than configured here. It is the only option
whose result describes the org as actually configured, and on the current split
it is cheaper than putting everything on the frontier model. A re-pin changes
what the suite measures, which is correct — that is the degradation it exists
to catch. The alternatives were frontier-for-everything, which measures the
ceiling rather than the configuration, and free-tier, which measures a tier
[AIOPS-12](../../../enkinex-pm/plan/done/enkinex-aiops/12-free-tier-viability.md)
deliberately does not run.

**A run reports its cost, and aborts above USD 0.50.** Roughly double the
present estimate, so the suite can grow by half again before anyone has to
think about it — and when it crosses, that is a decision worth making rather
than a bill worth discovering. The ceiling is a running total, checked between
calls, so an abort still reports what it managed. `just eval` is exactly the
kind of recipe that gets wired into an unattended loop later, and unbounded
spend there is the failure the ledger's spend-limit warning already exists for.

**Three samples per case; two must pass.** The same prompt does not give the
same output twice, so correctness is a rate. Majority-of-three catches gross
degradation — a re-pin that breaks a capability shows up as 0/3 or 1/3 — while
tolerating the one odd sample any nonzero temperature produces. Requiring 3/3
costs the same and fails on ordinary variance, and a suite that cries wolf is
one people stop reading. Five samples buys more confidence at 1.7x the spend
and can be revisited when the case count justifies it.

## Shape

| Path | What it is |
|---|---|
| `cases.json` | The cases. Each names an agent, an input, and deterministic checks |
| `run.mjs` | The runner. Reads agent frontmatter for the pin, calls OpenRouter directly |
| `README.md` | This file |

A real directory rather than a symlink to a root `evals/`, unlike
`.agents/policy` and `.agents/mcp`: nothing distributes this, so there is no
source-and-copy split to keep honest.

**The runner calls OpenRouter directly** rather than driving opencode. That is
a deliberate approximation and worth knowing when reading a result: it sends
the agent's own instruction file as the system prompt and its own pinned model,
so it measures the instruction and the model, not opencode's tool loop.
Driving opencode would be more faithful and is not currently possible to do
unattended — [AIOPS-14](../../../enkinex-pm/plan/enkinex-aiops/14-openrouter-model-fallback.md)
records two attempts to observe opencode's own requests that captured nothing.

## Scoring

Deterministic and unattended. A check is a regex the output must match, or must
not match; a case passes when every check holds. Nothing here asks a model to
score another model, and nothing waits for a person — an eval that needs a
human to read it will not be read.

**A pin that no longer resolves is a failure, loudly.** Before any case runs,
every pinned model is looked up in OpenRouter's catalog; if one is gone the run
stops and says so, rather than quietly evaluating whatever the provider
substitutes and reporting a rate for a model nobody chose.
