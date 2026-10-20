// End-to-end MCP registration and CLI bridge coverage. The server runs over
// real stdio JSON-RPC; AGENTSPACE_BIN points at a recording mock, so no Worker,
// app, or desktop session is opened.

import test from "node:test";
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const packageDir = path.dirname(here);
const serverPath = path.join(packageDir, "dist", "index.js");

const pairedSuffixes = [
  "list", "status", "doctor", "diagnostics", "screenshot", "apps", "ax_snapshot", "input", "click",
  "type", "key", "scroll", "drag", "launch", "quit", "exec", "open_desktop",
  "capabilities", "apps_available", "activate", "move", "ax_frontmost",
  "ax_windows", "ax_element_at", "ax_perform", "ax_set_value", "windows",
  "window_action", "open_resource", "clipboard_read", "clipboard_write",
];

class McpProcess {
  constructor(environment, executable = process.execPath, args = [serverPath]) {
    const childEnvironment = { ...process.env, ...environment };
    for (const [key, value] of Object.entries(childEnvironment)) {
      if (value === undefined) delete childEnvironment[key];
    }
    this.child = spawn(executable, args, {
      cwd: packageDir,
      env: childEnvironment,
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.closed = once(this.child, "close");
    this.nextId = 1;
    this.pending = new Map();
    this.buffer = "";
    this.stderr = "";
    this.child.stdout.setEncoding("utf8");
    this.child.stderr.setEncoding("utf8");
    this.child.stdout.on("data", chunk => this.onStdout(chunk));
    this.child.stderr.on("data", chunk => { this.stderr += chunk; });
    this.child.on("error", error => {
      for (const pending of this.pending.values()) pending.reject(error);
      this.pending.clear();
    });
  }

  onStdout(chunk) {
    this.buffer += chunk;
    for (;;) {
      const newline = this.buffer.indexOf("\n");
      if (newline < 0) return;
      const line = this.buffer.slice(0, newline);
      this.buffer = this.buffer.slice(newline + 1);
      if (!line.trim()) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        this.stderr += `\nUnexpected stdout: ${line}`;
        continue;
      }
      const pending = this.pending.get(message.id);
      if (pending) {
        this.pending.delete(message.id);
        clearTimeout(pending.timer);
        pending.resolve(message);
      }
    }
  }

  request(method, params) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`MCP request ${method} timed out; stderr: ${this.stderr}`));
      }, 8_000);
      this.pending.set(id, { resolve, reject, timer });
      this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    });
  }

  notify(method, params = {}) {
    this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method, params })}\n`);
  }

  async initialize() {
    const response = await this.request("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "agentspace-mcp-tools-test", version: "1.0.0" },
    });
    assert.ok(response.result?.serverInfo?.name, JSON.stringify(response.error));
    this.notify("notifications/initialized");
    return response.result;
  }

  async stop() {
    if (this.child.exitCode === null && this.child.signalCode === null) {
      this.child.kill("SIGTERM");
    }
    let timer;
    try {
      await Promise.race([
        this.closed,
        new Promise((_, reject) => {
          timer = setTimeout(() => reject(new Error("MCP server did not exit after SIGTERM")), 5_000);
        }),
      ]);
    } finally {
      clearTimeout(timer);
    }
  }
}

function toolText(result) {
  return (result?.content ?? []).filter(item => item.type === "text").map(item => item.text).join("\n");
}

function cliCalls(logPath) {
  const contents = readFileSync(logPath, "utf8").trim();
  return contents ? contents.split("\n").map(line => JSON.parse(line)) : [];
}

function writeMockMode(modePath, mode) {
  writeFileSync(modePath, JSON.stringify(mode));
}

test("MCP registers paired tools and bridges safely to the CLI", async () => {
  assert.ok(existsSync(serverPath), "run `npm run build` before the MCP bridge tests");
  const tempRoot = mkdtempSync(path.join(tmpdir(), "agentspace-mcp-tools-"));
  const mockPath = path.join(tempRoot, "mock-agentspace.mjs");
  const logPath = path.join(tempRoot, "calls.jsonl");
  const modePath = path.join(tempRoot, "mode.json");
  const markerPath = path.join(tempRoot, "shell-was-run");
  writeFileSync(logPath, "");
  writeMockMode(modePath, {
    results: {
      screenshot: {
        width: 1280, height: 720, pixelWidth: 3840, pixelHeight: 2160,
        scale: 2, originX: -1920, originY: 100, pngBase64: "aGVsbG8=",
      },
    },
  });
  writeFileSync(mockPath, `#!/usr/bin/env node
import { appendFileSync, readFileSync } from "node:fs";
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const argv = process.argv.slice(2);
const stdin = Buffer.concat(chunks).toString("utf8");
appendFileSync(process.env.AGENTSPACE_MOCK_LOG, JSON.stringify({ argv, stdin }) + "\\n");
const mode = JSON.parse(readFileSync(process.env.AGENTSPACE_MOCK_MODE, "utf8"));
if (mode.code) {
  process.stdout.write(JSON.stringify({
    status: "unavailable", reason: mode.code, ok: false,
    error: { code: mode.code, message: mode.message }, fix: mode.fix,
  }));
  process.exitCode = 1;
} else {
  const result = mode.results?.[argv[0]];
  process.stdout.write(JSON.stringify(result ?? { argv, stdin }));
  if (mode.exitCode) process.exitCode = mode.exitCode;
}
`);
  chmodSync(mockPath, 0o755);

  const server = new McpProcess({
    AGENTSPACE_BIN: mockPath,
    AGENTSPACE_MOCK_LOG: logPath,
    AGENTSPACE_MOCK_MODE: modePath,
    AGENTSPACE_MCP_TIMEOUT_MS: "3000",
  });

  try {
    await server.initialize();
    const listed = await server.request("tools/list", {});
    assert.equal(listed.error, undefined, JSON.stringify(listed.error));
    const tools = listed.result?.tools ?? [];
    const byName = new Map(tools.map(tool => [tool.name, tool]));
    assert.equal(byName.size, tools.length, "tool names must be unique");
    assert.equal(tools.length, 62, "all 31 tool pairs should be registered");

    for (const suffix of pairedSuffixes) {
      const modern = byName.get(`agent_${suffix}`);
      const legacy = byName.get(`agentspace_${suffix}`);
      assert.ok(modern, `missing agent_${suffix}`);
      assert.ok(legacy, `missing agentspace_${suffix}`);
      assert.deepEqual(modern.inputSchema, legacy.inputSchema, `${suffix} schemas drifted`);
      assert.equal(modern.description, legacy.description, `${suffix} descriptions drifted`);
    }
    for (const tool of tools) {
      assert.ok((tool.description ?? "").length > 20, `${tool.name} needs an actionable description`);
      assert.equal(tool.inputSchema?.type, "object", `${tool.name} needs an object input schema`);
    }

    // Capabilities are static documentation and must not start the CLI.
    const beforeCapabilities = cliCalls(logPath).length;
    for (const name of ["agent_capabilities", "agentspace_capabilities"]) {
      const result = await server.request("tools/call", { name, arguments: {} });
      assert.equal(result.result?.isError, undefined, toolText(result.result));
      assert.match(toolText(result.result), /systemSettings/);
      assert.match(toolText(result.result), /human/i);
    }
    assert.equal(cliCalls(logPath).length, beforeCapabilities, "capabilities must not spawn the CLI");

    const argsBySuffix = {
      list: {},
      status: { space: "Demo" },
      doctor: {},
      diagnostics: {},
      screenshot: { space: "Demo", maxWidth: 1280, display: 2 },
      apps: { space: "Demo" },
      ax_snapshot: { space: "Demo", pid: 321, maxDepth: 3 },
      input: { space: "Demo", actions: [{ type: "type", text: "hello" }] },
      click: { space: "Demo", x: 12.5, y: 24, double: true },
      type: { space: "Demo", text: "hello" },
      key: { space: "Demo", combo: "cmd+l" },
      scroll: { space: "Demo", dx: 0, dy: -20, x: 30, y: 40 },
      drag: { space: "Demo", x1: 1, y1: 2, x2: 30, y2: 40 },
      launch: { space: "Demo", app: "TextEdit" },
      quit: { space: "Demo", app: "TextEdit", force: true },
      exec: { space: "Demo", command: "printf MCP", cwd: "/workspace" },
      open_desktop: { space: "Demo" },
      apps_available: { space: "Demo", query: "Safari", limit: 7, all: true },
      activate: { space: "Demo", app: "com.example.Editor" },
      move: { space: "Demo", x: 12.25, y: 45.5 },
      ax_frontmost: { space: "Demo", pid: 321 },
      ax_windows: { space: "Demo", pid: 321 },
      ax_element_at: { space: "Demo", x: 50.5, y: 70.25 },
      ax_perform: { space: "Demo", pid: 321, role: "AXButton", identifier: "save", action: "AXPress" },
      ax_set_value: { space: "Demo", pid: 321, identifier: "search", value: "MCP_TEST_VALUE" },
      windows: { space: "Demo" },
      window_action: {
        space: "Demo", action: "set-frame", windowId: 9, pid: 321, generation: 4,
        frame: { x: 1.25, y: 2.5, width: 800, height: 600 },
      },
      open_resource: { space: "Demo", resource: `; touch ${markerPath}; #` },
      clipboard_read: { space: "Demo" },
      clipboard_write: { space: "Demo", text: "" },
    };

    for (const suffix of pairedSuffixes.filter(name => name !== "capabilities")) {
      const before = cliCalls(logPath).length;
      const legacy = await server.request("tools/call", {
        name: `agentspace_${suffix}`, arguments: argsBySuffix[suffix],
      });
      const legacyRecord = cliCalls(logPath)[before];
      const modern = await server.request("tools/call", {
        name: `agent_${suffix}`, arguments: argsBySuffix[suffix],
      });
      const modernRecord = cliCalls(logPath)[before + 1];
      assert.equal(legacy.result?.isError, undefined, `${suffix} legacy call: ${toolText(legacy.result)}`);
      assert.equal(modern.result?.isError, undefined, `${suffix} modern call: ${toolText(modern.result)}`);
      assert.deepEqual(modernRecord, legacyRecord, `${suffix} aliases must bridge identical argv/stdin`);
      assert.deepEqual(modern.result, legacy.result, `${suffix} aliases must return identical results`);
      if (suffix === "screenshot") {
        const text = toolText(modern.result);
        assert.match(text, /x = -1920 \+ imagePixelX \* 1\.5; y = 100 \+ imagePixelY \* 1\.5/);
        assert.ok(modern.result.content.some(item => item.type === "image" && item.data === "aGVsbG8="));
      }
    }

    const records = cliCalls(logPath);
    assert.equal(records.length, (pairedSuffixes.length - 1) * 2);
    const expectedArgv = new Map([
      ["doctor", ["doctor", "--json"]],
      ["diagnostics", ["diagnostics", "--json"]],
      ["apps_available", ["apps", "Demo", "--available", "--query", "Safari", "--limit", "7", "--all", "--json"]],
      ["open_desktop", ["open", "Demo", "--json"]],
      ["screenshot", ["screenshot", "Demo", "--inline", "--max-width", "1280", "--display", "2", "--json"]],
      ["activate", ["activate", "Demo", "com.example.Editor", "--json"]],
      ["move", ["move", "Demo", "12.25", "45.5", "--json"]],
      ["ax_frontmost", ["ax", "Demo", "frontmost", "--pid", "321", "--json"]],
      ["ax_windows", ["ax", "Demo", "windows", "--pid", "321", "--json"]],
      ["ax_element_at", ["ax", "Demo", "element-at", "50.5", "70.25", "--json"]],
      ["ax_perform", ["ax", "Demo", "perform", "--pid", "321", "--role", "AXButton", "--identifier", "save", "--action", "AXPress", "--json"]],
      ["ax_set_value", ["ax", "Demo", "set-value", "--pid", "321", "--identifier", "search", "--file", "-", "--json"]],
      ["windows", ["window", "Demo", "list", "--json"]],
      ["window_action", ["window", "Demo", "set-frame", "9", "321", "4", "1.25", "2.5", "800", "600", "--json"]],
      ["clipboard_read", ["clipboard", "Demo", "read", "--json"]],
      ["clipboard_write", ["clipboard", "Demo", "write", "--file", "-", "--json"]],
    ]);
    for (const [suffix, expected] of expectedArgv) {
      const first = pairedSuffixes.filter(name => name !== "capabilities").indexOf(suffix) * 2;
      assert.deepEqual(records[first].argv, expected, `${suffix} CLI mapping`);
    }

    const valueRecords = records[pairedSuffixes.filter(name => name !== "capabilities").indexOf("ax_set_value") * 2];
    assert.equal(valueRecords.stdin, JSON.stringify("MCP_TEST_VALUE"));
    assert.ok(!valueRecords.argv.includes("MCP_TEST_VALUE"), "AX values must stay off argv");
    const clipboardRecord = records[pairedSuffixes.filter(name => name !== "capabilities").indexOf("clipboard_write") * 2];
    assert.equal(clipboardRecord.stdin, "", "empty clipboard text is a valid write");
    assert.ok(!existsSync(markerPath), "resource text must never execute through a shell");
    const resourceRecord = records[pairedSuffixes.filter(name => name !== "capabilities").indexOf("open_resource") * 2];
    assert.ok(resourceRecord.argv.includes(`; touch ${markerPath}; #`), "resource is passed as a literal argv value");

    // Doctor exits 1 when a check fails. That is the report the caller asked
    // for, so it must arrive as content (with its fix) and not as a bridge
    // failure — otherwise an agent cannot relay the one thing that helps.
    writeMockMode(modePath, {
      exitCode: 1,
      results: {
        doctor: {
          ok: false,
          failed: 1,
          warned: 0,
          checks: [{
            name: "Input isolated",
            status: "fail",
            detail: "this session is the physical console",
            fix: "Switch back to your own account.",
          }],
        },
      },
    });
    const doctorReport = await server.request("tools/call", { name: "agent_doctor", arguments: {} });
    assert.equal(doctorReport.result?.isError, undefined, toolText(doctorReport.result));
    assert.match(toolText(doctorReport.result), /Input isolated/);
    assert.match(toolText(doctorReport.result), /Switch back to your own account/);

    // Validation mistakes stay inside MCP and never spawn the CLI.
    for (const invalid of [
      ["agent_ax_perform", { space: "Demo", identifier: "save", action: "AXPress", click: true }],
      ["agentspace_window_action", { space: "Demo", action: "set-frame", windowId: 9, pid: 321, generation: 4 }],
      ["agent_window_action", { space: "Demo", action: "close", windowId: 9, pid: 321, generation: 4, frame: { x: 0, y: 0, width: 500, height: 400 } }],
      ["agent_screenshot", { space: "Demo", display: 0 }],
    ]) {
      const before = cliCalls(logPath).length;
      const response = await server.request("tools/call", { name: invalid[0], arguments: invalid[1] });
      assert.ok(response.result?.isError === true || response.error, `${invalid[0]} must reject invalid arguments`);
      assert.equal(cliCalls(logPath).length, before, `${invalid[0]} validation must happen before CLI invocation`);
    }

    // Worker refusal codes and fixes cross the MCP boundary unchanged. The AX
    // value sentinel also verifies that secret-like content is absent from the
    // invocation context and failure text.
    writeMockMode(modePath, {
      code: "SESSION_IS_CONSOLE",
      message: "input refused for a console session",
      fix: "Sign in to the agent account session.",
    });
    const consoleFailure = await server.request("tools/call", {
      name: "agent_move", arguments: { space: "Demo", x: 1, y: 2 },
    });
    assert.equal(consoleFailure.result?.isError, true);
    assert.match(toolText(consoleFailure.result), /SESSION_IS_CONSOLE/);
    assert.match(toolText(consoleFailure.result), /input refused for a console session/);
    assert.match(toolText(consoleFailure.result), /Sign in to the agent account session/);

    writeMockMode(modePath, {
      code: "METHOD_NOT_FOUND",
      message: "worker needs an update",
      fix: "Update or reinstall the Worker.",
    });
    const methodFailure = await server.request("tools/call", {
      name: "agentspace_ax_set_value",
      arguments: { space: "Demo", identifier: "search", value: "MCP_TEST_VALUE" },
    });
    const methodFailureText = toolText(methodFailure.result);
    assert.equal(methodFailure.result?.isError, true);
    assert.match(methodFailureText, /METHOD_NOT_FOUND/);
    assert.match(methodFailureText, /worker needs an update/);
    assert.match(methodFailureText, /Update or reinstall the Worker/);
    assert.ok(!methodFailureText.includes("MCP_TEST_VALUE"), "AX value must not leak into context or errors");
    const errorCall = cliCalls(logPath).at(-1);
    assert.ok(!errorCall.argv.includes("MCP_TEST_VALUE"), "AX value must not leak into argv");
  } finally {
    await server.stop();
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("bundled launcher selects Node and completes MCP handshake", async () => {
  const launcherPath = path.join(packageDir, "launch.sh");
  assert.ok(existsSync(launcherPath), "launch.sh must be present in the package");
  const tempRoot = mkdtempSync(path.join(tmpdir(), "agentspace-mcp-launch-"));
  const nodeDir = path.join(tempRoot, "node-bin");
  mkdirSync(nodeDir);
  symlinkSync(process.execPath, path.join(nodeDir, "node"));
  const server = new McpProcess({
    PATH: nodeDir,
    HOME: tempRoot,
    AGENTSPACE_MCP_NODE: process.execPath,
    AGENTSPACE_BIN: undefined,
  }, "/bin/bash", [launcherPath]);

  try {
    const info = await server.initialize();
    assert.equal(info.serverInfo.name, "agentspace");
    const listed = await server.request("tools/list", {});
    assert.equal(listed.error, undefined, JSON.stringify(listed.error));
    assert.ok(listed.result?.tools?.length >= 62);
  } finally {
    await server.stop();
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("bundled launcher discovers PATH Node and rejects an invalid explicit override", () => {
  const launcherPath = path.join(packageDir, "launch.sh");
  const tempRoot = mkdtempSync(path.join(tmpdir(), "agentspace-mcp-node-"));
  const nodeDir = path.join(tempRoot, "node-bin");
  const invalidNode = path.join(tempRoot, "node14");
  mkdirSync(nodeDir);
  symlinkSync(process.execPath, path.join(nodeDir, "node"));
  writeFileSync(invalidNode, "#!/bin/sh\necho 14\n");
  chmodSync(invalidNode, 0o755);

  try {
    const auto = new McpProcess({
      PATH: nodeDir,
      HOME: tempRoot,
      AGENTSPACE_BIN: undefined,
    }, "/bin/bash", [launcherPath]);
    return (async () => {
      let info;
      try {
        info = await auto.initialize();
      } finally {
        await auto.stop();
      }
      assert.equal(info.serverInfo.name, "agentspace");

      const invalid = spawnSync("/bin/bash", [launcherPath], {
        cwd: packageDir,
        encoding: "utf8",
        env: {
          ...process.env,
          PATH: nodeDir,
          HOME: tempRoot,
          AGENTSPACE_MCP_NODE: invalidNode,
          AGENTSPACE_BIN: undefined,
        },
      });
      assert.equal(invalid.status, 1);
      assert.match(invalid.stderr, /AGENTSPACE_MCP_NODE must point to an executable Node\.js 18 or newer/);
      assert.doesNotMatch(invalid.stdout, /"jsonrpc"/, "invalid override must not fall back to PATH Node");
    })().finally(() => rmSync(tempRoot, { recursive: true, force: true }));
  } catch (error) {
    rmSync(tempRoot, { recursive: true, force: true });
    throw error;
  }
});

const temporaryAppBundle = process.env.AGENTSPACE_TEST_BUNDLE;
test("temporary app bundle launcher and CLI complete a real MCP list call", {
  skip: !temporaryAppBundle,
}, async () => {
  const app = path.resolve(temporaryAppBundle);
  const bundleRoot = path.join(app, "Contents", "Resources", "agentspace-mcp");
  const launcherPath = path.join(bundleRoot, "launch.sh");
  const cliPath = path.join(app, "Contents", "Helpers", "agentspace");
  assert.ok(existsSync(path.join(bundleRoot, "node_modules", "@modelcontextprotocol", "sdk")));
  assert.ok(existsSync(path.join(bundleRoot, "dist", "index.js")));
  assert.ok(existsSync(cliPath));

  const tempRoot = mkdtempSync(path.join(tmpdir(), "agentspace-mcp-bundle-root-"));
  const spacesDir = path.join(tempRoot, "Spaces");
  mkdirSync(spacesDir);
  writeFileSync(path.join(spacesDir, "index.json"), JSON.stringify({ spaces: [] }));
  const server = new McpProcess({
    AGENTSPACE_MCP_NODE: process.execPath,
    AGENTSPACE_BIN: cliPath,
    AGENTSPACE_ROOT: tempRoot,
  }, "/bin/bash", [launcherPath]);

  try {
    const info = await server.initialize();
    assert.equal(info.serverInfo.name, "agentspace");
    const listed = await server.request("tools/call", { name: "agent_list", arguments: {} });
    assert.equal(listed.result?.isError, undefined, toolText(listed.result));
    const accounts = JSON.parse(toolText(listed.result));
    assert.equal(accounts.count, 0);
    assert.deepEqual(accounts.accounts, []);
    assert.deepEqual(accounts.spaces, []);
  } finally {
    await server.stop();
    rmSync(tempRoot, { recursive: true, force: true });
  }
});
