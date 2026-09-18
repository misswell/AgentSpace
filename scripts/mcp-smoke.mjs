// End-to-end smoke test for the MCP server.
//
// Talks real JSON-RPC over the child's stdio exactly as an MCP client would:
// initialize -> tools/list -> tools/call. Used by docs/validation.md to show
// that the server actually works, not merely that it typechecks.
//
//   AGENTSPACE_BIN=... AGENTSPACE_ROOT=... node scripts/mcp-smoke.mjs
//
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const bin = process.argv[2] ?? "node";
const args = process.argv.slice(3);

const child = spawn(bin, args, {
  stdio: ["pipe", "pipe", "inherit"],
  env: process.env,
});

const pending = new Map();
let nextId = 1;

createInterface({ input: child.stdout }).on("line", (line) => {
  if (!line.trim()) return;
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    console.log("  (non-JSON on stdout)", line.slice(0, 200));
    return;
  }
  const resolve = pending.get(message.id);
  if (resolve) {
    pending.delete(message.id);
    resolve(message);
  }
});

function request(method, params) {
  const id = nextId++;
  const payload = { jsonrpc: "2.0", id, method, ...(params ? { params } : {}) };
  child.stdin.write(JSON.stringify(payload) + "\n");
  return new Promise((resolve, reject) => {
    pending.set(id, resolve);
    setTimeout(() => reject(new Error(`timeout waiting for ${method}`)), 30_000);
  });
}

function notify(method, params) {
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, ...(params ? { params } : {}) }) + "\n");
}

const failures = [];
function check(label, condition, detail) {
  console.log(`  ${condition ? "PASS" : "FAIL"}  ${label}`);
  if (!condition) failures.push(`${label}${detail ? ` — ${detail}` : ""}`);
}

try {
  console.log("== initialize ==");
  const init = await request("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "agentspace-smoke", version: "1.0.0" },
  });
  const server = init.result?.serverInfo;
  check("initialize returns a server name", Boolean(server?.name), JSON.stringify(init.error));
  console.log(`     server: ${server?.name} ${server?.version}`);
  const instructions = init.result?.instructions ?? "";
  check("instructions recommend the status -> screenshot -> input loop",
    /status/i.test(instructions) && /screenshot/i.test(instructions) && /input/i.test(instructions));
  check("instructions warn about SESSION_IS_CONSOLE", /SESSION_IS_CONSOLE/.test(instructions));

  notify("notifications/initialized");

  console.log("== tools/list ==");
  const list = await request("tools/list", {});
  const tools = list.result?.tools ?? [];
  const names = tools.map((t) => t.name);
  console.log(`     ${names.length} tools`);
  for (const required of [
    "agentspace_list", "agentspace_status", "agentspace_screenshot",
    "agentspace_input", "agentspace_click", "agentspace_type",
    "agentspace_key", "agentspace_scroll", "agentspace_drag",
    "agentspace_launch", "agentspace_quit", "agentspace_apps",
    "agentspace_exec", "agentspace_ax_snapshot",
  ]) {
    check(`tool ${required} exists`, names.includes(required));
  }
  check("no tool can create a Space", !names.some((n) => /create|delete|grant|tcc/i.test(n)));
  check("every tool has a description", tools.every((t) => (t.description ?? "").length > 20));
  check("every tool has an input schema", tools.every((t) => t.inputSchema?.type === "object"));

  console.log("== tools/call agentspace_status ==");
  const status = await request("tools/call", {
    name: "agentspace_status",
    arguments: {},
  });
  const statusText = status.result?.content?.map((c) => c.text ?? "").join("\n") ?? "";
  check("status call returns content", statusText.length > 0, JSON.stringify(status.error));
  console.log("     " + statusText.split("\n").slice(0, 6).join("\n     "));

  console.log("== tools/call agentspace_{click,type,key} — must be refused, not fall back ==");
  for (const [name, callArgs] of [
    ["agentspace_click", { space: "Demo", x: 100, y: 100 }],
    ["agentspace_type", { space: "Demo", text: "hello" }],
    ["agentspace_key", { space: "Demo", combo: "cmd+l" }],
  ]) {
    const reply = await request("tools/call", { name, arguments: callArgs });
    const text = reply.result?.content?.map((c) => c.text ?? "").join("\n") ?? "";
    const isError = reply.result?.isError === true || Boolean(reply.error);
    check(`${name} reports an error`, isError, `isError=${reply.result?.isError}`);
    check(`${name} names SESSION_IS_CONSOLE`, /SESSION_IS_CONSOLE/.test(text),
      text.slice(0, 200));
    check(`${name} includes the fix text`, /→|Switch back|console/i.test(text),
      text.slice(0, 200));
    check(`${name} says nothing about running locally`,
      !/falling back|running locally|your own session instead/i.test(text));
  }

  console.log("== unknown tool is refused ==");
  const unknown = await request("tools/call", { name: "agentspace_make_me_root", arguments: {} });
  check("unknown tool errors", Boolean(unknown.error) || unknown.result?.isError === true);
} catch (error) {
  failures.push(`threw: ${error.message}`);
  console.log(`  FATAL ${error.message}`);
} finally {
  child.kill("SIGTERM");
}

console.log();
if (failures.length) {
  console.log(`${failures.length} FAILURE(S):`);
  for (const f of failures) console.log(`  - ${f}`);
  process.exit(1);
}
console.log("all MCP smoke checks passed");
