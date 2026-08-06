#!/usr/bin/env node
// enkinex MCP server — GENERATED from enkinex-aiops mcp/enkinex.mjs.
// Do not edit here; change the source and run `just sync-opencode`.
//
// Phase 4's three tools, as ONE MCP server rather than three
// `.opencode/tools/*.ts` files. Custom opencode tools are opencode-only by
// construction; MCP is the single tool-extension surface opencode, Claude Code
// and Codex all speak, so the same implementation serves every harness.
//
// Zero dependencies and hand-rolled JSON-RPC, matching .githooks/ and
// policy/guard.mjs: the layer is distributed by file copy into repos that have
// no install step, so a server that needs `npm install` before it runs would
// not be governance that travels with the repo.
//
// TOKEN ECONOMY (ADR-0002). A tool catalog is ambient per-session cost, which
// is why the catalog is built from what the repo actually is: a repo with no
// kcl.mod never sees the KCL tools, and a repo with no plan/ never sees
// project_state. An empty catalog is the correct answer for an unrelated repo.
//
// stdio transport: newline-delimited JSON-RPC on stdout, nothing else ever.
// Diagnostics go to stderr.

import { execFile } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = process.cwd();
const DEFAULT_PROTOCOL = "2025-06-18";

const has = (p) => existsSync(join(ROOT, p));

// ── tool catalog, derived from the repo ────────────────────────────────────
function catalog() {
  const tools = [];

  if (has("kcl.mod")) {
    tools.push({
      name: "kcl_vet",
      description:
        "Validate this KCL library against its test fixtures by running the repo's own `just test` gate. Returns pass/fail plus the compiler's errors. Use before reporting work complete.",
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
    });
    tools.push({
      name: "kcl_docs",
      description:
        "Regenerate the KCL schema reference (`just docs`) and report whether the committed docs were stale. Use after changing any docstring.",
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
    });
  }

  if (has("plan") || has("discovery") || has("architecture")) {
    tools.push({
      name: "project_state",
      description:
        "Summarise this repo's active plans, discovery documents and ADRs with their status lines, so you can orient without reading every file.",
      inputSchema: { type: "object", properties: {}, additionalProperties: false },
    });
  }

  return tools;
}

// ── helpers ────────────────────────────────────────────────────────────────
function run(cmd, args, timeout = 300_000) {
  return new Promise((resolve) => {
    execFile(cmd, args, { cwd: ROOT, timeout, encoding: "utf8", maxBuffer: 8 << 20 },
      (error, stdout, stderr) => {
        resolve({
          ok: !error,
          code: error?.code ?? 0,
          spawnFailed: error?.code === "ENOENT",
          out: `${stdout || ""}${stderr || ""}`.trim(),
        });
      });
  });
}

const tail = (s, n = 60) => s.split("\n").slice(-n).join("\n");

function walk(dir, out = []) {
  let entries;
  try { entries = readdirSync(join(ROOT, dir)); } catch { return out; }
  for (const e of entries) {
    const rel = join(dir, e);
    let st;
    try { st = statSync(join(ROOT, rel)); } catch { continue; }
    if (st.isDirectory()) walk(rel, out);
    else if (e.endsWith(".md")) out.push(rel);
  }
  return out;
}

// ── tools ──────────────────────────────────────────────────────────────────
const IMPL = {
  async kcl_vet() {
    const r = await run("just", ["test"]);
    if (r.spawnFailed) {
      return { isError: true, text: "`just` is not on PATH, so the repo's test gate cannot run." };
    }
    const failures = r.out
      .split("\n")
      .filter((l) => /error|Error|failed|expected/.test(l))
      .slice(0, 40);
    return {
      isError: !r.ok,
      text: [
        r.ok ? "PASS — all kcl vet fixtures validate." : "FAIL — the test gate is red.",
        failures.length ? `\nDiagnostics:\n${failures.join("\n")}` : "",
        r.ok ? "" : `\nFull output (tail):\n${tail(r.out)}`,
      ].join(""),
    };
  },

  async kcl_docs() {
    const r = await run("just", ["docs"]);
    if (r.spawnFailed) {
      return { isError: true, text: "`just` is not on PATH, so docs cannot be regenerated." };
    }
    if (!r.ok) return { isError: true, text: `FAIL — \`just docs\` errored.\n${tail(r.out)}` };
    // The useful signal is not that docs regenerated, but whether what is
    // committed was already correct. A dirty tree here means stale docs.
    const g = await run("git", ["status", "--porcelain", "--", "docs"], 30_000);
    const changed = g.out.trim();
    return {
      isError: false,
      text: changed
        ? `Docs regenerated and CHANGED — the committed reference was stale. Commit these:\n${changed}`
        : "Docs regenerated with no diff — the committed reference is current.",
    };
  },

  async project_state() {
    const groups = [
      ["Active plans", walk("plan").filter((p) => !p.includes(`${"plan"}/done/`))],
      ["Completed plans", walk("plan/done")],
      ["Discovery", walk("discovery")],
      ["ADRs", walk("architecture")],
    ];
    const lines = [];
    for (const [label, files] of groups) {
      if (!files.length) continue;
      lines.push(`## ${label}`);
      for (const f of files.sort()) {
        let body = "";
        try { body = readFileSync(join(ROOT, f), "utf8"); } catch { continue; }
        const title = body.match(/^#\s+(.+)$/m)?.[1] ?? relative(".", f);
        const status = body
          .split("\n")
          .filter((l) => /^\s*[-*]?\s*(\*\*)?(Status|Phase \d+ status)/i.test(l))
          .slice(0, 6)
          .map((l) => `    ${l.trim()}`);
        lines.push(`  ${f} — ${title}`);
        lines.push(...status);
      }
    }
    return {
      isError: false,
      text: lines.length ? lines.join("\n") : "No plan/, discovery/ or architecture/ documents found.",
    };
  },
};

// ── JSON-RPC plumbing ──────────────────────────────────────────────────────
const send = (msg) => process.stdout.write(JSON.stringify(msg) + "\n");
const reply = (id, result) => send({ jsonrpc: "2.0", id, result });
const fail = (id, code, message) => send({ jsonrpc: "2.0", id, error: { code, message } });

async function handle(msg) {
  const { id, method, params } = msg;

  // Notifications carry no id and take no response.
  if (id === undefined || id === null) return;

  switch (method) {
    case "initialize": {
      const asked = params?.protocolVersion;
      return reply(id, {
        protocolVersion: /^\d{4}-\d{2}-\d{2}$/.test(asked ?? "") ? asked : DEFAULT_PROTOCOL,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "enkinex", version: "0.1.0" },
      });
    }
    case "ping":
      return reply(id, {});
    case "tools/list":
      return reply(id, { tools: catalog() });
    case "tools/call": {
      const name = params?.name;
      const impl = IMPL[name];
      if (!impl || !catalog().some((t) => t.name === name)) {
        return fail(id, -32602, `Unknown tool "${name}" for this repository.`);
      }
      try {
        const r = await impl(params?.arguments ?? {});
        return reply(id, { content: [{ type: "text", text: r.text }], isError: !!r.isError });
      } catch (e) {
        return reply(id, {
          content: [{ type: "text", text: `enkinex mcp: ${e?.message ?? e}` }],
          isError: true,
        });
      }
    }
    default:
      return fail(id, -32601, `Method not found: ${method}`);
  }
}

// In-flight accounting. A tool call can outlive stdin: `just test` takes
// seconds, and exiting the moment the client closes stdin would kill the child
// and return nothing. Drain before exiting.
let pending = 0;
let stdinClosed = false;
const maybeExit = () => {
  if (stdinClosed && pending === 0) process.exit(0);
};

let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  buf += chunk;
  let nl;
  while ((nl = buf.indexOf("\n")) !== -1) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch {
      process.stderr.write(`enkinex mcp: unparseable line\n`);
      continue;
    }
    pending += 1;
    handle(msg)
      .catch((e) => process.stderr.write(`enkinex mcp: ${e?.message ?? e}\n`))
      .finally(() => { pending -= 1; maybeExit(); });
  }
});
process.stdin.on("end", () => { stdinClosed = true; maybeExit(); });
