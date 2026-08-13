---
description: Use when starting work on a new task in an enkinex repo. Syncs with origin/main and creates a branch with the locked enkinex slug grammar. Aborts on non-enkinex remotes.
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
    "git branch*": "allow"
    "git remote*": "allow"
    "git fetch*": "allow"
    "git checkout -b *": "ask"
    "git switch -c *": "ask"
---

# git-branch — start an enkinex task

This agent is part of the CI/CD workflow definition (ADR-0004). The rules live here, not in docs.

## Pre-flight

1. **Your FIRST tool call must be** `git remote get-url origin` — before any other tool call,
   question, or action. The output must contain `github.com:enkinex/`. If it does not, respond
   with the abort message below and take **no further action** (no branch, no commit, no push,
   no questions — just abort):
   "Refusing to run: origin is not under github.com:enkinex/."
2. `git fetch origin` then `git status -sb` — the local `main` must be in sync with
   `origin/main`. If behind, stop and tell the user to sync first. Never branch from a stale main.

## Slug grammar (locked)

```
<type>/<short-slug>
```

- `type` ∈ `feat · fix · refactor · docs · chore · test · infra · proj` (`proj` reserved for
  planning and `architecture/` edits).
- **`proj` is decided by what the branch changes, not by what the change is about.** Planning is
  centralised in `enkinex-pm`, so a plan for this repo's code is written in *that* checkout: the
  `proj` branch belongs there, beside the plan file it edits. A branch here that delivers a plan
  is typed by what it touches here — `feat`, `refactor`, `docs` — and names the task in its
  `Refs:` footer. The two are separate branches in separate repositories, which is the intended
  consequence of centralising planning, not an accident to work around.
- `short-slug` — kebab-case, ≤6 words, imperative; describes the change, not the repository.
  Examples: `feat/output-port-retry-policy`, `chore/contributor-tooling`.
- **Do not prefix the slug with the repo name.** The branch already lives in the repo; `odcs-` in
  `enkinex-odcs` is noise.

Ask the user for type/summary if not given; propose one from the task description.

## Action

```bash
git checkout -b <slug>
```

Report the branch name and remind: work locally, commit at the end of the iteration, **never push
or open a PR unless the user explicitly asks**.
