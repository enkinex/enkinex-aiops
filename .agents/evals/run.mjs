#!/usr/bin/env node
// enkinex agent-output evals — the half the golden set cannot cover.
//
// tests/ asserts the artefacts: hooks, config, guard, frontmatter, MCP. It
// never asks a model anything, so a re-pin or a rewritten instruction can
// degrade every output in the org while `just test` stays green. This asks.
//
// Deliberately NOT part of `just check` (AIOPS-13): the gate stays free, fast
// and hermetic, and a gate that costs money per run is one people skip.
//
//   just eval            # all cases
//   just eval docs       # cases whose id contains "docs"
//
// The three decisions this suite refused to start without are in README.md:
// each agent runs on the model it pins, a run reports its cost and aborts
// above the budget, and a case passes on a majority of samples.

import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..", "..");
const AGENT_DIR = join(ROOT, "opencode", "agent");
const API = "https://openrouter.ai/api/v1";

const c = { reset: "\x1b[0m", dim: "\x1b[2m", ok: "\x1b[32m", bad: "\x1b[31m", warn: "\x1b[33m" };
if (!process.stdout.isTTY) for (const k of Object.keys(c)) c[k] = "";

const key = process.env.OPENROUTER_API_KEY;
if (!key) {
  console.error("eval: OPENROUTER_API_KEY is not set. This suite makes live model calls;");
  console.error("      there is no offline mode, because a mocked eval measures the mock.");
  process.exit(2);
}

const spec = JSON.parse(readFileSync(join(HERE, "cases.json"), "utf8"));
const filter = process.argv[2] ?? "";
const cases = spec.cases.filter((x) => x.id.includes(filter));
if (cases.length === 0) {
  console.error(`eval: no case id contains ${JSON.stringify(filter)}`);
  process.exit(2);
}

/** An agent's pinned model and instruction, read from the agent file itself —
 *  never configured here, so the suite measures what the org actually runs. */
function agentSpec(name) {
  const path = join(AGENT_DIR, `${name}.md`);
  const raw = readFileSync(path, "utf8");
  const m = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!m) throw new Error(`${name}.md has no frontmatter block`);
  const pin = m[1].match(/^model:\s*(\S+)/m)?.[1];
  if (!pin) throw new Error(`${name}.md pins no model`);
  // `openrouter/vendor/model` in opencode config is `vendor/model` upstream.
  return { model: pin.replace(/^openrouter\//, ""), system: m[2].trim(), file: `${name}.md` };
}

const pricing = new Map();
async function loadCatalog() {
  const r = await fetch(`${API}/models`, { headers: { Authorization: `Bearer ${key}` } });
  if (!r.ok) throw new Error(`model catalog unavailable: HTTP ${r.status}`);
  for (const m of (await r.json()).data) {
    pricing.set(m.id, { prompt: Number(m.pricing.prompt), completion: Number(m.pricing.completion) });
  }
}

async function ask(model, system, input) {
  const r = await fetch(`${API}/chat/completions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      messages: [{ role: "system", content: system }, { role: "user", content: input }],
      // Frontier pins are reasoning models: kimi-k3 spent 279 reasoning tokens
      // on a one-line question. At 400 the reasoning consumed the whole budget,
      // `content` came back empty, and the suite read that as the agent
      // failing — absence looking like a result, which is the mistake this
      // repo has recorded three times. The ceiling has to clear reasoning
      // before any answer exists to score.
      max_tokens: 1500,
    }),
  });
  const j = await r.json();
  if (j.error) throw new Error(`${model}: ${j.error.message}`);
  const u = j.usage ?? { prompt_tokens: 0, completion_tokens: 0 };
  const p = pricing.get(model) ?? { prompt: 0, completion: 0 };
  const choice = j.choices?.[0] ?? {};
  return {
    text: choice.message?.content ?? "",
    truncated: choice.finish_reason === "length",
    served: j.model,
    // OpenRouter reports the authoritative cost, cache discounts included; the
    // computed figure is the fallback and will read slightly high.
    cost: typeof u.cost === "number" ? u.cost : u.prompt_tokens * p.prompt + u.completion_tokens * p.completion,
  };
}

/** Deterministic and unattended. No model scores another model, and nothing
 *  waits for a person — an eval that needs one read will not be read. */
function score(text, kase) {
  // Case-insensitive throughout: a check that fails because a model capitalised
  // a word is noise, and noise is what gets a suite ignored. A leading `(?i)`
  // is accepted and stripped — JavaScript has no inline flag, and whoever
  // writes the next case will type it out of habit.
  const rx = (re) => new RegExp(re.replace(/^\(\?i\)/, ""), "i");
  for (const re of kase.must_match ?? []) if (!rx(re).test(text)) return `no match: ${re}`;
  for (const re of kase.must_not_match ?? []) if (rx(re).test(text)) return `matched: ${re}`;
  return null;
}

const money = (n) => `$${n.toFixed(4)}`;

async function main() {
  await loadCatalog();

  // A pin that no longer resolves fails loudly, before anything is spent.
  // Evaluating whatever the provider substitutes would report a rate for a
  // model nobody chose, which is worse than reporting nothing.
  const agents = new Map();
  const missing = new Set(); // by agent, not by case — one bad pin is one message
  for (const kase of cases) {
    if (!agents.has(kase.agent)) agents.set(kase.agent, agentSpec(kase.agent));
    const a = agents.get(kase.agent);
    if (!pricing.has(a.model)) missing.add(`${a.file} pins ${a.model}, which OpenRouter does not list`);
  }
  if (missing.size) {
    console.error(`${c.bad}eval: a pinned model no longer resolves — refusing to substitute${c.reset}`);
    for (const m of missing) console.error(`  ${m}`);
    process.exit(1);
  }

  const known = [...new Set([...agents.values()].map((a) => a.model))];
  console.log(`${c.dim}eval: ${cases.length} case(s), ${spec.samples} sample(s) each, pass at ${spec.pass_at}/${spec.samples}${c.reset}`);
  console.log(`${c.dim}eval: models ${known.join(", ")} · budget ${money(spec.budget_usd)}${c.reset}\n`);

  let spent = 0, passed = 0, aborted = false;
  const rows = [];

  for (const kase of cases) {
    const a = agents.get(kase.agent);
    let hits = 0, truncated = 0, worst = null; const notes = [];
    for (let i = 0; i < spec.samples; i++) {
      if (spent >= spec.budget_usd) { aborted = true; break; }
      const r = await ask(a.model, a.system, kase.input);
      spent += r.cost;
      // Truncation is not a wrong answer. Scoring it would report the agent
      // failing when the runner never let it finish, so it is called out as
      // the configuration problem it is.
      if (r.truncated && r.text.trim() === "") { truncated++; continue; }
      const why = score(r.text, kase);
      if (why === null) hits++;
      else { notes.push(why); if (!worst) worst = r.text; }
    }
    if (aborted) break;
    if (truncated) {
      console.error(`${c.bad}eval: ${kase.id} — ${truncated}/${spec.samples} sample(s) hit the token ceiling before producing an answer.${c.reset}`);
      console.error(`      Raise max_tokens in run.mjs; scoring a truncated reply would report the agent failing.`);
      process.exit(2);
    }
    const good = hits >= spec.pass_at;
    if (good) passed++;
    rows.push({ id: kase.id, model: a.model, hits, good, notes });
    const mark = good ? `${c.ok}pass${c.reset}` : `${c.bad}FAIL${c.reset}`;
    console.log(`  ${mark} ${kase.id} ${c.dim}${hits}/${spec.samples} · ${a.model}${c.reset}`);
    if (!good) {
      for (const n of [...new Set(notes)]) console.log(`         ${c.dim}${n}${c.reset}`);
      // The first failing sample, truncated. A failure nobody can read is one
      // nobody acts on, and the usual answer — rerun it by hand — costs another
      // call and may not reproduce.
      const snip = worst.replace(/\s+/g, " ").trim().slice(0, 220);
      console.log(`         ${c.dim}got: ${snip}${worst.length > 220 ? "…" : ""}${c.reset}`);
    }
  }

  // A rate, not a boolean — and the cost beside it, so the spend is visible
  // where it is incurred rather than in next month's ledger.
  const ran = rows.length;
  console.log(`\n${passed}/${ran} case(s) passed · cost ${money(spent)}`);
  if (aborted) {
    console.error(`${c.warn}eval: stopped at the ${money(spec.budget_usd)} budget after ${ran} case(s) — ${cases.length - ran} not run${c.reset}`);
    process.exit(1);
  }
  process.exit(passed === ran ? 0 : 1);
}

main().catch((e) => { console.error(`${c.bad}eval: ${e.message}${c.reset}`); process.exit(2); });
