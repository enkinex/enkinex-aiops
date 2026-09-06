#!/usr/bin/env just --justfile

# Sibling repos receiving the shared layer (ADR-0005). enkinex-aiops is not
# in this list: it is synced separately by the sync-self step below, because
# its opencode.jsonc and AGENTS.shared.md are the sources, not copies.
# enkinex-pm is private and takes the layer for the hooks and the guard, not
# for publication (PM-07).
REPOS := "enkinex-odcs enkinex-odps enkinex-org-website enkinex-databricks enkinex-okf enkinex-ossie enkinex-pm"

# Directories under opencode/ distributed to each repo's .opencode/.
# NOTE: opencode discovers custom tools at .opencode/tools (plural only) —
# .opencode/tool is never read. agent/command/plugin/skill accept both
# spellings; the plural form is used throughout for consistency.
ARTEFACT_DIRS := "agent command tools plugin skills"

default:
    @just --list

# Run opencode in a repo under the headless deny-list profile (no `ask` actions)
headless repo *args:
    @{{justfile_directory()}}/scripts/opencode-headless.sh "{{repo}}" {{args}}

# Run a task spec from loop/tasks/ end to end (steps -> gate -> one repair)
loop task *args:
    @{{justfile_directory()}}/scripts/loop.sh "{{task}}" {{args}}

# Show the most recent loop runs
loop-status:
    #!/usr/bin/env bash
    log="{{justfile_directory()}}/loop/runs.md"
    [ -f "$log" ] || { echo "no runs recorded yet"; exit 0; }
    head -8 "$log"; tail -n 10 "$log"

# Append a cost snapshot to loop/loop-log.md (OpenRouter + opencode cross-check)
ledger:
    @{{justfile_directory()}}/scripts/ledger.sh

# Golden-set regression over the executable governance artefacts.
#
# A suite that asserts nothing prints `0 passed` and exits 0, which reads as a
# clean run. That is what CI has been getting from tests/config.test.sh since it
# was written: opencode is not installed there, so its 49 assertions — including
# the only mechanical backing for the ADR-0006 permission table — have never run
# on a pull request. Suites that ran nothing are named at the end here.
#
# `just test strict` additionally refuses them, and that is the form `check`
# uses: check runs where opencode is installed, so a whole-suite skip there is a
# broken environment. Plain `just test` still exits 0 on a skip, because CI calls
# it and failing would force the install decision AIOPS-24 does not take.
test strict="":
    #!/usr/bin/env bash
    set -uo pipefail
    cd "{{justfile_directory()}}"
    report="$(mktemp)"
    trap 'rm -f "$report"' EXIT
    rc=0
    skipped=0
    empty=()
    for suite in tests/*.test.sh; do
        echo "═══ $suite ═══"
        : >"$report"
        ENKINEX_TEST_REPORT="$report" bash "$suite" || rc=1
        # A suite that died before summary() leaves the report empty. It ran
        # nothing measurable either way, and rc is already 1.
        read -r p f s <"$report" 2>/dev/null || { p=0; f=0; s=0; }
        skipped=$((skipped + ${s:-0}))
        [ "${p:-0}" -eq 0 ] && empty+=("$suite")
    done

    [ "$skipped" -gt 0 ] && echo "" && echo "$skipped assertion(s) skipped"
    if [ "${#empty[@]}" -gt 0 ]; then
        echo ""
        echo "asserted nothing: ${empty[*]}"
        # `check` runs where opencode is installed, so a whole-suite skip there
        # is a broken environment rather than a policy.
        [ -n "{{strict}}" ] && { echo "refusing: a suite that asserts nothing is not a passing suite"; rc=1; }
    fi
    exit "$rc"

# The gate every change to this repo must pass
check: (test "strict") verify-opencode

# Install the shared opencode layer into every sibling repo
sync-opencode:
    #!/usr/bin/env bash
    set -euo pipefail
    SRC="{{justfile_directory()}}"
    ROOT="{{justfile_directory()}}/.."
    source "$SRC/scripts/shared-layer.sh"

    render_self "$SRC"
    echo "synced -> enkinex-aiops (self)"

    for repo in {{REPOS}}; do
        dest="$ROOT/$repo"
        [ -d "$dest/.git" ] || { echo "SKIP $repo (not a repo)"; continue; }
        [ -f "$dest/AGENTS.md" ] || { echo "SKIP $repo (no AGENTS.md to inject into)"; continue; }

        cp "$SRC/opencode.jsonc" "$dest/opencode.jsonc"
        cp "$SRC/opencode.headless.json" "$dest/opencode.headless.json"
        inject_shared "$SRC/AGENTS.shared.md" "$dest/AGENTS.md"
        write_claude_md "$dest/CLAUDE.md"
        install_hooks "$SRC/githooks" "$dest"
        install_policy "$SRC" "$dest"
        install_mcp "$SRC" "$dest"
        # AGENTS.shared.md is no longer distributed as a file: its content now
        # lives inside AGENTS.md, which every harness reads (opencode, Codex)
        # or imports (Claude Code via CLAUDE.md).
        rm -f "$dest/AGENTS.shared.md"

        mkdir -p "$dest/.opencode"
        for d in {{ARTEFACT_DIRS}}; do
            if [ -d "$SRC/opencode/$d" ]; then
                rm -rf "${dest:?}/.opencode/$d"
                cp -r "$SRC/opencode/$d" "$dest/.opencode/$d"
            fi
        done
        echo "synced -> $repo"
    done

# Report drift between the sources here and each repo's installed copy.
#
# A REPOS entry with no clone used to `continue` in silence, so a workspace
# holding none of the siblings printed "shared layer in sync across
# enkinex-aiops and all sibling repos" and exited 0 — a claim about seven
# repositories, made after examining none of them. The install half of the same
# list has always said `SKIP $repo (not a repo)`; this half now reports it too,
# and refuses. The cost is deliberate: a partial workspace stops passing
# `just check`, because the sentence at the end is about all seven.
#
# ENKINEX_ROOT exists so that state is reachable from a test rather than only
# by deleting a sibling.
verify-opencode:
    #!/usr/bin/env bash
    set -uo pipefail
    SRC="{{justfile_directory()}}"
    ROOT="${ENKINEX_ROOT:-{{justfile_directory()}}/..}"
    source "$SRC/scripts/shared-layer.sh"
    rc=0
    examined=0
    total=0

    check_agents_block "$SRC/AGENTS.shared.md" "$SRC/AGENTS.md" "enkinex-aiops" || rc=1
    check_claude_md "$SRC/CLAUDE.md" "enkinex-aiops" || rc=1
    check_hooks "$SRC/githooks" "$SRC" "enkinex-aiops" || rc=1
    check_policy "$SRC" "$SRC" "enkinex-aiops" || rc=1
    check_mcp "$SRC" "$SRC" "enkinex-aiops" || rc=1

    for repo in {{REPOS}}; do
        total=$((total + 1))
        dest="$ROOT/$repo"
        [ -d "$dest/.git" ] || { echo "MISSING: $repo is not cloned at $ROOT — nothing was compared"; rc=1; continue; }
        examined=$((examined + 1))
        cmp -s "$SRC/opencode.jsonc" "$dest/opencode.jsonc" || { echo "DRIFT: $repo/opencode.jsonc"; rc=1; }
        cmp -s "$SRC/opencode.headless.json" "$dest/opencode.headless.json" || { echo "DRIFT: $repo/opencode.headless.json"; rc=1; }
        check_agents_block "$SRC/AGENTS.shared.md" "$dest/AGENTS.md" "$repo" || rc=1
        check_claude_md "$dest/CLAUDE.md" "$repo" || rc=1
        check_hooks "$SRC/githooks" "$dest" "$repo" || rc=1
        check_policy "$SRC" "$dest" "$repo" || rc=1
        check_mcp "$SRC" "$dest" "$repo" || rc=1
        [ -e "$dest/AGENTS.shared.md" ] && { echo "DRIFT: $repo/AGENTS.shared.md still present (content moved into AGENTS.md)"; rc=1; }
        for d in {{ARTEFACT_DIRS}}; do
            if [ -d "$SRC/opencode/$d" ] && ! diff -rq "$SRC/opencode/$d" "$dest/.opencode/$d" >/dev/null 2>&1; then
                echo "DRIFT: $repo/.opencode/$d/"
                rc=1
            fi
        done
    done
    # Named counts, so the line cannot claim more than was looked at.
    [ "$rc" -eq 0 ] && echo "shared layer in sync across enkinex-aiops and all $examined sibling repos"
    [ "$examined" -lt "$total" ] && echo "$((total - examined)) of $total sibling repo(s) were never examined"
    exit "$rc"
