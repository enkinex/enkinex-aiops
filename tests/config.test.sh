#!/usr/bin/env bash
# Regression suite for the permission posture as opencode actually resolves it.
#
# Reading opencode.jsonc is not enough: matching is last-match-wins, a merged
# overlay can silently re-open a rule, and an agent's own frontmatter takes
# precedence over the baseline. These cases assert the resolved posture, which
# is the only thing that governs anything.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

command -v opencode >/dev/null || { echo "opencode not on PATH — skipping"; exit 0; }

# resolved <agent-block> — prints "pattern<TAB>action" lines for bash rules.
resolve() {
    local env_content="${1:-}"
    OPENCODE_CONFIG_CONTENT="$env_content" timeout 120 opencode agent list 2>/dev/null |
        awk '/^build \(primary\)/{f=1} /^compaction \(primary\)/{f=0} f' |
        node -e '
      let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
        const rules = (s.match(/\{[^{}]*?"permission":[^{}]*?\}/gs) || [])
          .map(r => { try { return JSON.parse(r); } catch { return null; } })
          .filter(r => r && r.permission === "bash");
        for (const r of rules) console.log(`${r.pattern}\t${r.action}`);
      });'
}

action_of() { awk -F'\t' -v p="$2" '$1 == p {print $2}' <<<"$1" | tail -1; }

expect_action() {
    local table="$1" pattern="$2" want="$3"
    local got; got="$(action_of "$table" "$pattern")"
    got="${got:-<absent>}"
    [ "$got" = "$want" ] && ok "$pattern -> $want" || no "$pattern -> $want" "got $got"
}

# resolved_action <table> <command> — the verdict a whole command lands on:
# the LAST pattern in the table that matches it. Measured against opencode
# 1.18.29 on 2026-09-05, driving one bash call through a local provider: with
# `probe view*: allow` written above `probe*: deny`, `probe view hello` was
# refused; with the deny written first, the same command ran. Specificity does
# not enter into it — only position.
resolved_action() {
    local pattern action out=""
    while IFS=$'\t' read -r pattern action; do
        [ -n "$pattern" ] || continue
        # shellcheck disable=SC2254  # $pattern is the glob, deliberately
        case "$2" in $pattern) out="$action" ;; esac
    done <<<"$1"
    printf '%s' "${out:-<none>}"
}

expect_resolved() {
    local got; got="$(resolved_action "$1" "$2")"
    [ "$got" = "$3" ] && ok "\`$2\` -> $3" || no "\`$2\` -> $3" "got $got"
}

section "interactive posture (repo opencode.jsonc)"
INTERACTIVE="$(resolve "")"
if [ -z "$INTERACTIVE" ]; then
    no "resolved the interactive posture" "opencode agent list produced no rules"
    summary
fi
expect_action "$INTERACTIVE" 'git push --force*' deny
expect_action "$INTERACTIVE" 'git push -f*'      deny
expect_action "$INTERACTIVE" 'git reset --hard*' deny
# ADR-0006 opened Issues per verb. The catch-all deny stays, so a subcommand
# GitHub adds tomorrow arrives denied rather than inheriting an allow — and
# `delete`/`transfer` are denied by name as well as by it, because the two
# that destroy the record should fail a grep, not a precedence rule.
expect_action "$INTERACTIVE" 'gh issue*'          deny
expect_action "$INTERACTIVE" 'gh issue delete*'   deny
expect_action "$INTERACTIVE" 'gh issue transfer*' deny
expect_action "$INTERACTIVE" 'gh issue view*'     allow
expect_action "$INTERACTIVE" 'gh issue list*'     allow
expect_action "$INTERACTIVE" 'gh issue create*'   ask
expect_action "$INTERACTIVE" 'gh issue comment*'  ask
expect_action "$INTERACTIVE" 'gh issue edit*'     ask
# The three surfaces ADR-0006 explicitly did NOT open. Asserted together so a
# future reversal by analogy fails here rather than in a public repository.
expect_action "$INTERACTIVE" 'gh workflow*'      deny
expect_action "$INTERACTIVE" 'gh project*'       deny
expect_action "$INTERACTIVE" 'gh run*'           deny
expect_action "$INTERACTIVE" 'gh release*'       deny
expect_action "$INTERACTIVE" 'kcl *'             allow
expect_action "$INTERACTIVE" 'just check*'       allow
expect_action "$INTERACTIVE" 'git commit*'       ask

# `just *` as a blanket allow would grant everything the rules above deny,
# because a Justfile recipe runs arbitrary shell from inside the repo.
if [ "$(action_of "$INTERACTIVE" 'just *')" = "allow" ]; then
    no "no blanket 'just *' allow" "just * is allowed, which re-opens every denied command"
else
    ok "no blanket 'just *' allow"
fi

section "ADR-0006 §2 as commands resolve, not as patterns are declared"
# The cases above read what a rule declares. A rule nothing ever reaches
# declares the same thing as one that governs, and from 79416a4 (2026-08-16)
# that was the difference: `gh issue*: deny` sat below the per-verb entries, so
# every `gh issue` command resolved to deny and ADR-0006's table was
# decoration. These cases resolve whole commands instead.
expect_resolved "$INTERACTIVE" 'gh issue view 42'                   allow
expect_resolved "$INTERACTIVE" 'gh issue list --state open'         allow
expect_resolved "$INTERACTIVE" 'gh issue create --title x'          ask
expect_resolved "$INTERACTIVE" 'gh issue comment 42 --body x'       ask
expect_resolved "$INTERACTIVE" 'gh issue edit 42 --add-label bug'   ask
expect_resolved "$INTERACTIVE" 'gh issue delete 42'                 deny
expect_resolved "$INTERACTIVE" 'gh issue transfer 42 enkinex/other' deny
# The subcommand GitHub adds tomorrow: matched by the catch-all and nothing
# else, which is the only reason the catch-all is worth keeping.
expect_resolved "$INTERACTIVE" 'gh issue pin 42'                    deny

section "headless profile (opencode.headless.json)"
HEADLESS="$(resolve "$(cat "$ROOT/opencode.headless.json")")"
if [ -z "$HEADLESS" ]; then
    no "resolved the headless posture" "opencode agent list produced no rules"
    summary
fi
# The whole point of the profile: `ask` has no meaning with no human attached,
# so behaviour must be identical with and without --auto.
ASKS="$(awk -F'\t' '$2 == "ask"' <<<"$HEADLESS" | wc -l)"
[ "$ASKS" -eq 0 ] && ok "no ask rules remain" ||
    no "no ask rules remain" "$ASKS still ask: $(awk -F'\t' '$2=="ask"{printf "%s ", $1}' <<<"$HEADLESS")"

expect_action "$HEADLESS" '*'               deny
expect_action "$HEADLESS" 'git commit*'     allow
expect_action "$HEADLESS" 'git add *'       allow
expect_action "$HEADLESS" 'git push*'       deny
expect_action "$HEADLESS" 'gh pr create*'   deny
expect_action "$HEADLESS" 'gh pr merge*'    deny
# An unattended run must not file a public artefact in the org's name.
#
# Each write verb is denied by NAME as well as by the `gh issue*` catch-all
# that follows it. Under last-match-wins the catch-all is what resolves them,
# so the named entries are redundancy on purpose: a denial nobody can grep for
# is one nobody checks.
expect_action "$HEADLESS" 'gh issue*'         deny
expect_action "$HEADLESS" 'gh issue create*'  deny
expect_action "$HEADLESS" 'gh issue comment*' deny
expect_action "$HEADLESS" 'gh issue edit*'    deny
expect_action "$HEADLESS" 'git rebase*'     deny

section "headless profile reaches the loop agents"
# Regression: the profile resolved correctly for `build` but not for the agents
# the loop actually runs, because their frontmatter is merged last. Three loop
# runs failed on denied mkdir before this was found.
resolve_agent() {
    OPENCODE_CONFIG_CONTENT="$(cat "$ROOT/opencode.headless.json")" timeout 120 opencode agent list 2>/dev/null |
        awk -v a="^$1" '$0 ~ a {f=1; next} /^[a-z-]+ \((subagent|primary|all)\)/{f=0} f' |
        node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const rules=(s.match(/\{[^{}]*?"permission":[^{}]*?\}/gs)||[])
          .map(r=>{try{return JSON.parse(r)}catch{return null}}).filter(r=>r&&r.permission==="bash");
        for (const r of rules) console.log(`${r.pattern}\t${r.action}`);
      });'
}
DW="$(resolve_agent docs-writer)"
if [ -z "$DW" ]; then
    no "resolved docs-writer" "no rules parsed"
else
    STARS="$(awk -F'\t' '$1 == "*" {print $2}' <<<"$DW" | sort -u | tr '\n' ' ')"
    [ "$(tr -d ' ' <<<"$STARS")" = "deny" ] && ok "docs-writer catch-all is deny only" ||
        no "docs-writer catch-all is deny only" "got: $STARS"
    expect_action "$DW" 'mkdir*' allow
    expect_action "$DW" 'ls*' allow
fi

section "agents load"
# Only that the project config loads at all — `opencode agent list` truncates
# its output when piped (observed dropping the last few agents), so an
# exhaustive name match against it is unreliable. The inventory itself is
# asserted structurally in agents.test.sh, against the files.
LISTED="$(timeout 120 opencode agent list 2>/dev/null | grep -oE '^[a-z-]+' || true)"
if grep -qx "build-kcl" <<<"$LISTED"; then
    ok "project agents load from .opencode/agent"
else
    no "project agents load from .opencode/agent" "build-kcl not listed"
fi

# The loop agents must be bindable by `opencode run --agent`, which silently
# falls back to the default agent for a `mode: subagent` target.
for a in build-kcl docs-writer explore-enkinex review-standard plan-author; do
    m="$(sed -n 's/^mode: *//p' "$ROOT/opencode/agent/$a.md" | head -1)"
    [ "$m" = "all" ] && ok "$a is bindable headlessly (mode=all)" ||
        no "$a is bindable headlessly" "mode=$m; opencode run would silently use the default agent"
done

summary
