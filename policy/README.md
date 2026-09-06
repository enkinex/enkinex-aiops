# enkinex policy guard

GENERATED into each repo as `.agents/policy/`. Source of truth:
enkinex-aiops `policy/`. Change it there and run `just sync-opencode`.

One policy, three harnesses. `guard.mjs` reads a PreToolUse-shaped JSON
payload on stdin and writes a decision on stdout carrying **both** response
shapes — `hookSpecificOutput.permissionDecision` for Claude Code and
`decision`/`reason` for Codex — so a single file serves both. The opencode
adapter is a plugin that calls the same script and rethrows a deny.

| Harness | Adapter | Contains |
|---|---|---|
| Claude Code | `.claude/settings.json` | a `PreToolUse` hook pointing at `guard.mjs` |
| Codex | `.codex/hooks.json` | the same hook, same contract |
| opencode | `.opencode/plugin/enkinex-guard.js` | `tool.execute.before` → `guard.mjs` |

Every adapter is a pointer. No rule lives in any of them, so adding a fourth
harness is one file and no policy duplication.

## What belongs here, and what does not

The guard covers only what `.githooks/` structurally cannot see:

- **Hook bypasses** — `--no-verify`, `core.hooksPath` edits, deleting
  `.githooks/`. A git hook cannot defend itself; without this rule every
  git-level guarantee is one flag deep.
- **Commands that never reach git** — `gh pr merge`, `gh pr create`.
- **Command shape rather than result** — `git add -A` is invisible to
  `pre-commit`, which only sees the index that resulted.
- **Credential-path reads** — opencode denies these in config; Claude Code
  and Codex do not.

Anything enforceable at the git layer belongs in `.githooks/` instead: it
binds humans as well as agents, and it cannot be sidestepped by switching
harness.

## Enabling it

- **opencode** — automatic; the plugin loads from `.opencode/plugin/`.
- **Claude Code** — automatic once the workspace trust dialog is accepted.
- **Codex** — hooks are opt-in. Add to `~/.codex/config.toml`:

  ```toml
  [features]
  codex_hooks = true
  ```

  Project-level `hooks.json` also requires the project to be trusted. This is
  a user-level setting by design: enkinex tooling never writes to `$HOME`
  (ADR-0005).

## Failure behaviour

Three cases allow the call and a fourth blocks it, so they are worth keeping
apart. The allow cases are deliberate: a policy engine that breaks the
session when it has a bad day gets removed.

- **Malformed payload — allows.** `guard.mjs` parses stdin inside a `try` and
  exits 0 with no output when the parse throws. That is the guard's own
  behaviour, so it holds in every harness.
- **Missing guard — allows.** The opencode plugin's `existsSync` check
  returns early when `.agents/policy/guard.mjs` is absent; an ungoverned repo
  is not a broken one.
- **Unparseable response — allows.** The plugin returns without a decision
  when `JSON.parse` throws on the guard's stdout.
- **Guard present but unrunnable — blocks.** A spawn error, a non-zero exit
  or the 10-second timeout throws, and opencode aborts the tool call. The
  file is there, so enforcement is expected: an unrunnable guard is a broken
  policy path rather than an absent one, and allowing here would make every
  rule advisory again.

The last three are the opencode plugin's behaviour. Claude Code and Codex
carry no adapter code — their hook entry runs `guard.mjs` directly, so what a
missing, crashing or unparseable hook means there is the harness's decision
rather than this policy's.
