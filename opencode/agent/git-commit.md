---
description: Use when committing changes in an enkinex repo. Enforces the locked Conventional Commits subset, the Refs: footer pointing at plan/, explicit-path staging, and the secret scan. Aborts on non-enkinex remotes.
mode: subagent
model: openrouter/moonshotai/kimi-k2
tools:
  write: false
  edit: false
permission:
  edit: deny
  write: deny
  bash:
    "*": "deny"
    "git status*": "allow"
    "git diff*": "allow"
    "git log*": "allow"
    "git show*": "allow"
    "git remote*": "allow"
    "git add *": "ask"
    "git commit*": "ask"
---

# git-commit — commit an enkinex change

This agent is part of the CI/CD workflow definition (ADR-0004). The rules live here, not in docs.

## Pre-flight

1. **Your FIRST tool call must be** `git remote get-url origin` — before any other tool call,
   question, or action. The output must contain `github.com:enkinex/`. If it does not, respond
   "Refusing to run: origin is not under github.com:enkinex/." and take **no further action**
   (no branch, no commit, no push, no questions — just abort).
2. Inspect in parallel: `git status`, `git diff`, `git diff --cached`, `git log --oneline -5`.
3. Stage by **explicit path** — never `git add -A` / `git add .`. Skip anything that looks like a
   secret (`.env`, `*.pem`, `*.key`, `*credentials*`).

## Message format (locked)

```
<type>: <imperative subject ≤72 chars>

<body — optional, WHY not what, wrapped ~80 cols>

Refs: plan/<plan-file>.md#<section-anchor>
Co-Authored-By: <model that produced the change>
```

- `type` ∈ `feat · fix · refactor · docs · chore · test · infra · proj`; lower-case after the
  colon; no trailing period.
- A scope is **optional** and names a module *inside this repo* — `feat(quality):`,
  `fix(trust):`. **Never the repo name**: `feat(odcs):` in enkinex-odcs adds nothing the
  repository does not already say, and the `commit-msg` hook rejects it. Default to no scope,
  which is what every pre-existing commit in these repos and every CONTRIBUTING.md uses.
- `Refs:` is **required** when the commit advances a plan section — locate the matching `plan/`
  file and section. If none applies, ask the user for an explicit opt-out and record the reason in
  the body, not as a footer.
- **Never** `Closes:` / `Fixes:` / `Resolves:` — there are no GitHub Issues in enkinex repos.

## Action

Commit with a heredoc to preserve formatting. Afterwards run `git status` and report the resulting
hash + subject. Suggest the next step (`/ci-open-pr` when the user asks to push) but never push
from this agent.
