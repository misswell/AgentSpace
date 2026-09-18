// Plain `node --test` tests for the pure argument builders.
//
// These import the *compiled* module (`dist/args.js`) on purpose: nothing here
// spawns a process or touches macOS, so the only build step needed is `tsc`.
// Run with:
//   npm run build && node --test test/
//
// If `dist/args.js` is missing, run `npm run build` first.

import test from "node:test";
import assert from "node:assert/strict";

import {
  ArgError,
  buildAppsArgs,
  buildAxSnapshotArgs,
  buildClickArgs,
  buildDragArgs,
  buildExecArgs,
  buildInputArgs,
  buildKeyArgs,
  buildLaunchArgs,
  buildListArgs,
  buildQuitArgs,
  buildScreenshotArgs,
  buildScrollArgs,
  buildStatusArgs,
  buildTypeArgs,
  serializeActions,
} from "../dist/args.js";

const SPACE = "research";

test("list always passes --json", () => {
  assert.deepEqual(buildListArgs(), ["list", "--json"]);
});

test("status omits the space when none is given", () => {
  assert.deepEqual(buildStatusArgs(), ["status", "--json"]);
  assert.deepEqual(buildStatusArgs(SPACE), ["status", SPACE, "--json"]);
});

test("click builds the documented argv", () => {
  assert.deepEqual(buildClickArgs(SPACE, 10, 20), [
    "click",
    SPACE,
    "10",
    "20",
    "--json",
  ]);
});

test("click passes --double and --right", () => {
  assert.deepEqual(buildClickArgs(SPACE, 10, 20, { double: true }), [
    "click",
    SPACE,
    "10",
    "20",
    "--double",
    "--json",
  ]);
  assert.deepEqual(buildClickArgs(SPACE, 10, 20, { right: true }), [
    "click",
    SPACE,
    "10",
    "20",
    "--right",
    "--json",
  ]);
});

test("click keeps fractional point coordinates", () => {
  assert.deepEqual(buildClickArgs(SPACE, 10.5, 20.25), [
    "click",
    SPACE,
    "10.5",
    "20.25",
    "--json",
  ]);
});

test("click rejects a missing or bad space and non-numeric coordinates", () => {
  assert.throws(() => buildClickArgs("", 1, 2), ArgError);
  assert.throws(() => buildClickArgs("   ", 1, 2), ArgError);
  // The explicit `undefined`/NaN cases are what a tool call looks like when the
  // argument was never supplied.
  assert.throws(() => buildClickArgs(SPACE, undefined, 2), ArgError);
  assert.throws(() => buildClickArgs(SPACE, 1, Number.NaN), ArgError);
  assert.throws(() => buildClickArgs(SPACE, 1, Number.POSITIVE_INFINITY), ArgError);
});

test("type passes the text through and guards a leading hyphen", () => {
  assert.deepEqual(buildTypeArgs(SPACE, "hello"), ["type", SPACE, "hello", "--json"]);
  assert.deepEqual(buildTypeArgs(SPACE, "two words"), [
    "type",
    SPACE,
    "two words",
    "--json",
  ]);
  // Free text that looks like a flag must not be parsed as one.
  assert.deepEqual(buildTypeArgs(SPACE, "--json"), [
    "type",
    SPACE,
    "--json",
    "--",
    "--json",
  ]);
  assert.throws(() => buildTypeArgs(SPACE, ""), ArgError);
});

test("key builds a combo argument", () => {
  assert.deepEqual(buildKeyArgs(SPACE, "cmd+l"), ["key", SPACE, "cmd+l", "--json"]);
  assert.throws(() => buildKeyArgs(SPACE, ""), ArgError);
});

test("scroll requires integer deltas", () => {
  assert.deepEqual(buildScrollArgs(SPACE, 0, -500), [
    "scroll",
    SPACE,
    "0",
    "-500",
    "--json",
  ]);
  assert.throws(() => buildScrollArgs(SPACE, 1.5, 0), ArgError);
  assert.throws(() => buildScrollArgs(SPACE, 0, undefined), ArgError);
});

test("drag passes four point coordinates", () => {
  assert.deepEqual(buildDragArgs(SPACE, 1, 2, 50, 60), [
    "drag",
    SPACE,
    "1",
    "2",
    "50",
    "60",
    "--json",
  ]);
  assert.throws(() => buildDragArgs(SPACE, 1, 2, 50), ArgError);
});

test("screenshot always asks for --inline and maps its flags", () => {
  assert.deepEqual(buildScreenshotArgs(SPACE), ["screenshot", SPACE, "--inline", "--json"]);
  assert.deepEqual(buildScreenshotArgs(SPACE, { maxWidth: 1200, display: 1 }), [
    "screenshot",
    SPACE,
    "--inline",
    "--max-width",
    "1200",
    "--display",
    "1",
    "--json",
  ]);
  assert.deepEqual(buildScreenshotArgs(SPACE, { out: "/tmp/shot.png" }), [
    "screenshot",
    SPACE,
    "--inline",
    "--out",
    "/tmp/shot.png",
    "--json",
  ]);
  assert.throws(() => buildScreenshotArgs(SPACE, { maxWidth: 1.5 }), ArgError);
});

test("input reads the batch from stdin", () => {
  assert.deepEqual(buildInputArgs(SPACE), ["input", SPACE, "--file", "-", "--json"]);
  assert.throws(() => buildInputArgs(""), ArgError);
});

test("serializeActions emits the JSON array for stdin", () => {
  const actions = [{ type: "move", x: 1, y: 2 }];
  assert.equal(serializeActions(actions), JSON.stringify(actions));
  assert.throws(() => serializeActions([]), ArgError);
});

test("launch and quit map app and --force", () => {
  assert.deepEqual(buildLaunchArgs(SPACE, "Safari"), ["launch", SPACE, "Safari", "--json"]);
  assert.deepEqual(buildQuitArgs(SPACE, "Safari"), ["quit", SPACE, "Safari", "--json"]);
  assert.deepEqual(buildQuitArgs(SPACE, "Safari", { force: true }), [
    "quit",
    SPACE,
    "Safari",
    "--force",
    "--json",
  ]);
  assert.throws(() => buildLaunchArgs(SPACE, ""), ArgError);
});

test("apps passes the space", () => {
  assert.deepEqual(buildAppsArgs(SPACE), ["apps", SPACE, "--json"]);
  assert.throws(() => buildAppsArgs(""), ArgError);
});

test("exec passes --cwd, --timeout and --env", () => {
  assert.deepEqual(buildExecArgs(SPACE, "ls -la"), ["exec", SPACE, "ls -la", "--json"]);

  const args = buildExecArgs(SPACE, "ls", { cwd: "/tmp/work" });
  assert.deepEqual(args, ["exec", SPACE, "ls", "--cwd", "/tmp/work", "--json"]);
  assert.ok(args.includes("--cwd"));
  assert.equal(args[args.indexOf("--cwd") + 1], "/tmp/work");

  assert.deepEqual(buildExecArgs(SPACE, "sleep 1", { timeoutMs: 5000 }), [
    "exec",
    SPACE,
    "sleep 1",
    "--timeout",
    "5000",
    "--json",
  ]);

  assert.deepEqual(buildExecArgs(SPACE, "env", { env: { FOO: "bar", N: "2" } }), [
    "exec",
    SPACE,
    "env",
    "--env",
    "FOO=bar",
    "--env",
    "N=2",
    "--json",
  ]);
});

test("exec rejects bad options and keeps a leading-hyphen command safe", () => {
  assert.throws(() => buildExecArgs(SPACE, ""), ArgError);
  assert.throws(() => buildExecArgs(SPACE, "ls", { cwd: "" }), ArgError);
  assert.throws(() => buildExecArgs(SPACE, "ls", { timeoutMs: 0.5 }), ArgError);
  assert.throws(() => buildExecArgs(SPACE, "ls", { env: { "": "x" } }), ArgError);
  assert.throws(() => buildExecArgs(SPACE, "ls", { env: { "A=B": "x" } }), ArgError);

  assert.deepEqual(buildExecArgs(SPACE, "--help"), [
    "exec",
    SPACE,
    "--json",
    "--",
    "--help",
  ]);
});

test("ax snapshot maps depth, node and all flags", () => {
  assert.deepEqual(buildAxSnapshotArgs(SPACE), ["ax", SPACE, "snapshot", "--json"]);
  assert.deepEqual(
    buildAxSnapshotArgs(SPACE, { pid: 42, maxDepth: 3, maxNodes: 10, all: true }),
    [
      "ax",
      SPACE,
      "snapshot",
      "--pid",
      "42",
      "--max-depth",
      "3",
      "--max-nodes",
      "10",
      "--all",
      "--json",
    ],
  );
  assert.throws(() => buildAxSnapshotArgs(SPACE, { pid: 1.5 }), ArgError);
});

test("no builder ever returns a shell string", () => {
  // A cheap invariant test: every builder returns an array of strings, so
  // spawn() can never hand a value to a shell.
  const all = [
    buildListArgs(),
    buildStatusArgs(SPACE),
    buildScreenshotArgs(SPACE),
    buildInputArgs(SPACE),
    buildClickArgs(SPACE, 1, 2),
    buildTypeArgs(SPACE, "hi"),
    buildKeyArgs(SPACE, "enter"),
    buildScrollArgs(SPACE, 0, -1),
    buildDragArgs(SPACE, 0, 0, 1, 1),
    buildLaunchArgs(SPACE, "Finder"),
    buildQuitArgs(SPACE, "Finder"),
    buildAppsArgs(SPACE),
    buildExecArgs(SPACE, "true"),
    buildAxSnapshotArgs(SPACE),
  ];
  for (const args of all) {
    assert.ok(Array.isArray(args));
    assert.ok(args.every((arg) => typeof arg === "string"));
    assert.equal(args.at(-1), "--json");
  }
});
