#!/usr/bin/env node
// enkinex policy guard — GENERATED from enkinex-aiops policy/guard.mjs.
// Do not edit here; change the source and run `just sync-opencode`.
//
// One policy, three harnesses. Reads a PreToolUse-shaped JSON payload on
// stdin and writes a decision on stdout, in a form both Claude Code and Codex
// understand; the opencode plugin adapter calls the same script and turns a
// deny into a thrown error.
//
// SCOPE — this covers what .githooks/ structurally cannot see:
//
//   * hook bypasses (--no-verify, core.hooksPath edits, deleting .githooks).
//     A hook cannot defend itself, which is what makes this the highest-value
//     rule here: without it, every git-level guarantee is one flag deep.
//   * commands that never reach git at all: gh pr merge outright, and any
//     gh or push whose origin is not under github.com/enkinex. gh pr create
//     against an enkinex remote is allowed here and gated in config.
//   * the shape of a command rather than its result — `git add -A` is invisible
//     to pre-commit, which only ever sees the index that resulted.
//   * reads of credential paths, which opencode denies in config but Claude
//     Code and Codex do not.
//
// Anything enforceable at the git layer belongs in .githooks/ instead: it binds
// humans too, and it cannot be skipped by using a different agent.

import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

const ENKINEX_REMOTE = /github\.com[:/]enkinex\//;

const SECRET_PATH =
  /(^|\/)\.env(\.|$)|\.(pem|key|p12|pfx|keystore|jks)$|(^|\/)id_(rsa|ed25519|ecdsa)$/i;
const SECRET_PATH_EXEMPT = /\.(example|sample|template)$/i;

// ── helpers ────────────────────────────────────────────────────────────────
const tokens = (cmd) => cmd.trim().split(/\s+/);

/** Short-flag clusters mean `-nm` counts as `-n`. */
const hasShortFlag = (cmd, letter) =>
  tokens(cmd).some((t) => /^-[a-zA-Z]+$/.test(t) && t.slice(1).includes(letter));

const hasFlag = (cmd, flag) => tokens(cmd).includes(flag);

/**
 * Matches the command and any `&&`/`;`/`|` chained segment of it.
 *
 * Splitting has to ignore separators inside quotes. Splitting on a bare `|`
 * without doing so trades one bypass for another: it catches
 * `echo x | git commit --no-verify`, and it lets
 * `git commit -m "fix the A|B table" --no-verify` through, because the segment
 * carrying the flag no longer starts with `git commit`. A pipe in a commit
 * message is the likelier of the two to occur, so that trade was a loss. It is
 * also why an ordinary alternation in a read-only `grep` was being evaluated as
 * if its tail were a separate command.
 *
 * Quoted spans are blanked to same-length filler before the split, so offsets
 * are preserved and the ORIGINAL text of each segment is what the rules see.
 */
const maskQuoted = (cmd) => {
  let masked = "";
  let quote = null;
  for (let i = 0; i < cmd.length; i++) {
    const ch = cmd[i];
    if (quote) {
      // Inside single quotes a backslash is literal; inside double quotes it escapes.
      if (quote === '"' && ch === "\\" && i + 1 < cmd.length) {
        masked += "xx";
        i++;
        continue;
      }
      masked += ch === quote ? ch : "x";
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      masked += ch;
      continue;
    }
    masked += ch;
  }
  return masked;
};

const segments = (cmd) => {
  const masked = maskQuoted(cmd);

  const out = [];
  let start = 0;
  const sep = /&&|\|\||\||;|\n/g;
  let m;
  while ((m = sep.exec(masked)) !== null) {
    out.push(cmd.slice(start, m.index));
    start = m.index + m[0].length;
  }
  out.push(cmd.slice(start));
  return out.map((s) => s.trim()).filter(Boolean);
};

const startsWith = (seg, prefix) =>
  seg === prefix || seg.startsWith(prefix + " ");

/**
 * Git's global options sit BETWEEN `git` and the verb, so `git -C . commit`
 * defeats every rule below that matches on a `git commit` prefix. Leading
 * `NAME=value` assignments move the verb the same way. Both are stripped here
 * and the rules see `git <verb> …`.
 *
 * What is stripped is returned rather than discarded, because two of those
 * tokens are themselves tampering: `-c core.hooksPath=` and the
 * `GIT_CONFIG_KEY_*` environment form both redirect the hooks without ever
 * spelling `git config`.
 *
 * Any leading `-` token is treated as a global option, rather than only the
 * ones on a list. An unknown flag that stopped the walk would leave the whole
 * segment unmatched, which is the failure being fixed.
 *
 * The list below is only for the options that take a SEPARATE value, and it
 * has to be exact in that direction: naming one that does not take a separate
 * value would consume the verb instead and hand back a bypass. Each entry was
 * checked against git 2.55.0 by giving it a value and watching option parsing
 * accept it. `--exec-path` is deliberately absent — bare, it prints a path and
 * runs nothing.
 */
const ASSIGNMENT = /^[A-Za-z_][A-Za-z0-9_]*=/;
const GLOBAL_TAKES_VALUE = new Set([
  "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--attr-source",
  "--config-env",
]);

/**
 * Splitting on whitespace would cut `-c "user.name=A B"` in two and leave the
 * walk below pointing at `B"` instead of the verb — the same bypass one layer
 * down, so it is masked the same way. Boundaries come from the masked text and
 * the ORIGINAL substring is what is returned.
 */
const quotedTokens = (seg) => {
  const masked = maskQuoted(seg);
  const out = [];
  const word = /\S+/g;
  let m;
  while ((m = word.exec(masked)) !== null) {
    out.push(seg.slice(m.index, m.index + m[0].length));
  }
  return out;
};

/** `-C 'my repo'` arrives with its quotes still on; a path keeps neither. */
const unquote = (t) =>
  (t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))
    ? t.slice(1, -1)
    : t;

const normalise = (seg) => {
  const t = quotedTokens(seg);
  let i = 0;
  const stripped = [];
  while (i < t.length && ASSIGNMENT.test(t[i])) stripped.push(t[i++]);
  const assignments = i;

  if (t[i] !== "git") {
    return {
      cmd: assignments ? t.slice(i).join(" ") : seg,
      stripped,
      chdir: [],
    };
  }

  const chdir = [];
  let j = i + 1;
  while (j < t.length && t[j].startsWith("-")) {
    const flag = t[j].split("=")[0];
    stripped.push(t[j]);
    if (GLOBAL_TAKES_VALUE.has(flag) && !t[j].includes("=") && j + 1 < t.length) {
      stripped.push(t[j + 1]);
      if (flag === "-C") chdir.push(unquote(t[j + 1]));
      j++;
    }
    j++;
  }

  if (!stripped.length) return { cmd: seg, stripped, chdir };
  return { cmd: ["git", ...t.slice(j)].join(" "), stripped, chdir };
};

// ── rules ──────────────────────────────────────────────────────────────────
// Each returns a reason string to deny, or null to allow.
const BASH_RULES = [
  {
    id: "hook-bypass-flag",
    check: (s) =>
      (startsWith(s, "git commit") || startsWith(s, "git push")) &&
      (hasFlag(s, "--no-verify") || hasShortFlag(s, "n"))
        ? "--no-verify skips the enkinex git hooks. If a hook refuses, fix the cause rather than bypassing the check."
        : null,
  },
  {
    id: "hook-path-tamper",
    // Three spellings, one effect. `git config core.hooksPath` is the visible
    // one; `-c core.hooksPath=` and `GIT_CONFIG_KEY_n=core.hooksPath` set it for
    // a single command and leave nothing behind to notice afterwards. The last
    // two are in ctx.stripped, which is what normalise() took off the front.
    check: (s, ctx) =>
      /git\s+config\s+(--\S+\s+)*core\.hooksPath/.test(s) ||
      ctx.stripped.some((t) => /core\.hooksPath/i.test(t))
        ? "core.hooksPath is what makes the enkinex hooks active. Changing it from an agent disables every git-level guarantee."
        : null,
  },
  {
    id: "hook-removal",
    check: (s) =>
      /\b(rm|mv|chmod)\b[^|]*\.githooks\b/.test(s)
        ? "refusing to remove, move or unset the executable bit on .githooks/."
        : null,
  },
  {
    id: "implicit-staging",
    check: (s) => {
      if (!startsWith(s, "git add")) return null;
      const args = tokens(s).slice(2);
      const implicit = args.some(
        (a) => a === "." || a === "-A" || a === "--all" || a === "-u" || a === ":/",
      );
      return implicit || args.length === 0
        ? "stage explicit paths only — never `git add -A`, `git add .` or `git add -u`. Naming the paths is how an unrelated or secret-shaped file avoids being swept into a commit."
        : null;
    },
  },
  {
    id: "pr-merge",
    check: (s) =>
      startsWith(s, "gh pr merge")
        // Inlined, not cited: this string is printed to a user mid-denial, and
        // the plan it used to name is in a private repo they may not hold. A
        // path nobody can open is noise at exactly the moment the message has
        // to be actionable.
        ? "landing a PR is a human action (ADR-0002): an unattended run must not merge its own work. Ask the user to merge."
        : null,
  },
  {
    id: "destructive-git",
    check: (s) => {
      if (startsWith(s, "git push") && (hasFlag(s, "--force") || hasShortFlag(s, "f")))
        return "force-pushing rewrites published history.";
      if (startsWith(s, "git reset") && hasFlag(s, "--hard"))
        return "`git reset --hard` discards uncommitted work irrecoverably.";
      if (startsWith(s, "git clean") && hasShortFlag(s, "f"))
        return "`git clean -f` deletes untracked files irrecoverably.";
      return null;
    },
  },
  {
    id: "remote-guard",
    check: (s, ctx) => {
      if (!/^(gh\s|git\s+push\b)/.test(s)) return null;
      if (!/^gh\s+(pr|repo|release|api)\b/.test(s) && !startsWith(s, "git push")) return null;
      const origin = originOf(targetOf(ctx));
      if (origin === null) return null; // no remote: a local scratch tree
      return ENKINEX_REMOTE.test(origin)
        ? null
        : `origin is not under github.com/enkinex (${origin}).`;
    },
  },
];

/**
 * `git -C <path>` is where the command actually writes, so it is the origin
 * worth checking. Git interprets each -C relative to the previous one, which
 * `resolve` reproduces. A path that does not exist makes originOf return null
 * and the rule allow — the same answer a scratch tree already gets.
 */
function targetOf(ctx) {
  return ctx.chdir.reduce((dir, next) => resolve(dir, next), ctx.cwd || process.cwd());
}

function originOf(cwd) {
  try {
    return execFileSync("git", ["remote", "get-url", "origin"], {
      cwd: cwd || process.cwd(),
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

function evaluate(payload) {
  const tool = payload.tool_name ?? payload.toolName ?? payload.tool ?? "";
  const input = payload.tool_input ?? payload.toolInput ?? payload.args ?? {};
  const cwd = payload.cwd ?? payload.directory ?? process.cwd();

  if (/^bash$/i.test(tool) || /^shell$/i.test(tool)) {
    const command = input.command ?? input.cmd ?? "";
    if (!command) return null;
    for (const seg of segments(command)) {
      const { cmd, stripped, chdir } = normalise(seg);
      for (const rule of BASH_RULES) {
        const reason = rule.check(cmd, { cwd, stripped, chdir });
        if (reason) return `[${rule.id}] ${reason}`;
      }
    }
    return null;
  }

  if (/^(read|edit|write|multiedit|notebookedit)$/i.test(tool)) {
    const path = input.file_path ?? input.filePath ?? input.path ?? "";
    if (path && SECRET_PATH.test(path) && !SECRET_PATH_EXEMPT.test(path)) {
      return `[secret-path] ${path} is a credential-shaped path and is not readable or writable by an agent.`;
    }
  }

  return null;
}

// ── main ───────────────────────────────────────────────────────────────────
let payload = {};
try {
  const raw = readFileSync(0, "utf8");
  if (raw.trim()) payload = JSON.parse(raw);
} catch {
  process.exit(0); // Never let a malformed payload block legitimate work.
}

const reason = evaluate(payload);

if (reason) {
  // Claude Code reads hookSpecificOutput; Codex reads decision/reason. Emitting
  // both keeps this one file valid for both, and each ignores the other's.
  process.stdout.write(
    JSON.stringify({
      decision: "block",
      reason: `enkinex policy: ${reason}`,
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: `enkinex policy: ${reason}`,
      },
    }),
  );
}

process.exit(0);
