#!/usr/bin/env bash
# Regression suite for scripts/loop.sh.
#
# The runner is exercised against a STUB `opencode` on PATH, so every case is
# deterministic, free and instant. That matters more here than elsewhere: the
# first real run of this loop reported success while producing nothing, and a
# suite that needs a live model to catch that would never be run often enough
# to catch it again.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── a fake repo the runner can drive ───────────────────────────────────────
REPO="$WORK/enkinex-fake"
git init -q -b main "$REPO"
git -C "$REPO" remote add origin git@github.com:enkinex/enkinex-fake.git
git -C "$REPO" config user.email t@enkinex.invalid
git -C "$REPO" config user.name t
echo '{"permission":{"bash":{"*":"deny"}}}' >"$REPO/opencode.headless.json"
echo seed >"$REPO/seed.txt"
git -C "$REPO" add seed.txt opencode.headless.json >/dev/null
git -C "$REPO" commit -q -m "chore: seed" -m "No-Plan-Ref: fixture" >/dev/null 2>&1

# ── stub opencode: records its prompt, optionally creates a file ───────────
BIN="$WORK/bin"; mkdir -p "$BIN"
cat >"$BIN/opencode" <<'STUB'
#!/usr/bin/env bash
# args: run --dir <repo> --agent <agent> <prompt>
repo=""; agent=""; prompt=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) repo="$2"; shift 2 ;;
    --agent) agent="$2"; shift 2 ;;
    run) shift ;;
    *) prompt="$1"; shift ;;
  esac
done
# Stands in for the real binary's blocking read on stdin. Reaches EOF at once
# when the caller closed stdin; blocks forever when it inherited an open one.
[ "${STUB_READ_STDIN:-0}" = "1" ] && cat >/dev/null
mkdir -p "$STUB_OUT"
printf '%s' "$prompt" > "$STUB_OUT/prompt.$agent"
echo "STUB ran agent=$agent"
[ "${STUB_FALLBACK:-0}" = "1" ] && echo 'agent "x" is a subagent, not a primary agent. Falling back to default agent'
if [ -n "${STUB_WRITE:-}" ]; then
  mkdir -p "$(dirname "$repo/$STUB_WRITE")"
  echo "written by stub" > "$repo/$STUB_WRITE"
fi
echo "OUTPUT-MARKER-$agent"
exit "${STUB_RC:-0}"
STUB
chmod +x "$BIN/opencode"
export PATH="$BIN:$PATH"
export STUB_OUT="$WORK/stub"
# Never append to the committed run log.
export LOOP_RUNLOG="$WORK/runs.md"
# The runner reads OpenRouter usage; keep it offline and deterministic.
unset OPENROUTER_API_KEY

TASKS="$ROOT/loop/tasks"
spec() { cat >"$TASKS/__test-$1.yaml"; }
cleanup_specs() { rm -f "$TASKS"/__test-*.yaml; }
trap 'rm -rf "$WORK"; cleanup_specs' EXIT

run_loop() { (cd "$ROOT" && bash scripts/loop.sh "__test-$1" ${2:-} 2>&1); }

section "spec validation"
spec bad <<'EOF'
task: missing repo and steps
EOF
OUT="$(run_loop bad)"; assert_contains "missing keys are rejected" "$OUT" "missing required key"

spec nosteps <<EOF
task: t
repo: $(realpath --relative-to="$ROOT" "$REPO")
steps: []
EOF
OUT="$(run_loop nosteps)"; assert_contains "empty steps rejected" "$OUT" "non-empty list"

REL="$(realpath --relative-to="$ROOT" "$REPO")"

section "dry run executes nothing"
spec dry <<EOF
task: t
repo: $REL
gate: "true"
steps:
  - agent: build-kcl
    prompt: hello
EOF
rm -rf "$STUB_OUT"
OUT="$(run_loop dry --dry-run)"
assert_contains "dry run lists steps" "$OUT" "step 1: agent=build-kcl"
[ ! -d "$STUB_OUT" ] && ok "dry run did not invoke opencode" || no "dry run did not invoke opencode"

section "placeholders are substituted"
spec subst <<EOF
task: THE-TASK-TEXT
repo: $REL
gate: "true"
expect:
  changed: false
steps:
  - agent: explore-enkinex
    prompt: first step
  - agent: docs-writer
    prompt: |
      task was {{task}}
      previous said:
      {{previous}}
EOF
rm -rf "$STUB_OUT"; run_loop subst >/dev/null
P2="$(cat "$STUB_OUT/prompt.docs-writer" 2>/dev/null || true)"
assert_contains "{{task}} substituted"     "$P2" "THE-TASK-TEXT"
assert_contains "{{previous}} substituted" "$P2" "OUTPUT-MARKER-explore-enkinex"
case "$P2" in *'{{previous}}'*) no "no placeholder left behind" ;; *) ok "no placeholder left behind" ;; esac

section "effect verification"
# A green gate on an untouched tree is the exact false pass the first real run
# produced. It must be a failure.
spec noeffect <<EOF
task: t
repo: $REL
gate: "true"
steps:
  - agent: build-kcl
    prompt: do nothing
EOF
rm -rf "$STUB_OUT"; OUT="$(run_loop noeffect)"
assert_contains "unchanged tree is a failure" "$OUT" "no effect"
assert_contains "status is no-effect"          "$OUT" "no-effect"
(cd "$ROOT" && bash scripts/loop.sh "__test-noeffect" >/dev/null 2>&1) && no "no-effect exits non-zero" || ok "no-effect exits non-zero"

spec missing <<EOF
task: t
repo: $REL
gate: "true"
expect:
  changed: false
  files:
    - docs/never-written.md
steps:
  - agent: build-kcl
    prompt: do nothing
EOF
rm -rf "$STUB_OUT"; OUT="$(run_loop missing)"
assert_contains "declared output must exist" "$OUT" "missing or empty"

spec produced <<EOF
task: t
repo: $REL
gate: "true"
expect:
  files:
    - docs/made.md
steps:
  - agent: build-kcl
    prompt: write it
EOF
rm -rf "$STUB_OUT"; STUB_WRITE="docs/made.md" OUT="$(STUB_WRITE=docs/made.md run_loop produced)"
assert_contains "a real effect passes" "$OUT" "status   ok"
rm -rf "${REPO:?}/docs"

section "failure modes"
spec fallback <<EOF
task: t
repo: $REL
gate: "true"
steps:
  - agent: build-kcl
    prompt: x
EOF
rm -rf "$STUB_OUT"; OUT="$(STUB_FALLBACK=1 run_loop fallback)"
assert_contains "subagent fallback aborts the run" "$OUT" "cannot bind it"

spec stepfail <<EOF
task: t
repo: $REL
gate: "true"
steps:
  - agent: build-kcl
    prompt: x
EOF
rm -rf "$STUB_OUT"; OUT="$(STUB_RC=3 run_loop stepfail)"
assert_contains "a failing step is recorded" "$OUT" "step-failed"

section "a step never inherits a blocking stdin"
# AIOPS-11. `opencode run` blocks on stdin when stdin is not a TTY and never
# reaches EOF: no output, forever. Interactively it is invisible, because a
# terminal's stdin is a TTY — so this only bites where nobody is watching, which
# is every unattended run the runner exists for.
#
# The case gives loop.sh a stdin that is open and will never deliver EOF, and a
# stub that reads stdin before answering. If the runner passes that stdin down,
# the stub blocks and the run has to be killed — the exact reported symptom.
spec stdinblock <<EOF
task: t
repo: $REL
gate: "true"
expect:
  changed: false
steps:
  - agent: build-kcl
    prompt: x
EOF
FIFO="$WORK/never-eof"
mkfifo "$FIFO"
# Held open read-write, so the reader never sees EOF and never gets data.
exec 9<>"$FIFO"
rm -rf "$STUB_OUT"
OUT="$(cd "$ROOT" && STUB_READ_STDIN=1 timeout 20 bash scripts/loop.sh "__test-stdinblock" 2>&1 <&9)"
RC=$?
exec 9>&-
if [ "$RC" = 124 ]; then
    no "a step completes with a never-EOF stdin" \
       "the runner passed its own stdin to opencode; every unattended run hangs on step 1"
else
    ok "a step completes with a never-EOF stdin"
fi
assert_contains "the step actually ran" "$OUT" "OUTPUT-MARKER-build-kcl"

section "gate failure triggers exactly one repair"
spec repair <<EOF
task: t
repo: $REL
gate: "false"
retries: 1
steps:
  - agent: build-kcl
    prompt: x
EOF
rm -rf "$STUB_OUT"; OUT="$(run_loop repair)"
assert_contains "gate red is reported"  "$OUT" "gate: RED"
assert_contains "one repair attempt"    "$OUT" "repair 1/1"
assert_contains "stops when still red"  "$OUT" "STILL RED"

section "the human gate"
assert_contains "run reports it stops at the gate" "$OUT" "stopping at the human gate"

summary
