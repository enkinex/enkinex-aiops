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
