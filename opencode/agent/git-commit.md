---
description: Use when committing changes in an enkinex repo. Enforces the locked Conventional Commits subset, the Refs: footer naming the task delivered, explicit-path staging, and the secret scan. Aborts on non-enkinex remotes.
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

Refs: <TASK-ID>
Co-Authored-By: <model that produced the change>
```

- `type` ∈ `feat · fix · refactor · docs · chore · test · infra · proj`; lower-case after the
  colon; no trailing period.
- A scope is **optional** and names a module *inside this repo* — `feat(quality):`,
  `fix(trust):`. **Never the repo name**: `feat(odcs):` in enkinex-odcs adds nothing the
  repository does not already say, and the `commit-msg` hook rejects it. Default to no scope,
  which is what every pre-existing commit in these repos and every CONTRIBUTING.md uses.
- `Refs:` is **required** when the commit advances a task, and its value is the stable **task ID**
  — `AIOPS-08`, `MGR-16`, `PM-04` — a project prefix plus a file number. It resolves to
  `../enkinex-pm/plan/<repo>/<NN>-<slug>.md`; locate that file to confirm the ID before using it.
  Never write the path itself: the ID survives a rename or re-numbering, and a sibling-relative
  path encodes one machine's checkout layout into permanent history.
- **Planning is centralised and private.** This repo having no local `plan/` is correct, not
  misconfigured — do not create one, and do not read a `Refs:` target from the repo you are
  committing in. If the `enkinex-pm` clone is not beside this one, ask rather than guessing an ID.
- When the commit advances no task, use `No-Plan-Ref: <reason>` in place of `Refs:`. The
  `commit-msg` hook accepts it and it is the **correct footer, not a bypass** — repo hygiene,
  tooling and dependency bumps legitimately advance no plan. Do not invent a task ID to satisfy
  the hook, and do not bury the reason in the body where the footer belongs.
- **Never** `Closes:` / `Fixes:` / `Resolves:` — there are no GitHub Issues in enkinex repos.

## Action

Commit with a heredoc to preserve formatting. Afterwards run `git status` and report the resulting
hash + subject. Suggest the next step (`/ci-open-pr` when the user asks to push) but never push
from this agent.
