# Harness Hardening & Dogfooding — successor plan to `loop.md`

> Everything `plan/opencode/loop.md` left open, plus the governance work that
> must precede it and the two dogfooding milestones that follow. Four phases,
> run in order, each on its own branch. Phase 1 contains one-way steps.
> Phase 3 creates a new repository; Phase 4 was deferred out of v0.2.0
> deliberately.

## 1. Status entering the plan

`loop.md` v0.2.0 is complete except its Phase 7 dogfooding (see that plan's
Phase 7 status). The harness is live in six repos and covered by 204
deterministic cases. Six adoption PRs are open and awaiting human review.

What is unfinished falls into four groups, separated here because they have
different risk and different prerequisites: the org and its refs are not yet
protected to the standard the work assumes, fixing the harness is cheap and
blocking, OKF dogfooding creates a new repository, and Databricks dogfooding
is a large code-generation exercise that should not share a branch with
either.

**Branching model — decided, keep trunk-based.** Short-lived
`<type>/<short-slug>` branches off `main`, squash-merged through a reviewed
PR, releases cut as tags. A long-lived `dev`/`develop` branch was considered
and rejected: it adds a name rather than a gate (an agent that can write to
`main` can write to `dev` identically), it enlarges and delays the human
review that generated code most needs, and it doubles the long-lived-branch
count across a six-repo shared layer that is already synced by drift check.
What the model actually lacks is enforcement on the refs themselves, which is
Phase 1. Maintenance branches (`release/<major>-<minor>`, cut from a tag on
demand) are the topology addition these libraries will eventually need — not
before a published major requires a backport, and the `pre-push` slug grammar
must gain a `release` type on the day it happens.

## 2. Phase 1 — Project Governance & Branch Protection

Goal: every enkinex repository is public, owned by exactly one team, and
protected by the same mechanically-applied template — before the dogfooding
phases put generated code within reach of a public `main`.

Branch: `infra/org-governance-and-protection`.

Runs first for two reasons. It is the only phase whose absence makes the
others unsafe. And it contains the plan's only genuinely one-way steps: a
repository's history cannot be un-published, and a deleted repository cannot
be recovered.

### 1.1 Measured starting state (2026-08-05)

Org `enkinex` — GitHub **Free**, 2 seats, `rodrigoalvamat` owner,
`xaviervini` member, `default_repository_permission: none` (correct, keep).

| Org setting | Now | Target | Why |
|---|---|---|---|
| `members_can_delete_repositories` | `true` | **`false`** | The explicit requirement. Today a member with repo-admin could delete a repo |
| `members_can_change_repo_visibility` | `true` | `false` | A member could re-privatise a published library, or publish an unscanned one |
| `members_can_create_repositories` | `true` (`all`) | `false` | With four teams, repo creation is an owner action; it is also what assigns a repo to a team |
| `members_can_create_teams` | `true` | `false` | The team map is the access model; it should not be editable from below |
| `members_can_invite_outside_collaborators` | `true` | `false` | Outside contributors arrive by fork + PR, which the `pre-push` remote guard already handles |
| `two_factor_requirement_enabled` | `false` | `true` | A public org with a second member and publish rights. The largest account-level gap on the list |
| `secret_scanning_enabled_for_new_repositories` | `false` | `true` | Free for public repos; see 1.8 |
| `secret_scanning_push_protection_enabled_for_new_repositories` | `false` | `true` | Free for public repos; see 1.8 |
| `dependabot_alerts_enabled_for_new_repositories` | `false` | `true` | Free; the website is the npm surface that needs it |

The end state is the **thirteen** product repositories of §1.2 plus
**`.github`**, the org-profile repo. Eight are public today, two more flip
during this phase (`enkinex-aiops`, `enkinex-org-website`), one is created
(`enkinex-knowledge-base`), and three tutorials are deferred past this plan —
so this phase closes with **twelve protected repositories** and the target of
fourteen is reached later. `enkinex-agents`, `enkinex-articles` and
`enkinex-bitol-common` stay private and **owner-only**: legacy, no team
grant, retired or migrated on their own schedule. `enkinex-architecture` no
longer exists in the org.

A read-only auditor in `enkinex-lab` (`governance/audit-governance.sh`)
snapshots all of this on demand and writes `reports/latest.{md,json}`; the
JSON is the baseline the applier of 1.5 is generated from. Everything below
was measured by it. The state below is the *starting* state; §1.10 records
what has since been applied.

| Repo | Today | Action |
|---|---|---|
| enkinex-odcs, enkinex-odps, enkinex-okf, enkinex-ossie | public, protected: push restricted to `rodrigoalvamat`, 1 review, code-owner review, force-push and deletion off, conversation resolution on. **No status check, no linear history, `enforce_admins: false`** | close the gaps (1.5, 1.6) |
| enkinex-databricks, enkinex-odcs-tutorial, enkinex-odps-tutorial, .github | public, **protected 2026-08-05** | done |
| enkinex-aiops | private | clean root commit → scan → flip → protect, **last** (1.3) |
| enkinex-org-website | private, held deliberately | flips at the end of the phase, after a Cloudflare credential review (1.3) |
| enkinex-knowledge-base | does not exist | create public → protect (1.3) |
| enkinex-okf-tutorial, enkinex-ossie-tutorial, enkinex-databricks-tutorial | do not exist | **deferred past this plan** — created after the dogfooding phases (1.2) |
| enkinex-lab | private | the research repo of §1.9; outside the fourteen |
| enkinex-agents, enkinex-articles, enkinex-bitol-common | private | **legacy, owner-only access.** No team grant, no dev access |

Three findings set the priority.

**Four public repos have no protection at all** — `enkinex-databricks`,
`enkinex-odcs-tutorial`, `enkinex-odps-tutorial`, `.github`. Anyone with
write can push to `main`, force-push it, or delete it. This is a live gap,
not a future one, and it is the first thing 1.5 closes.

**Two access grants contradict the model.** `xaviervini` holds **direct
`admin`** on `enkinex-bitol-common` and on `enkinex-odps-tutorial`. Admin is
the one role that can delete a repository and edit branch protection, so
those two grants defeat both guarantees this phase is built on — and
`enkinex-bitol-common` is one of the repos designated owner-only. Separately,
the `libdev` team holds `write` on **`enkinex-lab`**, the private research
repo, which was not intended. Access is corrected as part of 1.2, not left
to the org-level flags in 1.4.

**`enkinex-aiops`** — the repo that generates the hooks and the policy guard
for every sibling — remains the least protected in the fleet, with bypassable
local hooks as its only control.

**`.github` goes to WebDev.** It is public, unprotected, and not legacy — it
renders the org profile, which is the public face WebDev already owns. It is
not a product repo and carries no version line, so it takes the protection
template and the team assignment but no release or tag rules.

`CODEOWNERS` in the protected repos is `* @rodrigoalvamat @xaviervini`, so
either maintainer can satisfy the code-owner review while merge stays
restricted to the owner. That is the shape the rest of this phase
generalises.

### 1.2 The team map

Four teams, each owning a coherent surface. The correlation the project is
built on — Terraform/OpenTofu is to IaC what enkinex is to Semantic &
Governance as Code — puts the boundary in the same place those projects do:
the standard libraries (providers) are one surface, the corpus they are
documented and reasoned about in is another, the public face is a third, and
the machinery that builds and distributes all of it is a fourth.

| Team | Repos | Action |
|---|---|---|
| **LibDev** | enkinex-odcs · enkinex-odcs-tutorial · enkinex-odps · enkinex-odps-tutorial · enkinex-okf · enkinex-ossie · enkinex-databricks | all seven public; protect the three that are not |
| **KbDev** | enkinex-knowledge-base | created and protected in 1.3; modelled and filled in Phase 3 |
| **WebDev** | enkinex-org-website, .github | protect `.github` now; website flips last (1.3) |
| **PlatformDev** | enkinex-aiops, future platform repos | clean root, then flip |

`enkinex-okf-tutorial`, `enkinex-ossie-tutorial` and
`enkinex-databricks-tutorial` join LibDev when they are created, **after** the
governance and dogfooding phases — deferred deliberately, not forgotten. The
pairing convention below governs them on arrival.

**Team name: `PlatformDev`, not `CoreDev`.** In the Terraform/OpenTofu
correlation the project is built on, "core" names the engine and the
libraries are the providers — but enkinex has no engine of its own to name:
that role is played by KCL. What `enkinex-aiops` and a future registry
backend actually are is the enabling surface the other three teams build on,
which is what "platform" means in ordinary usage. `CoreDev` would also be the
only one of the four names that asserts *importance* rather than *surface*,
and it would imply the standard libraries — the actual product — are
peripheral. Every other name here answers "which surface do you own"; this
one should too.

**The library/tutorial pairing is a convention, not a coincidence.** Every
library repo has exactly one `enkinex-<library>-tutorial` sibling, and the
pair is one governance unit: same team, same protection template, same
review bar. A tutorial is the first thing a newcomer executes, so a broken
one costs more than a broken internal document — it needs CI that runs
against the library version it pins (1.6), not just a link check. How tightly
the versions track is a decision in 1.9.

Reconcile the stray `docs/odps-tutorial-1.0.0` branch on the
`enkinex-org-website` remote against `enkinex-odps-tutorial` before the
tutorials are cut, so tutorial content has exactly one home.

**Role: each team gets `write`, never `Maintain` or `Admin`** — applied
2026-08-05. Admin is the only role that can delete a repository, change
branch protection, or manage rulesets, verified against GitHub's role matrix.
`Maintain` was the earlier recommendation here, and the rules of 2026-08-05
overruled it: "cannot configure repos" excludes `Maintain`, which can edit
repository settings. `write` gives branches, PRs, review and approval — the
whole contributor surface — and nothing else.

The deletion guarantee therefore rests on two independent conditions, and
needs both: `xaviervini` stays an org **member** (owners always hold admin on
every repo), and `members_can_delete_repositories` is **false**.

**Naming recommendation — `enkinex-knowledge-base`, team `KbDev`.** The
website already owns human-facing documentation, so `enkinex-docs` would
collide with `enkinex-org-website` in exactly the place a newcomer looks
first. The repo is an OKF bundle, and OKF is literally the Open *Knowledge*
Format — the domain word is the standard's own. And by §3.3 the repo is a
queryable corpus that *compiles* into artefacts (`.agents/skills/`, the
shared `AGENTS.md` block); "docs" describes one of its outputs, "knowledge
base" describes what it is. Final call stays with the Phase 3 detailed plan,
but this phase needs a team name and takes `KbDev` on that basis.

### 1.3 Going public — the irreversible step

Two different operations, with two different risks.

**Two flips remain** — `enkinex-aiops` and `enkinex-org-website`. History
cannot be un-published, and both predate the `pre-commit` credential scan,
which only ever saw *staged* content going forward. Before either flip: scan
the **full history, all branches, all tags** (`gitleaks detect
--no-git=false`, or equivalent), then review `.env*`, key material, `kcl.mod`
registry credentials, internal hostnames and customer names by hand. A hit
means the repo does not flip until the history is rewritten or the repo is
recreated — deliberately the only place in this plan where a rewrite is on
the table, and it happens *before* publication, never after.

`enkinex-org-website` flips **last, after `enkinex-aiops`**, and its scan has
a specific target the others do not: Cloudflare and Wrangler credentials,
account and zone identifiers, and any deploy token in history or in
`wrangler.toml`. The audit reports its Actions secrets, environments and
deploy keys, which is the other half of the same question.

**Two flips already happened** — `enkinex-databricks` (judged to expose
nothing the published libraries do not) and `enkinex-odps-tutorial`
(unintentionally private until now). Neither was preceded by a documented
history scan. Publication cannot be undone, so run the scan on both
**retrospectively**: the point is no longer prevention but knowing, and a
credential that is already public needs rotating rather than removing.

`enkinex-aiops` is the highest-risk flip by a wide margin and goes **last,
after 1.4–1.8 are applied and verified** — not merely planned. The reason is
this document. It enumerates which repos are unprotected, that local hooks
are bypassable, that this repo is the least-protected in the fleet, and that
a spend warning currently reports the opposite of the truth. Published before
the fixes, that is a map of the holes; published after, the same words are
evidence of rigour. Nothing about the text changes — only when it ships.

Note what publication does *not* disclose. The harness is already public:
`guard.mjs`, the three hooks, the ten agents, the `/ci-*` commands and the
plugin are readable today on `feat/adopt-opencode-layer` in three public
repos. And the harness was never a security boundary — it is client-side,
bypassable by design, and inert until `core.hooksPath` is set. The boundary
is 1.5 and 1.8, which publication does not touch.

The flip is done with the closest reading of the content. A full-history scan on 2026-08-05 found **no
credentials** — every hit was a `githooks/pre-commit` pattern or a
`tests/hooks.test.sh` fixture. What it found instead was *context*:

- Committed agent-memory files, in history only — infrastructure detail for
  a private system that was never meant to leave it.
- `.prompts/`, in the working tree — task specs describing the internals of
  a private repository, and references to documents that exist nowhere
  public.

  *(Both are described by class rather than content: a scan report that
  restates what it found republishes it, which would defeat the clean root
  commit this section prescribes.)*
- Vendored copies of `enkinex-odps/`, `enkinex-okf/` and `enkinex-website/`
  from when they sat inside this repo. Not sensitive, just bloat.
- `loop/loop-log.md`, tracked — the OpenRouter spend ledger. Publishing burn
  is a legitimate choice; it should be a made one (§1.9).

The disposition is therefore a **clean root commit, not a filter**: the
material is spread across enough of the history that removing it selectively
costs more than the forty commits are worth. Boundary 1 already permits this,
and only before publication.

Mechanics, because the obvious method is blocked by design: `pre-push`
refuses non-fast-forward pushes and direct pushes to `main`, and `guard.mjs`
denies rewrites — so this is done by **deleting and recreating the remote**,
never by `--no-verify`. The repo is private with no forks, so nothing
external breaks. The cost is the `Refs:` chain across forty commits; the
decisions themselves survive as files in `AGENTS.md`, `plan/` and
`architecture/`.

`.prompts/` does not come across. It is a porting source with a scheduled
removal (Phase 2 §2.6) and, more immediately, an index of work lost to a
disk failure — so it is archived outside git and read, not parked in a repo.
Not `enkinex-architecture`: that repo is legacy and slated for retirement,
which is the wrong home for the only surviving copy of something.

**One creation** — `enkinex-knowledge-base`. Empty history, so there is
nothing to scan; the risk is the unprotected window between `gh repo create
--public` and the template landing. Create it **after** 1.4 and 1.5 are in
place, so `just protect` is a single command that follows creation
immediately. Repo creation is an owner action by then (1.4), which is also
what guarantees a new repo is assigned to a team at birth. The three deferred
tutorials are created the same way, later.

**A published-docs dependency, now resolved.** `enkinex-org-website` carries
16 deep links into `enkinex-odps-tutorial` (`blob/main/team/member.k`,
`product.yaml`, `Justfile`, …) and 19 into `enkinex-odcs-tutorial`. While
`enkinex-odps-tutorial` was private, every one of those published links was a
404 for readers. All 16 target paths were verified present on `main` on
2026-08-05, and every enkinex repository linked from the website is now
public — so the flip closed this with nothing further to fix. Worth keeping
as a standing check: **a tutorial repo's visibility is a website
dependency**, and the website has no test that would have caught it.

Order of operations per repo, in one sitting: (scan →) flip or create →
apply protection (1.5) → verify. A public unprotected repo is exactly the
window `enkinex-odcs-tutorial` is sitting in now; it should not be opened
eight more times — four flips and four creations.

### 1.4 Org settings

Apply the 1.1 target column. Available on Free, and none of it requires an
Actions workflow (ADR-0002 stands) — but **three of them are not writable
through the API**, established by running it on 2026-08-05:
`members_can_delete_repositories`, `members_can_change_repo_visibility` and
`members_can_invite_outside_collaborators`. `PATCH /orgs/enkinex` accepts all
three, returns `200`, and ignores them; they are web-UI settings under
Member privileges. The applier re-reads every field after writing and reports
the ones that did not stick, because a `200` that changes nothing reports
success while leaving the gap open. The remaining seven apply normally and
have been applied.

That matters more than it sounds: `members_can_delete_repositories` is the
deletion guarantee itself, so **the phase's headline control is a manual
step**, not something the applier can hold in place. `verify-protection`
should therefore treat it as drift to be reported, never as drift to be
fixed.

2FA enforcement is last, because enabling it removes any member who has not
already enrolled — confirm with the contributor first.

### 1.5 The branch-protection template

One template, applied identically to all fourteen repos. Taken from the
proven `enkinex-odcs` shape, with the gaps closed:

| Setting | Value | Note |
|---|---|---|
| `restrictions.users` | `[rodrigoalvamat]` | The requirement: merging a PR is a push, so this makes the owner the only one who can land on `main` |
| `required_approving_review_count` | `1` | |
| `require_code_owner_reviews` | `true` | With `* @rodrigoalvamat @xaviervini`, either maintainer's approval counts |
| `dismiss_stale_reviews` | `true` | already set |
| `require_last_push_approval` | `true` | **change** — new commits after an approval need re-approval. Directly aimed at agent-authored follow-up commits |
| `required_status_checks` | `strict`, contexts per 1.6 | **change** — see 1.6 |
| `required_linear_history` | `true` | **change** — squash-merge is already the only merge path; this makes it mechanical |
| `required_conversation_resolution` | `true` | already set |
| `allow_force_pushes`, `allow_deletions` | `false` | already set |
| `enforce_admins` | `false` | deliberate — see 1.9 |

The applier is generated from the auditor's JSON baseline
(`enkinex-lab/governance/`), so every field it writes is one the audit first
read. Its constraints are recorded there: idempotent, `--dry-run` by default,
current → target diff before writing, refuses on unexpected drift rather than
overwriting, and never deletes or changes visibility without a separate flag.

Deliver it as `just protect <repo>` and `just verify-protection`, reading one
committed JSON template in `policy/`, alongside the existing shared-layer
sync recipes. ADR-0004 applies: the protection posture is an executable,
diffable, drift-checked artefact, not a click-path someone reproduces from
memory fourteen times. `verify-protection` joins `just check` if it can run
without network cost, and stays a separate recipe if it cannot. The template
is also what makes the four new repos cheap: creation becomes
`gh repo create --public` followed by one recipe.

### 1.6 Required status checks

The gap that costs the most today: CI runs on odcs/odps/okf and its result
does not block a merge (`required_status_checks: null` everywhere).

- odcs, odps, okf: require the existing `test` context. Zero new work.
- **enkinex-aiops has no CI at all** and owns 204 deterministic cases that
  run in ~14s. It gets a `test.yml` calling `just check`, then requires it.
- ossie, databricks, org-website: add the minimal workflow their gate already
  implies (`just check`, or `npm run typecheck` for the website).
- The five tutorial repos: a tutorial's gate is that **it still runs against
  the library version it pins**. A link check is not that. This is the one
  place in 1.6 that is new work rather than wiring, and it is the work that
  stops the tutorials rotting silently behind their libraries.

A deterministic-only workflow — no model calls — was already judged the
narrower amendment in the item this replaces. It stays narrow.

### 1.7 Tag protection

Tags are the release contract for a `kcl mod` consumer far more than `main`
is: `enkinex-odcs` v3.1.0 and `enkinex-odps` v1.0.0 are what a consumer pins.
Nothing currently stops a `v*` tag from being moved or deleted.

Add a `v*` tag ruleset per repo (repository rulesets returned no `403` on the
public repos, so they are available on this plan). Before writing fourteen of
them, check whether one **organization** ruleset can replace them: the
`orgs/enkinex/rulesets` probe returned `404` with a missing-scope hint, which
is ambiguous. Resolve it with `gh auth refresh -h github.com -s admin:org`
and retry. If org rulesets are available on Free, they become the primary
surface and the per-repo templates shrink to what they cannot express.

### 1.8 Secret-scanning push protection — the `--no-verify` backstop

This absorbs the "server-side backstop" item that was §1.5 of the previous
Phase 1, and answers the question it asked. Local hooks are bypassable and
inert on a fresh clone; that is unfixable from inside a repo. GitHub secret
scanning **with push protection** is free on public repositories and rejects
a credential at the remote, whether or not a hook ran, and whether or not
`--no-verify` was passed.

Branch-name and commit-message grammar have no equivalent server-side
control on this plan — rulesets can enforce branch *naming* on push, which
covers the slug grammar; the Conventional Commits subject remains
hook-and-review enforced. Record that split rather than leaving the gap
implicit.

### 1.9 Decisions to record

**Decided — ADRs migrate to `enkinex-knowledge-base`.** Architecture is
explicitly part of the KB's remit, so `enkinex-aiops/architecture/` becomes a
satellite of it rather than a peer, and the ADRs move there in Phase 3.

This does not contradict ADR-0005. That decision chose repo-local
distribution *for the shared layer* — artefacts a build consumes and a drift
check compares, which must exist in the repo that uses them. ADRs are a
different class: they are read by humans and agents at decision time and
consumed by no build. Centralising the second class while distributing the
first is the same reasoning applied to two different kinds of thing, not an
exception to it.

Four mechanics, because a half-done migration is worse than either end state:

- **Timing.** The move happens after the KB bundle model exists (Phase 3
  §3.2), not at repo creation. Until then `enkinex-aiops/architecture/`
  stays authoritative, and it is the only authoritative copy at any moment.
- **Numbering is preserved.** ADR-0002, 0004, 0005 keep their numbers across
  the move. Renumbering would break every `Refs:` footer and cross-link that
  points at them, for no gain.
- **A pointer stays behind.** `enkinex-aiops/architecture/` is replaced by a
  README naming the KB as the home, so existing links and agent instructions
  resolve instead of dangling.
- **ADR-0006, if written, is authored in `enkinex-aiops` and migrates with
  the rest.** The KB repo exists from Phase 1 §1.3 but has no bundle model
  until Phase 3; writing an ADR into an unmodelled corpus would create the
  first document nobody can validate.

The legacy private `enkinex-architecture` repo is not the target and is not
revived by this: the destination is the KB.

**Decided — a private `enkinex-lab` for unpublished research, referenced from
no tracked file.** LLM-assisted discovery and research need somewhere that is
not publication-ready, and running them through the harness is the point. The
repo is created fresh, private, named plainly. It is *not* a repurposing of
`enkinex-architecture`, whose ADRs migrate to the KB first and which stays
legacy; and it is not named `enkinex-discovery`, which would collide with the
`discovery/` directory that exists in every repo and feeds **public** plans.
The line against the KB: the KB is published knowledge, the lab is
unpublished research. The lab sits outside the fourteen and outside the team
map — it is not a product surface.

**The mechanism is omission, not obfuscation.** An earlier proposal — hide
the lab behind an environment variable, optionally with an unguessable name —
was rejected. The name is not the control; access is, and GitHub 404s a
private repo for non-members regardless. Obfuscation also fails on this
harness specifically: `Justfile` hardcodes `REPOS`, every loop spec carries
`repo: ../<name>`, `loop/runs.md` records what ran where, and `pre-push`
matches the **local directory basename** against the remote, so the name must
exist on disk whatever a variable calls it. Decisively, the agent *resolves*
the value — it enters the prompt, the OpenRouter payload, and whatever the
model writes next. The property actually wanted is that the lab never appears
in a tracked file, and a **gitignored local config** delivers it outright.

Deliverables, all of which improve the harness independently of the lab:

- Make the workspace root and repo list configurable rather than hardcoded in
  `Justfile` and each loop spec — today a contributor with a different clone
  layout must edit tracked files. The lab becomes a local-only entry.
- Extend the `pre-push` remote guard so lab-origin content cannot reach a
  public remote; extend the `pre-commit` content scan with lab markers.
  Secret-scanning push protection (1.8) is the server-side half.

**No "safety instructions" layer.** Telling agents not to expose sensitive
information in public plans is a prompt guard wearing a safety label, and
this project already settled that: loop.md Phase 2 found prompt guards
advisory, which is why enforcement moved to `.githooks/` and `guard.mjs`
(ADR-0004). What remains genuinely editorial is stated as editorial — public
plans cite conclusions, not the lab — and is not mistaken for a control.

Two things to accept with it. A private repo on this plan has **no branch
protection** (1.1), so the lab's own `main` is unprotected; nothing whose
integrity matters should live only there. And the *existence* of a private
research space is fine to disclose — normal for an open-source project, and
better than having an oddly-named repo surface in a shell history.

The rest are open. Each is a judgement call the owner should make explicitly,
because each has a defensible answer in both directions:

- **`enforce_admins`** — recommended `false` initially. With merge restricted
  to one person and code-owner review required, turning it on means the owner
  cannot land anything while the contributor is unavailable. It is the single
  deliberate bypass in the model and should be named as such, not discovered.
- **Signed commits — DECIDED 2026-08-06: required on all eleven public
  repos.** The concern recorded here, that every agent-authored commit would
  have to be signed, was misplaced. Branch protection governs what lands on
  `main`, and under squash-merge that is a commit **GitHub creates and signs
  itself** — every commit on every `main` already verified before the rule
  was turned on. Unsigned commits on feature branches are untouched, so the
  loop's commit path needed no change.

  `required_signatures` is a separate sub-resource (`POST
  …/branches/{branch}/protection/required_signatures`) that the protection
  `PUT` neither accepts nor returns, so it needs its own step and its own
  verification — the fourth setting this phase found where reading the
  obvious object proves nothing.

  What it rejects is a command-line merge of unsigned commits. That is the
  intent, not a side effect: PR merges through GitHub are the only sanctioned
  path anyway.
- **GitHub Issues** — the shared rules say "there are no GitHub Issues" and
  ban `Closes:` footers, yet every public repo has `has_issues: true` and
  ships an `ISSUE_TEMPLATE/`. Public repos with outside contributors make
  this a live contradiction. Either enable Issues deliberately and amend the
  commit-footer rule, or disable them and remove the templates.
- **Tutorial version lockstep** — recommended: a tutorial pins its library by
  tag in `kcl.mod` and is tagged in lockstep with the library's `major.minor`.
  The alternative, tracking `main`, means the tutorial breaks the moment the
  library moves and nobody finds out until a newcomer does. Whichever is
  chosen becomes the tutorial CI gate in 1.6.
- **Roadmap candour** — publishing `plan/` and `discovery/` means publishing
  unfinished work, known defects, and negative findings about named vendors'
  models. For a project whose thesis is Governance as Code that is an asset,
  and the benchmark is worth more with its failures intact than without. But
  it is a temperament choice, not a default, and it is easier to make once
  than to revisit per document.
- **Publishing the spend ledger** — `loop/loop-log.md` is tracked and carries
  the OpenRouter running total. Publishing burn is defensible for an
  open-source project and is even evidence for the benchmark; keeping it out
  is equally defensible. Decide before the flip, because after it the
  decision has already been made for you. Note the scope: this covers the
  ledger only. The **model pins are already public** — the tier table ships
  in the shared `AGENTS.md` block on `feat/adopt-opencode-layer` in three
  public repos, alongside `opencode.jsonc` and `opencode.headless.json`. A
  2026-08-05 sweep of those branches found nothing else: no infrastructure
  names, no `enkinex-agents` references, no paths, no keys.
- **ADR-0006** — publication and the org-as-enforcement-boundary are one-way
  in a way branch topology is not, which is the ADR-0004 test for writing one.
  The trunk-based decision itself belongs in this plan (§1), not in an ADR.
- **Repo count vs. seats** — fourteen repos on a 2-seat Free org. Org
  rulesets and private-repo protection are the two things the plan is
  currently working around; note the price of Team so the constraint is a
  choice rather than an assumption.

### 1.10 Applied — status at 2026-08-05

Applied by `enkinex-lab/governance/apply-governance.sh`, verified by a fresh
audit run. The applier is idempotent, so re-running it is the drift check.

| Done | Detail |
|---|---|
| Org flags | Seven by API; `members_can_delete_repositories` and `members_can_change_repo_visibility` by hand in Member privileges — the API accepts and ignores those two (1.4) |
| Four teams | LibDev, KbDev, PlatformDev, WebDev, at `write` |
| Access corrected | Two direct `admin` grants revoked; `libdev` removed from `enkinex-lab` |
| Branch protection | All 8 public repos on the 1.5 template, merge restricted, linear history on |
| CODEOWNERS | Now present in all 8 — five added by PR, since the applier does not commit |
| Tag protection | `v*` deletion and non-fast-forward blocked on the 7 versioned repos, no bypass |
| Status checks | `test` required on all 7 code repos. CI added to databricks, ossie and both tutorials by PR; `.github` and the empty knowledge base deliberately have none |
| 2FA | Required org-wide, 2026-08-06. Both members were already enrolled (`?filter=2fa_disabled` returned empty), so enforcement removed nobody. A **third** API-accepted-and-ignored field, set by hand under Authentication security |
| Publication | `enkinex-aiops` recreated from a clean root and published; `enkinex-knowledge-base` created public and empty. Both protected. The applier now discovers public repos, having silently missed both when the list was hardcoded |
| Shared layer | Live in all six repos — the five adoption PRs merged 2026-08-06 |
| Signed commits | Required on all eleven public repos, 2026-08-06. Safe because GitHub signs the squash commits it creates; a command-line merge of unsigned commits is rejected, which is the intent |
| History scans | All **10** public repos scanned 2026-08-06 by `enkinex-lab/governance/scan-history.sh` across every commit on every branch and tag: no credentials, no secret-shaped assignments, no `.env`/key files ever added, no local paths or personal emails. GitHub secret scanning reports 0 alerts on each. This closes the retrospective owed on `enkinex-databricks` and `enkinex-odps-tutorial` |
| Secret scanning + push protection | Enabled on all 8 public repos. The org `*_for_new_repositories` flags do **not** retro-apply, so this needed a per-repo `PATCH`; §1.8's backstop is now genuinely on |

**Still open, in rough priority order:**

1. `enkinex-org-website`: publication is now a decision, not a blocker. Its
   2026-08-06 scan found no Cloudflare credentials (`wrangler.jsonc` carries
   no `account_id`, `zone_id` or token; deployment is a local `wrangler
   deploy` with no Actions secrets, environments, deploy keys or webhooks),
   no analytics secret (a GA4 measurement ID is public by design and already
   served in the site's JavaScript), and no prompts, plans or LLM-related
   content. What remains is editorial: 8 pages are `TodoBanner`
   placeholders.
3. `CODEOWNERS` and CI for `enkinex-aiops`; `CODEOWNERS` for
   `enkinex-knowledge-base`. Note aiops CI runs `just test`, not `just
   check` — `verify-opencode` reads sibling clones from `../`, which do not
   exist in a single-repo Actions checkout.
4. Dependabot **security updates** (fix PRs) are off on all public repos.
   Alerts are on. A no-op for the KCL repos — Dependabot does not parse
   `kcl.mod` — so it matters only for `enkinex-org-website`.
5. §1.9 open items: the Issues contradiction and ADR-0006. Signed commits
   were decided and applied on 2026-08-06.

### Acceptance

- The in-scope repos public: eight already there, `enkinex-aiops` and
  `enkinex-org-website` flipped after a clean full-history scan,
  `enkinex-knowledge-base` created. Retrospective scans run on
  `enkinex-databricks` and `enkinex-odps-tutorial`. The three deferred
  tutorials are not part of this phase. Legacy private repos untouched and
  owner-only.
- `members_can_delete_repositories: false`, `xaviervini` still a member, no
  team holding `Admin`, and the two direct `admin` grants on
  `enkinex-bitol-common` and `enkinex-odps-tutorial` removed.
- Four teams cut — LibDev, KbDev, WebDev, PlatformDev — every repo assigned
  to exactly one, at `Maintain`.
- Every `main` protected by the 1.5 template, applied by `just protect` and
  verified by `just verify-protection` — including the four unprotected
  today: `enkinex-databricks`, `enkinex-odcs-tutorial`,
  `enkinex-odps-tutorial`, `.github`.
- `libdev` no longer holds `write` on `enkinex-lab`.
- A clean audit run: `governance/audit-governance.sh` reports no observation
  that has not been decided.
- Status checks required everywhere, which means CI exists everywhere,
  starting with `enkinex-aiops` and including a real gate for each tutorial.
- `v*` tags protected; secret-scanning push protection on.
- 1.9 decisions recorded with rationale.

## 3. Phase 2 — Harness & loop pending tasks

Goal: everything in `loop.md` that is known-broken or known-missing, closed,
so that the two dogfooding phases run on a harness nobody has to work around.

Branch: `fix/harness-pending-tasks`.

### 2.1 The odcs loop hang (blocking — do first)

Every `just loop` run against `enkinex-odcs` hangs with no output from step 1
and must be killed. The identical invocation by hand —
`OPENCODE_CONFIG_CONTENT=… opencode run --dir … --agent build-kcl "<same
prompt>"` — completes in ~30 s with correct output. It reproduces under
`just loop`, under `bash scripts/loop.sh`, and on both the free and the mid
tier; the same runner completes fine against `enkinex-okf`. Reproducer:
`loop/tasks/odcs-check-rule-audit.yaml`.

Not yet ruled out: output buffering through `tee` when stdout is not a TTY;
something repo-specific to odcs (35 `server/*.k` files, a larger context);
MCP server startup interacting with the pipe. Nothing here should be assumed
— the last four defects in this layer were all found by executing, not by
reading.

Acceptance: `just loop odcs-check-rule-audit` completes, and a regression
case in `tests/loop.test.sh` covers whatever the cause turns out to be.

### 2.2 Free-tier viability

`explore-enkinex` on `nvidia/nemotron-3-nano-30b-a3b:free` failed to finish a
broad exploration step in 10 minutes on two separate occasions, and answered
a narrow bounded question in seconds. Decide: keep the free tier for bounded
lookups only, or re-pin the explore agent to mid. This is direct evidence for
the benchmark's T1 tier-pinning decision and should be recorded there.

### 2.3 Agent-output evals

The golden set is deterministic and covers the artefacts, not the agents.
Three decisions are the user's before this can be built: which tier to
evaluate on, acceptable cost per run, and a pass threshold under
nondeterminism. Intended home `.agents/evals/`, run by `just eval`, kept out
of `just check` so the gate stays free and fast.

### 2.4 OpenRouter model-level fallback

`loop.md` §5 requires per-agent fallback chains; none exist. No verified
config path was found — `provider.<id>.options` accepts unknown keys and
`agent.options` is free-form, but neither is documented to forward OpenRouter
routing parameters, and an echo-server rig could not confirm even `baseURL`
passthrough. Provider-level failover within a model is already automatic, so
only *model*-level fallback is missing. Needs a working instrumentation
approach, or an OpenRouter-side preset.

### 2.5 OpenRouter spend limit — set, but the ledger cannot see it

A spend limit was set at the **workspace** level (OpenRouter Guardrails) on
2026-08-04. That is the right control: it holds regardless of which harness
spends the money, and it applies to Claude Code and Codex sessions too, not
just opencode.

The ledger, however, still reports `Key limit: none` and warns on every run,
because `/api/v1/key` exposes only the *per-key* limit and that remains
`null`. The warning is now a false positive, which is worse than no warning —
an alert that is always wrong gets ignored, and then the real one is missed
too.

Pending, pick one:

- set a per-key limit as well, so the two agree and the existing check works
  unchanged; or
- teach `scripts/ledger.sh` to read the workspace guardrail (check whether
  the management API exposes it) and warn only when *neither* control is
  present.

Either way `tests/` should gain a case, since this is a check that silently
reports the opposite of the truth.

### 2.6 Smaller items

- Complete 7A dogfooding once 2.1 is fixed: one task per repo across both
  gate types (`just check` and `npm run typecheck`), each spec carrying a
  review step and an `expect` block.
- Decide the fate of `github-pr-cycle`: the branch/commit rules it would
  orchestrate are now enforced by `.githooks/` for every author, and the
  actions it would take are denied to a headless runner. Likely a
  human-driven `/ci-*` chain rather than a loop task.
- `docs-writer`'s instructions mention the website's `TodoBanner` component
  and are synced into KCL library repos where it does not exist.

Acceptance: 2.1 fixed with a regression case; 2.2, 2.3, 2.4, 2.5 each either
delivered or recorded as an explicit decision with rationale; 7A dogfooding
complete across all repos except databricks.

> The server-side backstop for `--no-verify`, previously tracked here, moved
> to Phase 1 §1.8 — it is an org and ref concern, not a harness one.

## 4. Phase 3 — OKF Dogfooding, and the knowledge-base repo

Goal: prove the loop on a real, multi-step body of work, and produce the
enkinex knowledge base as its output.

Branch: `feat/okf-dogfooding`. **To be detailed in its own plan before any
work starts** — this section is scope, not specification.

### 3.1 The new repository

`enkinex-knowledge-base`, owned by `KbDev`. The **repository** is created
public and protected in Phase 1 §1.3, so it is never an ungoverned public
repo; what belongs to this phase is its **model and content**.

Its destination is broader than the corpus this phase builds: it is the
source of truth for docs, specs, reusable knowledge, architecture, and the
documentation exported to `enkinex-org-website`. That makes the KB→website
export a standing interface between KbDev and WebDev, and it makes
`enkinex-aiops/architecture/` a satellite of the KB rather than its peer —
the ADRs migrate here, decided and specified in §1.9.

Grounding: `discovery/opencode/harness-agnostic-review.md` §8, which reviewed
`enkinex-okf` against the OKF v0.2 spec and found the approach feasible, with
these results already established:

- KCL can write the file tree itself (`file.write`/`mkdir`/`read`/`glob`,
  verified on 0.12.7) — the generator is pure KCL, no external emitter.
- A single document can be simultaneously a conformant OKF concept and a
  valid `SKILL.md`, so skill generation is a projection, not a translation.
- `enkinex-okf` models frontmatter only; the bundle tree, `index.md`,
  `log.md`, cross-links and directory-level conformance are unmodelled
  (§8.2, gaps G1–G5).

### 3.2 Scope sketch

- `enkinex-okf` v0.3: bundle model, renderer with deterministic key ordering,
  directory-level conformance, link validation, and a closed producer
  vocabulary.
- The new repo: the governance corpus only to begin with (commit convention,
  branch grammar, PR template, review rules, and now the team map and
  protection posture from Phase 1) — roughly a dozen concepts. Docs, specs
  and architecture follow once the bundle model has survived one real
  consumer; a corpus that takes everything on day one cannot be evaluated.
- The ADR migration decided in §1.9: ADR-0002, 0004, 0005 (and 0006 if it is
  written) move from `enkinex-aiops/architecture/` into the bundle with their
  numbers intact, leaving a pointer README behind. They are the second real
  consumer of the model, after the governance corpus, and a good test of it —
  an ADR is prose with structure, which is exactly what the frontmatter-only
  v0.2 model cannot yet hold.
- Emit two artefacts from that one source: the `.agents/skills/` tree and the
  shared block of `AGENTS.md`. Both committed, both gated by
  `git diff --exit-code`. The website export is a third projection, added
  once the first two hold.

### 3.3 Scaling the corpus — a deferred decision with one constraint

Splitting into sub-bundles, or moving behind a backend (cocoindex, pageindex,
neo4j, surrealdb), is a real problem for later and should not be pre-solved
here. One constraint binds whatever arrives: **the committed OKF bundle stays
the source of truth, and any backend is a derived index that can be rebuilt
from it.** A store that becomes authoritative is a store whose contents are
unreviewable and undiffable — which is the same failure §3.4 rejects, one
layer down. Choosing a backend before the corpus is large enough to hurt
would also be choosing on speculation rather than on a measured retrieval
problem.

### 3.4 The decision this phase must not get wrong

**Generate at build time and commit the output.** Generating skills at
session start and never committing them reintroduces exactly what ADR-0005
rejected: governance that exists only after a ritual, invisible to review,
and undiffable. The bundle is the source, `just` is the compiler, the
committed tree is the artefact. Runtime fetch (opencode's `skills.urls`) is
for cross-repo distribution only.

Prerequisites: Phase 1, because this phase creates a repository and the rules
for creating one must exist first; and Phase 2, because this is the first
phase that leans on the loop for real work.

## 5. Phase 4 — Databricks Dogfooding

Goal: `enkinex-databricks` from v0.1.0 scaffold to a real library, built by
the loop, with the model-tier benchmark filled in as a by-product.

Branch: `feat/databricks-dogfooding`. Deferred out of v0.2.0 deliberately and
detailed in `plan/opencode/benchmark-enkinex-databricks.md` (task ladder
T0–T8, scoring rubric, Opus-5 baseline comparison).

Prerequisite, open since Phase 0: `databricks bundle schema > dab-schema.json`
is the machine-readable source T1 maps from, and the REST-docs fallback is
weaker (the benchmark plan says so). The user will install the Databricks CLI
directly; confirm it is on PATH and snapshot the schema before T1 starts.

This phase is materially different in kind from Phase 3: T2/T3 ask the loop
to *implement KCL modules*, not to write documents. Given that a mid-tier
step produced a plausible but partly fabricated document during Phase 5
proving (it claimed OKF uses `okf://` URIs, which it does not), expect
generated KCL to need substantial review. That expectation is itself the
benchmark evidence — record it rather than working around it.

Note that `enkinex-databricks` becomes public in Phase 1, so this phase's
output lands in the open from its first commit. Scope boundary 4 applies to
it from that point on.

Runs last because it is the largest, the least certain, and the only one with
an unmet external prerequisite.

## 6. Scope boundaries

1. No history rewrite — with one exception, confined to Phase 1 §1.3: a repo
   whose history carries a credential is rewritten or recreated *before* it
   is published, never after. The six open adoption PRs land or are closed on
   their own merits first.
2. No repository is made public before a clean full-history credential scan.
   Publication is one-way. Legacy private repos are out of scope: this plan
   neither publishes nor retires them.
3. Each phase is its own branch and its own PR. Phase 3 and Phase 4 each get
   a detailed plan before implementation starts.
4. Unreviewed model output does not land in a repository. The Phase 5 proof
   run's artefact was deleted for containing an invented detail; that is the
   standard, not an exception.
5. All in-scope repos are public and must remain fork-safe. Nothing
   experimental, unverified, or credential-shaped goes into them.
6. Only the org owner merges to `main`, in every repo, enforced by push
   restriction rather than convention.
7. Phase 4 does not start before Phase 3 lands, Phase 3 does not start before
   Phase 2, and nothing starts before Phase 1.

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| A repo is published with a credential in its history | Full-history scan per repo before the flip (§1.3); publication is one-way, so the scan is the only control that works |
| A repo is deleted | Two independent conditions, both required: contributor stays an org member, `members_can_delete_repositories: false` (§1.2, §1.4) |
| Protection drifts, or a new repo is created without it | `just protect` / `just verify-protection` from one committed template; repo creation restricted to the owner (§1.4, §1.5) |
| A public repo sits unprotected between flip and template | Scan → flip/create → protect → verify in one sitting per repo; create the four new repos only after `just protect` exists; `enkinex-odcs-tutorial` and `.github` are the standing example (§1.3) |
| A tutorial rots behind the library it teaches | Tutorial CI runs against the pinned library version, not a link check; version-lockstep decided in §1.9 (§1.2, §1.6) |
| The odcs hang has a cause that also affects other repos silently | Fix before any dogfooding; add a regression case; the loop already fails loudly on no-effect rather than reporting a false pass |
| Generated content lands unreviewed in a public repo | Every loop spec carries a review step and an `expect` block; required status checks (§1.6); boundary 4 |
| Databricks generation produces low-quality KCL at scale | Treat as benchmark evidence; T4 review is a frontier-tier gate; keep T2/T3 scoped per module |
| Spend runs away during dogfooding | Workspace-level OpenRouter budget is set; `just ledger` per run. Reconcile the ledger's per-key check with it (2.5) so the warning stops lying |

## 8. Done criteria

- [ ] Phase 1 — the thirteen product repos public (four flipped after a
      clean history scan, four created) and `.github` protected; deletion
      closed off; four teams cut at `Maintain`; the protection template
      applied and drift-checked everywhere; status checks required, tutorials
      included; `v*` tags protected; push protection on; the ADR migration
      and `enkinex-lab` decisions recorded, workspace paths made configurable,
      and the remaining §1.9 decisions made.
- [ ] Phase 2 — odcs hang fixed with a regression case; 2.2–2.5 delivered or
      decided; 7A dogfooding complete outside databricks.
- [ ] Phase 3 — detailed plan written; `enkinex-okf` v0.3 bundle model;
      the governance corpus in `enkinex-knowledge-base`; skills and
      `AGENTS.md` generated from it, committed and drift-gated; ADRs migrated
      with numbers intact and a pointer left in `enkinex-aiops/architecture/`;
      the KB→website export and the wider docs/specs scope sequenced, not
      built.
- [ ] Phase 4 — Databricks CLI on PATH and `dab-schema.json` snapshotted;
      benchmark scorecard filled with evidence; tier pins and frontier
      fallback order recorded.
- [ ] This plan moves to `plan/done/` with an Outcome section.
