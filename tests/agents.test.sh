#!/usr/bin/env bash
# Regression suite for the agent and command definitions.
#
# These are the artefacts ADR-0004 calls the workflow definition, and they fail
# quietly: a typo in a model id, an agent pinned to a model that no longer
# exists on OpenRouter, a command delegating to an agent that was renamed, or a
# blanket `just *` creeping back into one agent's frontmatter and re-opening
# every command the baseline denies. None of that surfaces until a run.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

AGENT_DIR="$ROOT/opencode/agent"
CMD_DIR="$ROOT/opencode/command"

frontmatter() { awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f' "$1"; }
fm_value() { frontmatter "$1" | sed -n "s/^$2: *//p" | head -1; }

section "agent frontmatter"
for f in "$AGENT_DIR"/*.md; do
    name="$(basename "$f" .md)"
    [ -n "$(fm_value "$f" description)" ] && ok "$name has a description" ||
        no "$name has a description" "opencode requires it to route the subagent"
    mode="$(fm_value "$f" mode)"
    case "$mode" in
        subagent | primary | all) ok "$name mode=$mode" ;;
        *) no "$name has a valid mode" "got '${mode:-<missing>}'" ;;
    esac
    model="$(fm_value "$f" model)"
    [ -n "$model" ] && ok "$name pins a model" ||
        no "$name pins a model" "an unpinned agent silently inherits the session default"
done

section "model pins resolve on OpenRouter"
# The only non-hermetic check in the suite: it needs the opencode binary and
# a live catalog. Absent binary is environmental (CI runs without it) and
# skips; a present binary returning nothing is a real signal and fails.
if ! command -v opencode >/dev/null 2>&1; then
    ok "skipped: opencode not installed, so pins cannot be checked here"
    CATALOG=""
else
    CATALOG="$(timeout 120 opencode models openrouter 2>/dev/null || true)"
fi
if [ -z "$CATALOG" ]; then
    command -v opencode >/dev/null 2>&1 &&
        no "fetched the OpenRouter catalog" "opencode models openrouter returned nothing"
else
    for f in "$AGENT_DIR"/*.md; do
        name="$(basename "$f" .md)"
        model="$(fm_value "$f" model)"
        [ -n "$model" ] || continue
        if grep -Fxq "$model" <<<"$CATALOG"; then
            ok "$name -> $model"
        else
            no "$name -> $model" "not in the OpenRouter catalog; a re-pin is a PR (AGENTS.md)"
        fi
    done
fi

section "KCL agents carry the context7 docs wiring"
# context7 sat in the shared baseline for a week: connected, proven by Phase 3's
# acceptance test, and referenced by nothing — a tool catalog billed to every
# session across ten repos with no caller. The wiring is what makes it earn that
# cost, and a well-meaning trim of an agent's instructions is exactly how it
# would quietly go back to being unused. See harness-and-dogfooding.md §2.6.
C7_IDS="/kcl-lang/kcl-lang.io
/bitol-io/open-data-contract-standard
/bitol-io/open-data-product-standard
/apache/ossie
/databricks/cli"
for name in build-kcl review-standard; do
    f="$AGENT_DIR/$name.md"
    [ -f "$f" ] || { no "$name exists" "missing agent definition"; continue; }

    if grep -Fq "context7_query-docs" "$f"; then
        ok "$name names the context7 tool"
    else
        no "$name names the context7 tool" \
            "the server is declared in opencode.jsonc but no agent would call it"
    fi

    missing=""
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        grep -Fq "$id" "$f" || missing="$missing $id"
    done <<<"$C7_IDS"
    [ -z "$missing" ] && ok "$name carries every verified library id" ||
        no "$name carries every verified library id" "missing:$missing"

    # OKF is the one standard context7 does not index. Without the exception
    # stated, the agent spends calls hunting for an entry that does not exist.
    if grep -Fq "not indexed by context7" "$f"; then
        ok "$name records that OKF is not indexed"
    else
        no "$name records that OKF is not indexed" \
            "enkinex-okf must be steered to its committed reference"
    fi
done

section "commands delegate to agents that exist"
for f in "$CMD_DIR"/*.md; do
    name="$(basename "$f" .md)"
    agent="$(fm_value "$f" agent)"
    if [ -z "$agent" ]; then
        ok "$name has no agent pin (runs on the session agent)"
    elif [ -f "$AGENT_DIR/$agent.md" ]; then
        ok "$name -> $agent"
    else
        no "$name -> $agent" "no such agent in opencode/agent/"
    fi
done

section "no agent re-opens a blanket 'just *'"
# The baseline enumerates just recipes because a Justfile runs arbitrary shell.
# Agent permissions take precedence over the baseline, so one blanket rule in
# frontmatter would undo that everywhere the agent runs.
for f in "$AGENT_DIR"/*.md; do
    name="$(basename "$f" .md)"
    if frontmatter "$f" | grep -Eq '"just \*" *: *"allow"'; then
        no "$name has no blanket just *" "grants arbitrary shell via any Justfile recipe"
    else
        ok "$name has no blanket just *"
    fi
done

section "loop agents declare no bash catch-all"
# Agent frontmatter is appended AFTER the global config and the headless
# overlay, so an agent's own "*" rule wins under last-match-wins and defeats
# every allow the overlay grants it. The catch-all belongs to the profile.
for name in build-kcl docs-writer review-standard plan-author; do
    f="$AGENT_DIR/$name.md"
    [ -f "$f" ] || { no "$name exists" "missing"; continue; }
    if frontmatter "$f" | grep -Eq '^ *"\*" *: *"(ask|deny)"'; then
        no "$name has no bash catch-all" "its \"*\" rule overrides the headless profile"
    else
        ok "$name has no bash catch-all"
    fi
done

section "planning is centralised — no agent teaches a repo-local plan/"
# AIOPS-02 moved planning into the private enkinex-pm sibling, but the workflow
# agents encoded the old layout as *behaviour*: pr-open refused to open a PR
# without a plan reference and pr-review checked that it resolved to a real
# local `plan/` section. In a repo that no longer has one, those two agents
# blocked the workflow they exist to run. The gate is kept below; what moved is
# its target, so these cases assert both halves — still refuses, resolves
# centrally.
for name in pr-open pr-review git-commit plan-author; do
    f="$AGENT_DIR/$name.md"
    [ -f "$f" ] || { no "$name exists" "missing agent definition"; continue; }
    if grep -Fq 'enkinex-pm/plan/' "$f"; then
        ok "$name resolves plans in enkinex-pm"
    else
        no "$name resolves plans in enkinex-pm" \
            "it must name ../enkinex-pm/plan/<repo>/, not a local plan/"
    fi
done

# The stages that no longer exist. A negative statement about them is fine in
# prose; a path an agent could act on is not.
if grep -rn 'plan/done\|discovery/' "$AGENT_DIR" "$CMD_DIR" >/dev/null 2>&1; then
    no "no agent names plan/done/ or discovery/" \
        "$(grep -rln 'plan/done\|discovery/' "$AGENT_DIR" "$CMD_DIR" | tr '\n' ' ')"
else
    ok "no agent names plan/done/ or discovery/"
fi

# The refusal is the point of the gate and must survive the retarget: an agent
# that stopped asking for a plan reference would be a regression, not a fix.
# Matched against the file with newlines collapsed: these are prose documents
# wrapped at ~100 columns, so a phrase that fits on one line today straddles two
# after the next edit. A case that fails on reflow trains you to reflow for the
# test rather than for the reader.
unwrapped() { tr '\n' ' ' <"$1" | tr -s ' '; }

if unwrapped "$AGENT_DIR/pr-open.md" | grep -Fq 'Refuse to open without a plan reference'; then
    ok "pr-open still refuses without a plan reference"
else
    no "pr-open still refuses without a plan reference" \
        "AIOPS-08 moves the target of this gate; it does not remove the gate"
fi

# No-Plan-Ref is the correct footer for a commit that advances no plan, and the
# hook has always accepted it. Undocumented, it reads as a bypass and gets used
# like one — or a task ID gets invented to satisfy the hook, which is worse.
if grep -Fq 'No-Plan-Ref:' "$AGENT_DIR/git-commit.md"; then
    ok "git-commit documents the No-Plan-Ref escape hatch"
else
    no "git-commit documents the No-Plan-Ref escape hatch" \
        "the hook accepts it; an undocumented escape hatch is used blindly"
fi

# plan-author now writes into a different git repository than the one it is
# invoked from. Staging across that boundary is the failure mode.
if grep -Fq 'Never stage or commit across the boundary' "$AGENT_DIR/plan-author.md"; then
    ok "plan-author states the cross-repo boundary"
else
    no "plan-author states the cross-repo boundary" \
        "it writes into ../enkinex-pm/, a separate history from the code"
fi

section "the taught Refs: footer is one the commit-msg hook accepts"
# A template the hook rejects is worse than no template: the agent produces it,
# the hook refuses it, and the loop stalls with the agent's own instructions as
# the cause. So this does not re-implement the grammar — it renders the footer
# each agent teaches and runs it through the real hook.
taught_refs() { grep -m1 '^Refs: ' "$1" | sed 's/<TASK-ID>/AIOPS-08/'; }

GC_REFS="$(taught_refs "$AGENT_DIR/git-commit.md")"
PO_REFS="$(taught_refs "$AGENT_DIR/pr-open.md")"

if [ -n "$GC_REFS" ] && [ "$GC_REFS" = "$PO_REFS" ]; then
    ok "git-commit and pr-open teach the same footer"
else
    no "git-commit and pr-open teach the same footer" \
        "git-commit: '${GC_REFS:-<none>}' vs pr-open: '${PO_REFS:-<none>}'"
fi

case "$GC_REFS" in
    *plan/*) no "the taught footer is not a repo-local path" \
        "'$GC_REFS' points into a plan/ directory the repo does not have" ;;
    *) ok "the taught footer is not a repo-local path" ;;
esac

# The grammar itself is AIOPS-10's decision; AIOPS-08 adopts its recommended
# form (the stable task ID) so the agents teach something the hook accepts
# today. If AIOPS-10 settles on a different shape, this case is what says so.
if printf '%s' "$GC_REFS" | grep -Eq '^Refs: [A-Z]+-[0-9]+$'; then
    ok "the taught footer is a stable task ID"
else
    no "the taught footer is a stable task ID" "got: '$GC_REFS'"
fi

REPO="$(new_repo "$ROOT/githooks")"
trap 'rm -rf "$REPO"' EXIT
if try_commit "$REPO" "feat: probe the footer the agents teach"$'\n\n'"$GC_REFS"; then
    ok "commit-msg accepts the footer git-commit teaches"
else
    no "commit-msg accepts the footer git-commit teaches" \
        "the hook rejected '$GC_REFS' — the agents would stall every commit"
fi
if try_commit "$REPO" "chore: probe the documented escape hatch"$'\n\n'"No-Plan-Ref: repo hygiene"; then
    ok "commit-msg accepts the No-Plan-Ref git-commit documents"
else
    no "commit-msg accepts the No-Plan-Ref git-commit documents" \
        "git-commit documents a footer the hook refuses"
fi

section "github workflow agents stay read-only where it matters"
for name in git-branch git-commit pr-open pr-review pr-land; do
    f="$AGENT_DIR/$name.md"
    [ -f "$f" ] || { no "$name exists" "missing agent definition"; continue; }
    if frontmatter "$f" | grep -Eq '^ *(edit|write): *deny'; then
        ok "$name denies edit/write"
    else
        no "$name denies edit/write" "a git workflow agent must not modify files"
    fi
done

summary
