// enkinex policy guard, opencode adapter — GENERATED from enkinex-aiops
// opencode/plugin/enkinex-guard.js. Do not edit here; change the source and
// run `just sync-opencode`.
//
// Adapter only: every rule lives in .agents/policy/guard.mjs, which Claude Code
// and Codex call directly as a PreToolUse hook. This translates opencode's
// tool.execute.before into the same stdin/stdout contract, and turns a deny
// into the thrown error opencode uses to abort a tool call.

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";

export const EnkinexGuard = async ({ directory, worktree }) => {
  const root = worktree || directory || process.cwd();
  const guard = join(root, ".agents", "policy", "guard.mjs");

  return {
    "tool.execute.before": async (input, output) => {
      if (!existsSync(guard)) return;

      const payload = JSON.stringify({
        hook_event_name: "PreToolUse",
        tool_name: input.tool,
        tool_input: output.args ?? {},
        cwd: root,
      });

      // `node`, never process.execPath: opencode runs plugins in its own
      // embedded runtime, so process.execPath is the opencode binary and
      // spawning it would hang until the timeout and then silently allow.
      const res = spawnSync("node", [guard], {
        input: payload,
        encoding: "utf8",
        timeout: 10_000,
      });

      // Fail closed. The guard file is present, so enforcement is expected;
      // an unrunnable guard is a broken policy path, not an absent one, and
      // silently allowing here would make every rule advisory again.
      if (res.error || res.status !== 0) {
        throw new Error(
          `enkinex policy: guard could not run (${res.error?.message ?? `exit ${res.status}`}). ` +
            `Install node, or remove .agents/policy/ if this repo is not governed.`,
        );
      }

      const out = (res.stdout || "").trim();
      if (!out) return;

      let decision;
      try {
        decision = JSON.parse(out);
      } catch {
        return;
      }

      const denied =
        decision?.hookSpecificOutput?.permissionDecision === "deny" ||
        decision?.decision === "block";

      if (denied) {
        throw new Error(
          decision.hookSpecificOutput?.permissionDecisionReason ||
            decision.reason ||
            "enkinex policy: denied",
        );
      }
    },
  };
};
