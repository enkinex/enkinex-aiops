#!/usr/bin/env just --justfile

# Sibling repos receiving the shared layer (ADR-0005). enkinex-aiops is not
# in this list: it is synced separately by the sync-self step below, because
# its opencode.jsonc and AGENTS.shared.md are the sources, not copies.
REPOS := "enkinex-odcs enkinex-odps enkinex-org-website enkinex-databricks enkinex-okf enkinex-ossie"

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

# Golden-set regression over the executable governance artefacts
test:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    rc=0
    for suite in tests/*.test.sh; do
        echo "═══ $suite ═══"
        bash "$suite" || rc=1
    done
    exit "$rc"

# The gate every change to this repo must pass
check: test verify-opencode

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

# Report drift between the sources here and each repo's installed copy
verify-opencode:
    #!/usr/bin/env bash
    set -uo pipefail
    SRC="{{justfile_directory()}}"
    ROOT="{{justfile_directory()}}/.."
    source "$SRC/scripts/shared-layer.sh"
    rc=0

    check_agents_block "$SRC/AGENTS.shared.md" "$SRC/AGENTS.md" "enkinex-aiops" || rc=1
    check_claude_md "$SRC/CLAUDE.md" "enkinex-aiops" || rc=1
    check_hooks "$SRC/githooks" "$SRC" "enkinex-aiops" || rc=1
    check_policy "$SRC" "$SRC" "enkinex-aiops" || rc=1
    check_mcp "$SRC" "$SRC" "enkinex-aiops" || rc=1

    for repo in {{REPOS}}; do
        dest="$ROOT/$repo"
        [ -d "$dest/.git" ] || continue
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
    [ "$rc" -eq 0 ] && echo "shared layer in sync across enkinex-aiops and all sibling repos"
    exit "$rc"
