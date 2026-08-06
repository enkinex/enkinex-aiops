#!/usr/bin/env bash
# The enkinex loop runner (loop.md Phase 5).
#
#   just loop <task-name> [--dry-run]
#
# Drives a task spec from loop/tasks/<name>.yaml as an ordered set of opencode
# sessions, then a mechanical gate, then a single repair attempt. Stops at the
# human gate: it never pushes and never opens a PR.
#
# WHY `opencode run` AND NOT THE SDK
# ----------------------------------
# Phase 5 originally specified @opencode-ai/sdk over `opencode serve`, for one
# reason: something had to answer permission prompts with no human attached.
# The headless profile removed that problem instead of solving it — it contains
# no `ask` rules at all, so there is nothing to answer (see
# scripts/opencode-headless.sh). With the justification gone, `opencode run`
# per step is simpler, has no npm dependency, and gives each step its own
# process — which is exactly the fresh context the plan wants for the review
# step, rather than something to engineer.
#
# WHY THE HUMAN GATE IS NOT ENFORCED HERE
# ---------------------------------------
# The runner stopping before `git push` would be a promise. Under the headless
# profile, push, rebase, PR creation and PR merge are DENIED, so a runaway step
# cannot take those actions even if it tries. This script stopping is the
# expected path; the profile is what makes it true.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS="$ROOT/loop/tasks"
# Overridable so the regression suite never appends to the committed log.
RUNLOG="${LOOP_RUNLOG:-$ROOT/loop/runs.md}"

die() { echo "loop: $*" >&2; exit 1; }

[ "$#" -ge 1 ] || die "usage: just loop <task-name> [--dry-run]"
NAME="$1"; shift
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

SPEC="$TASKS/$NAME.yaml"
[ -f "$SPEC" ] || die "no task spec at loop/tasks/$NAME.yaml
  available: $(ls "$TASKS" 2>/dev/null | sed 's/\.yaml$//' | tr '\n' ' ')"

# ── spec ───────────────────────────────────────────────────────────────────
spec_json="$(python3 -c '
import json, sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
for k in ("task", "repo", "steps"):
    if k not in d:
        sys.exit(f"spec is missing required key: {k}")
if not isinstance(d["steps"], list) or not d["steps"]:
    sys.exit("spec.steps must be a non-empty list")
for i, s in enumerate(d["steps"]):
    for k in ("agent", "prompt"):
        if k not in s:
            sys.exit(f"steps[{i}] is missing: {k}")
d.setdefault("gate", "just check")
d.setdefault("retries", 1)
e = d.setdefault("expect", {})
e.setdefault("changed", True)
e.setdefault("files", [])
print(json.dumps(d))' "$SPEC")" || die "$spec_json"

field() { printf '%s' "$spec_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1],""))' "$1"; }
step_count() { printf '%s' "$spec_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["steps"]))'; }
step_field() { printf '%s' "$spec_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["steps"][int(sys.argv[1])].get(sys.argv[2],""))' "$1" "$2"; }

TASK="$(field task)"
REPO_REL="$(field repo)"
GATE="$(field gate)"
RETRIES="$(field retries)"
REPO="$(cd "$ROOT/$REPO_REL" 2>/dev/null && pwd)" || die "spec.repo does not resolve: $REPO_REL"
[ -d "$REPO/.git" ] || die "$REPO is not a git repository"

PROFILE="$REPO/opencode.headless.json"
[ -f "$PROFILE" ] || die "no headless profile in $REPO — run 'just sync-opencode'"

N="$(step_count)"

echo "loop: $NAME"
echo "  task   $TASK"
echo "  repo   $REPO_REL"
echo "  steps  $N"
echo "  gate   $GATE"

if [ "$DRY_RUN" = "1" ]; then
    for i in $(seq 0 $((N - 1))); do
        printf '  step %d: agent=%s\n' "$((i + 1))" "$(step_field "$i" agent)"
    done
    echo "loop: dry run, nothing executed"
    exit 0
fi

# ── cost accounting: OpenRouter usage delta across the whole run ────────────
usage_now() {
    [ -n "${OPENROUTER_API_KEY:-}" ] || { echo ""; return; }
    curl -s -m 20 -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        https://openrouter.ai/api/v1/key 2>/dev/null |
        python3 -c 'import json,sys
try: print(json.load(sys.stdin)["data"]["usage"])
except Exception: print("")' 2>/dev/null
}
USAGE_START="$(usage_now)"
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SECONDS=0

# The gate proves the repo is healthy, not that the task was done: `just check`
# passes on an unchanged tree, so a step that read everything and then gave up
# would report green. Snapshot the tree and verify an effect afterwards.
TREE_BEFORE="$(cd "$REPO" && git status --porcelain | sort)"

# ── run a step ─────────────────────────────────────────────────────────────
CONFIG_CONTENT="$(cat "$PROFILE")"
STEP_LOG="$(mktemp)"
trap 'rm -f "$STEP_LOG"' EXIT

# Each step is its own process, which is what gives the review step a genuinely
# fresh view of the diff. The cost is that nothing carries forward: a step that
# reports findings "in your reply" hands them to no one. `{{previous}}` in a
# prompt is replaced with the prior step's final output, making the handoff
# explicit and per-step rather than implicit and total.
PREVIOUS=""

run_step() {
    local agent="$1" prompt="$2" label="$3"
    prompt="${prompt//\{\{previous\}\}/$PREVIOUS}"
    prompt="${prompt//\{\{task\}\}/$TASK}"
    echo
    echo "── $label · @$agent ──"
    OPENCODE_CONFIG_CONTENT="$CONFIG_CONTENT" \
        opencode run --dir "$REPO" --agent "$agent" "$prompt" 2>&1 | tee "$STEP_LOG"
    local rc="${PIPESTATUS[0]}"
    # Strip ANSI and opencode's tool-trace glyphs so the next step receives
    # prose rather than terminal decoration.
    PREVIOUS="$(sed -e 's/\x1b\[[0-9;]*m//g' -e 's/^[→✱⚙✗!$] *//' "$STEP_LOG" | tail -200)"
    # A subagent silently falls back to the default agent, which would run the
    # wrong model under the wrong permissions and still look like success.
    if grep -q "not a primary agent" "$STEP_LOG"; then
        die "agent '$agent' is a subagent; opencode run cannot bind it.
  Set 'mode: all' in opencode/agent/$agent.md and re-sync."
    fi
    return "$rc"
}

STATUS="ok"
FAILED_AT=""

for i in $(seq 0 $((N - 1))); do
    agent="$(step_field "$i" agent)"
    prompt="$(step_field "$i" prompt)"
    if ! run_step "$agent" "$prompt" "step $((i + 1))/$N"; then
        STATUS="step-failed"; FAILED_AT="step $((i + 1)) (@$agent)"
        break
    fi
done

# ── gate, then one repair attempt ──────────────────────────────────────────
GATE_OUT=""
if [ "$STATUS" = "ok" ] && [ -n "$GATE" ]; then
    echo
    echo "── gate · $GATE ──"
    if GATE_OUT="$(cd "$REPO" && eval "$GATE" 2>&1)"; then
        echo "gate: green"
    else
        echo "gate: RED"
        printf '%s\n' "$GATE_OUT" | tail -20
        if [ "$RETRIES" -ge 1 ]; then
            last=$((N - 1))
            repair_agent="$(step_field "$last" agent)"
            run_step "$repair_agent" \
"The repository gate failed after your change. Fix the cause; do not weaken or skip the gate.

Command: $GATE

Output:
$(printf '%s' "$GATE_OUT" | tail -60)" "repair 1/$RETRIES"
            echo
            echo "── gate (retry) ──"
            if GATE_OUT="$(cd "$REPO" && eval "$GATE" 2>&1)"; then
                echo "gate: green after repair"
                STATUS="ok-after-repair"
            else
                echo "gate: STILL RED — stopping"
                STATUS="gate-red"
            fi
        else
            STATUS="gate-red"
        fi
    fi
fi

# ── did the task actually do anything? ─────────────────────────────────────
# The gate proves the repo is healthy, not that the work happened: `just check`
# passes on an untouched tree, so a step that read everything and then gave up
# reports green. The first real run of this loop did exactly that.
EXPECT_CHANGED="$(printf '%s' "$spec_json" | python3 -c 'import json,sys; print("1" if json.load(sys.stdin)["expect"]["changed"] else "0")')"
mapfile -t EXPECT_FILES < <(printf '%s' "$spec_json" | python3 -c 'import json,sys
for f in json.load(sys.stdin)["expect"]["files"]: print(f)')

if [ "$STATUS" = "ok" ] || [ "$STATUS" = "ok-after-repair" ]; then
    TREE_AFTER="$(cd "$REPO" && git status --porcelain | sort)"
    if [ "$EXPECT_CHANGED" = "1" ] && [ "$TREE_AFTER" = "$TREE_BEFORE" ]; then
        echo
        echo "loop: gate is green but the working tree is unchanged."
        echo "      The steps ran and produced no effect — that is a failure, not a pass."
        STATUS="no-effect"
    fi
    for want in "${EXPECT_FILES[@]}"; do
        [ -n "$want" ] || continue
        if [ ! -s "$REPO/$want" ]; then
            echo
            echo "loop: expected output missing or empty — $want"
            STATUS="missing-output"
        fi
    done
fi

# ── record ─────────────────────────────────────────────────────────────────
ELAPSED="$SECONDS"
# OpenRouter's usage figure lags the request by seconds, so reading it the
# instant a run ends yields 0.0000 — a number that looks like a measurement and
# is not one. Poll briefly, and record "pending" rather than a false zero.
COST="-"
if [ -n "$USAGE_START" ]; then
    COST="pending"
    for _ in 1 2 3 4 5 6; do
        sleep 5
        USAGE_END="$(usage_now)"
        [ -n "$USAGE_END" ] || continue
        if [ "$USAGE_END" != "$USAGE_START" ]; then
            COST="$(python3 -c 'import sys; print(f"{float(sys.argv[2])-float(sys.argv[1]):.4f}")' "$USAGE_START" "$USAGE_END")"
            break
        fi
    done
fi
MODELS="$(printf '%s' "$spec_json" | python3 -c '
import json,sys
print(",".join(s["agent"] for s in json.load(sys.stdin)["steps"]))')"
DIFF="$(cd "$REPO" && git status --porcelain | wc -l | tr -d " ")"

mkdir -p "$(dirname "$RUNLOG")"
if [ ! -f "$RUNLOG" ]; then
    cat >"$RUNLOG" <<'HEADER'
# Loop runs

Appended by `just loop` (enkinex-aiops `scripts/loop.sh`). Cost is the
OpenRouter usage delta across the whole run, so it includes every step.
`files` counts the working-tree entries the run left dirty — the loop never
commits, pushes or opens a PR.

| Started (UTC) | Task | Repo | Agents | Status | Gate | Elapsed | Cost (USD) | files |
|---|---|---|---|---|---|---|---|---|
HEADER
fi
printf '| %s | %s | %s | %s | %s | %s | %ss | %s | %s |\n' \
    "$STARTED" "$NAME" "$REPO_REL" "$MODELS" "$STATUS" \
    "${GATE:-none}" "$ELAPSED" "$COST" "$DIFF" >>"$RUNLOG"

echo
echo "── run recorded ──"
echo "  status   $STATUS${FAILED_AT:+ at $FAILED_AT}"
echo "  elapsed  ${ELAPSED}s"
echo "  cost     \$$COST"
echo "  dirty    $DIFF file(s) — review, then commit yourself"
echo
echo "loop: stopping at the human gate. Pushing and opening a PR are yours;"
echo "      the headless profile denies them to this runner."

case "$STATUS" in
    ok | ok-after-repair) exit 0 ;;
    *) exit 1 ;;
esac
