# ADR 0006 — GitHub Issues are the unit of work; Actions, Projects and Releases stay closed

- Status: Accepted
- Date: 2026-08-16
- Deciders: rodrigo@enkinex.com
- Supersedes: ADR-0002 Decisions 4 and 5, **for Issues only**
- Superseded by: —

## Context

ADR-0002 Decision 4 reads *"No GitHub Actions, no Issues, no Projects, no
Releases"*, and Decision 5 keeps `gh issue|project|workflow|run|release`
denied in the permission table. Both were written on 2026-08-03 as one
sentence about four surfaces.

The work now needs one of them. Planning is centralised in the private
`enkinex-pm`, and the flow it exists to serve narrows a plan into an issue
document and then into an implementation:

```
specify → plan → issue → implement
```

The last transition has no public artefact. An approved plan becomes an issue
document on disk in a repository nobody outside the org can read, and the work
then appears on `main` as a merged pull request with no visible statement of
what was being attempted or why. **Contributors and readers of nine public
repositories can see every answer and none of the questions.**

**The cost argument that justified the ban never applied to Issues.** ADR-0002
bundles them with Actions, and its reasoning is cost: Actions consume billable
compute, and ADR-0001's objection to GitHub MCP is ambient per-session token
cost. An issue consumes neither. `gh issue create` is a bounded CLI call of
exactly the kind ADR-0002 §2 *reaffirms* for every other GitHub mutation —
same transport, same permission table, same audit trail as `gh pr create`,
which has always been allowed. Issues were forbidden by adjacency.

**The counter-argument, stated because it is not weak.** ADR-0002's real
through-line is *"no GitHub surface we do not need"*. With one operator,
`enkinex-pm/issues/` on disk is already a tracker, and a public issue buys
agent-assignability and an outward-visible roadmap and nothing else. That is a
genuine cost — one more surface to keep tidy, and an empty or stale issue list
is worse than none. The decision below is that the visibility is worth it now
that the planning surface is private; it would not have been worth it while
planning was public.

## Decision

1. **GitHub Issues are the unit of work at the `implement` stage.** An
   approved plan becomes an issue before implementation begins. The issue is
   the public statement of intent; the plan behind it stays private.

2. **Reads are allowed, writes are asked, destruction is denied.** The
   permission table gains, in `opencode.jsonc`:

   | Command | Action | Why |
   |---|---|---|
   | `gh issue list`, `gh issue view` | `allow` | Read-only, zero prompts — the posture every other read has |
   | `gh issue create`, `comment`, `edit` | `ask` | A mutation with a public audience. `gh pr create` is `ask`; an issue is not more casual than a PR |
   | `gh issue delete`, `gh issue transfer` | `deny` | Deleting destroys the record this ADR exists to create, and transfer moves it out of the org's repository. Owner actions, taken by hand |
   | `gh issue*` (anything else) | `deny` | The catch-all stays. New subcommands arrive denied and are opened deliberately |

3. **The headless profile files nothing.** `opencode.headless.json` denies
   `gh issue*` outright. An unattended loop run must not create a public
   artefact in the org's name while nobody is watching — the same reasoning
   that denies `gh pr create` there.

4. **Actions, Projects and Releases stay forbidden, and the reason is
   restated so nobody reopens them by analogy with this ADR.** Actions consume
   billable compute and the local loop runner is the pipeline (ADR-0004);
   Projects are a second tracker over the same issues; Releases are a
   publishing surface this org does not use. **Issues are not a precedent for
   them.** Reopening any of the three requires its own ADR naming the concrete
   need, exactly as ADR-0002 §3 requires for GitHub MCP.

5. **`Closes:` / `Fixes:` / `Resolves:` footers stay rejected.** The
   `commit-msg` hook refuses them today and continues to. A footer that closes
   an issue on merge makes the issue's lifecycle a side effect of a commit
   message; issues are closed by hand, deliberately, after the squash merge.
   The `Refs: <TASK-ID>` footer is unchanged and still names the plan task,
   not the issue.

## Rationale

- **Bounded CLI call, existing transport.** Nothing about `gh issue create`
  differs in kind from `gh pr create`: same binary, same auth, same permission
  table, same `ask` posture. The change is one line of policy, not a new
  integration.
- **The private planning surface is what makes this necessary.** While plans
  lived beside the code, the repository showed its own reasoning. Centralising
  them was right and it took the public trail with it; this puts back the
  minimum needed for a reader to see what is being attempted.
- **Granularity is the safeguard, not a blanket reversal.** ADR-0002 §3 asks
  for revisits "per concrete unmet need, per service, never as a blanket
  reversal". This ADR reverses one surface, in one direction, with the
  destructive verbs still denied.

## Consequences

### Positive

- The `specify → plan → issue → implement` flow can run end to end.
- Public repositories gain a visible statement of intent per unit of work,
  without publishing the planning that produced it.
- Issues are assignable to agents, which the on-disk tracker is not.

### Negative

- **One more surface to keep tidy.** A stale issue list is worse than no issue
  list, and nothing in this ADR maintains it. The discipline is that an issue
  is created from an approved plan and closed by hand at merge — both manual.
- **Two trackers exist during the transition.** `enkinex-pm/plan/backlog.md`
  remains the private ordering of work; issues are the public unit of
  implementation. They are not synchronised by anything, and if they disagree
  the backlog is authoritative.
- The permission table grows five rules where it had one deny.

## References

- ADR-0002 (Decisions 4 and 5, partially superseded here; the no-Actions
  corollary and the GitHub MCP denial are untouched and restated above).
- ADR-0004 (executable governance — why the loop runner is the pipeline and
  Actions stay closed).
- The flow this serves is defined in `enkinex-pm/plan/README.md` (private),
  and the issue scaffolding is `PM-04`.
