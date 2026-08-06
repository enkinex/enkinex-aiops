#!/usr/bin/env bash
# Shared-layer distribution helpers, sourced by the enkinex-aiops Justfile
# (ADR-0005). The shared rules travel inside each repo's AGENTS.md as a
# delimited generated block, so every harness that reads AGENTS.md (opencode,
# Codex) or imports it (Claude Code, via CLAUDE.md) is governed identically.

BEGIN_MARK='<!-- BEGIN GENERATED: enkinex-aiops/AGENTS.shared.md — do not edit here; run "just sync-opencode" in enkinex-aiops -->'
END_MARK='<!-- END GENERATED -->'

CLAUDE_MD_LINE_1='<!-- Claude Code reads CLAUDE.md, not AGENTS.md. This file exists only to import it. -->'
CLAUDE_MD_LINE_2='@AGENTS.md'

# inject_shared <shared-fragment> <target AGENTS.md>
# Replaces the generated block in the target, or appends it when absent.
# Everything outside the markers is hand-owned and left untouched.
inject_shared() {
    local shared="$1" dest="$2" tmp
    tmp="$(mktemp)"
    if grep -Fxq "$BEGIN_MARK" "$dest"; then
        awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v s="$shared" '
            $0 == b { print; while ((getline line < s) > 0) print line; close(s); skip = 1; next }
            $0 == e { print; skip = 0; next }
            !skip
        ' "$dest" >"$tmp"
    else
        {
            cat "$dest"
            printf '\n%s\n' "$BEGIN_MARK"
            cat "$shared"
            printf '%s\n' "$END_MARK"
        } >"$tmp"
    fi
    mv "$tmp" "$dest"
}

# extract_shared <AGENTS.md> — prints the generated block body, markers excluded.
extract_shared() {
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
        $0 == e { inblock = 0 }
        inblock { print }
        $0 == b { inblock = 1 }
    ' "$1"
}

# write_claude_md <path> — the whole Claude Code adapter: an import, no rules.
write_claude_md() {
    printf '%s\n\n%s\n' "$CLAUDE_MD_LINE_1" "$CLAUDE_MD_LINE_2" >"$1"
}

# check_agents_block <shared-fragment> <AGENTS.md> <repo label>
check_agents_block() {
    local shared="$1" dest="$2" label="$3"
    if [ ! -f "$dest" ]; then
        echo "DRIFT: $label/AGENTS.md missing"
        return 1
    fi
    if ! grep -Fxq "$BEGIN_MARK" "$dest"; then
        echo "DRIFT: $label/AGENTS.md has no generated block"
        return 1
    fi
    if ! diff -q <(extract_shared "$dest") "$shared" >/dev/null 2>&1; then
        echo "DRIFT: $label/AGENTS.md generated block"
        return 1
    fi
    return 0
}

# check_claude_md <path> <repo label>
check_claude_md() {
    local dest="$1" label="$2"
    if ! diff -q <(printf '%s\n\n%s\n' "$CLAUDE_MD_LINE_1" "$CLAUDE_MD_LINE_2") "$dest" >/dev/null 2>&1; then
        echo "DRIFT: $label/CLAUDE.md"
        return 1
    fi
    return 0
}

# install_hooks <source githooks dir> <repo root>
# Copies the hooks and points the repo at them. git deliberately never runs
# hooks from a fresh clone, so core.hooksPath is a bootstrap that has to happen
# once per clone; there is no way around it inside git. The server-side backstop
# for clones this never touched is tracked in
# discovery/opencode/harness-agnostic-review.md §7.2.
install_hooks() {
    local src="$1" dest="$2"
    rm -rf "${dest:?}/.githooks"
    cp -r "$src" "$dest/.githooks"
    chmod +x "$dest"/.githooks/*
    git -C "$dest" config core.hooksPath .githooks
}

# install_policy <aiops root> <repo root>
# The guard plus its three pointer-only adapters. All rules live in
# .agents/policy/guard.mjs; nothing in an adapter is policy.
install_policy() {
    local src="$1" dest="$2"
    mkdir -p "$dest/.agents/policy" "$dest/.claude" "$dest/.codex"
    cp "$src/policy/guard.mjs" "$dest/.agents/policy/guard.mjs"
    cp "$src/policy/README.md" "$dest/.agents/policy/README.md"
    chmod +x "$dest/.agents/policy/guard.mjs"
    cp "$src/policy/adapters/claude-settings.json" "$dest/.claude/settings.json"
    cp "$src/policy/adapters/codex-hooks.json" "$dest/.codex/hooks.json"
}

# install_mcp <aiops root> <repo root>
# The enkinex MCP server plus the Claude Code project-scope declaration.
# Codex reads MCP servers from user-level config, which enkinex never writes
# (ADR-0005) — see mcp/README.md.
install_mcp() {
    local src="$1" dest="$2"
    mkdir -p "$dest/.agents/mcp"
    cp "$src/mcp/enkinex.mjs" "$dest/.agents/mcp/enkinex.mjs"
    cp "$src/mcp/README.md" "$dest/.agents/mcp/README.md"
    chmod +x "$dest/.agents/mcp/enkinex.mjs"
    cp "$src/mcp/adapters/mcp.json" "$dest/.mcp.json"
}

# check_mcp <aiops root> <repo root> <repo label>
check_mcp() {
    local src="$1" dest="$2" label="$3" rc=0
    cmp -s "$src/mcp/enkinex.mjs" "$dest/.agents/mcp/enkinex.mjs" ||
        { echo "DRIFT: $label/.agents/mcp/enkinex.mjs"; rc=1; }
    cmp -s "$src/mcp/README.md" "$dest/.agents/mcp/README.md" ||
        { echo "DRIFT: $label/.agents/mcp/README.md"; rc=1; }
    cmp -s "$src/mcp/adapters/mcp.json" "$dest/.mcp.json" ||
        { echo "DRIFT: $label/.mcp.json"; rc=1; }
    return "$rc"
}

# check_policy <aiops root> <repo root> <repo label>
check_policy() {
    local src="$1" dest="$2" label="$3" rc=0
    cmp -s "$src/policy/guard.mjs" "$dest/.agents/policy/guard.mjs" ||
        { echo "DRIFT: $label/.agents/policy/guard.mjs"; rc=1; }
    cmp -s "$src/policy/README.md" "$dest/.agents/policy/README.md" ||
        { echo "DRIFT: $label/.agents/policy/README.md"; rc=1; }
    cmp -s "$src/policy/adapters/claude-settings.json" "$dest/.claude/settings.json" ||
        { echo "DRIFT: $label/.claude/settings.json"; rc=1; }
    cmp -s "$src/policy/adapters/codex-hooks.json" "$dest/.codex/hooks.json" ||
        { echo "DRIFT: $label/.codex/hooks.json"; rc=1; }
    return "$rc"
}

# check_hooks <source githooks dir> <repo root> <repo label>
check_hooks() {
    local src="$1" dest="$2" label="$3"
    if ! diff -rq "$src" "$dest/.githooks" >/dev/null 2>&1; then
        echo "DRIFT: $label/.githooks/"
        return 1
    fi
    local configured
    configured="$(git -C "$dest" config --get core.hooksPath || true)"
    if [ "$configured" != ".githooks" ]; then
        echo "DRIFT: $label core.hooksPath is '${configured:-unset}', expected '.githooks' — hooks are NOT active"
        return 1
    fi
    return 0
}

# render_self <aiops root> — aiops dogfoods the layer it publishes (ADR-0005 §5).
# Its opencode.jsonc, opencode.headless.json and AGENTS.shared.md stay as the
# live sources; only the generated AGENTS.md block, CLAUDE.md and the installed
# hooks are rendered.
render_self() {
    local src="$1"
    inject_shared "$src/AGENTS.shared.md" "$src/AGENTS.md"
    write_claude_md "$src/CLAUDE.md"
    # Symlink rather than copy, matching .opencode/agent and .opencode/command:
    # the sources are live here without a second copy to keep in step.
    [ -L "$src/.githooks" ] || { rm -rf "${src:?}/.githooks"; ln -s githooks "$src/.githooks"; }
    git -C "$src" config core.hooksPath .githooks
    # Same idiom for the policy guard: symlink the live source, copy the
    # generated adapters.
    mkdir -p "$src/.agents"
    [ -L "$src/.agents/policy" ] || { rm -rf "${src:?}/.agents/policy"; ln -s ../policy "$src/.agents/policy"; }
    [ -L "$src/.agents/mcp" ] || { rm -rf "${src:?}/.agents/mcp"; ln -s ../mcp "$src/.agents/mcp"; }
    cp "$src/mcp/adapters/mcp.json" "$src/.mcp.json"
    mkdir -p "$src/.claude" "$src/.codex"
    cp "$src/policy/adapters/claude-settings.json" "$src/.claude/settings.json"
    cp "$src/policy/adapters/codex-hooks.json" "$src/.codex/hooks.json"
    # Every artefact directory that exists gets a symlink, so a new one
    # (tools/, skills/) goes live here the moment it is created.
    mkdir -p "$src/.opencode"
    for d in "$src"/opencode/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        [ -L "$src/.opencode/$name" ] || {
            rm -rf "${src:?}/.opencode/$name"
            ln -s "../opencode/$name" "$src/.opencode/$name"
        }
    done
}
