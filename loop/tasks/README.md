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
