#!/usr/bin/env node
// Deterministic frame renderer for marketing/promo/promo.html.
// Drives headless Chrome over CDP: seek(t) -> screenshot, one PNG per frame.
// No npm dependencies (Node >= 22 global fetch/WebSocket).
//
// Usage:
//   node render.mjs --preview 1.2,6.5,15.6   # render a few sample times
//   node render.mjs                          # render the whole video (38 s @ 30 fps)
//   node render.mjs --vertical               # 1080x1920 variant
//   node render.mjs --fps 30 --dur 38 --out ./frames
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const get = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const has = k => args.includes(k);

const fps = Number(get("--fps", 30));
const dur = Number(get("--dur", 38));
const outDir = get("--out", path.join(__dirname, "frames"));
const preview = get("--preview", null);
const vertical = has("--vertical");
const W = vertical ? 1080 : 1920;
const H = vertical ? 1920 : 1080;

const CHROME_CANDIDATES = [
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
];
const chrome = CHROME_CANDIDATES.find(p => { try { readFileSync(p); return true; } catch { return false; } });
if (!chrome) { console.error("no Chrome/Edge/Chromium found"); process.exit(1); }

mkdirSync(outDir, { recursive: true });
const profile = mkdtempSync("/tmp/agentspace-promo-chrome-");
const url = "file://" + path.join(__dirname, "promo.html") + (vertical ? "?v=1" : "");
const cp = spawn(chrome, [
  "--headless=new",
  "--remote-debugging-port=0",
  `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check",
  `--window-size=${W},${H}`,
  "--force-device-scale-factor=1",
  "--force-color-profile=srgb",
  "--hide-scrollbars",
  "--disable-lcd-text",
  url,
], { stdio: "ignore" });

const sleep = ms => new Promise(r => setTimeout(r, ms));
let port = null;
for (let i = 0; i < 150 && !port; i++) {
  await sleep(200);
  try { port = readFileSync(path.join(profile, "DevToolsActivePort"), "utf8").split("\n")[0].trim(); } catch {}
}
if (!port) { console.error("chrome did not expose a DevTools port"); cp.kill(); process.exit(1); }

const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const page = list.find(t => t.type === "page");
if (!page) { console.error("no page target"); cp.kill(); process.exit(1); }

const ws = new WebSocket(page.webSocketDebuggerUrl);
let finished = false;
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
ws.onclose = () => { if (!finished) { console.error("DevTools connection closed early — aborting so no stale frames are left behind"); process.exit(2); } };

let nextId = 0;
const pending = new Map();
ws.onmessage = ev => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
};
const send = (method, params = {}) => new Promise(res => {
  const id = ++nextId;
  pending.set(id, res);
  ws.send(JSON.stringify({ id, method, params }));
});

await send("Page.enable");
await send("Runtime.enable");
await sleep(700);
// settle: fonts (system) + images (icon.png) fully decoded before any frame
await send("Runtime.evaluate", {
  expression: `Promise.all([...document.images].map(i => i.decode().catch(() => {}))).then(() => "ok")`,
  awaitPromise: true,
});
// capture the #stage element itself, independent of window chrome eating viewport height
const stageBox = await send("Runtime.evaluate", {
  expression: `(() => { const s = document.getElementById("stage");
     const r = s.getBoundingClientRect();
     return JSON.stringify({ x: r.x, y: r.y, w: s.offsetWidth, h: s.offsetHeight }); })()`,
  returnByValue: true,
});
const box = JSON.parse(stageBox.result.result.value);
const clip = { x: box.x, y: box.y, width: box.w, height: box.h, scale: 1 };
console.log(`stage clip: ${box.w}x${box.h} at (${box.x},${box.y})`);

const total = Math.round(dur * fps);
const frames = preview
  ? preview.split(",").map(s => Math.round(Number(s) * fps))
  : Array.from({ length: total }, (_, i) => i);

const t0 = Date.now();
for (const f of frames) {
  const t = f / fps;
  await send("Runtime.evaluate", { expression: `window.__seek(${t.toFixed(4)})` });
  const shot = await send("Page.captureScreenshot", { format: "png", optimizeForSpeed: true, clip, captureBeyondViewport: true });
  writeFileSync(path.join(outDir, `frame_${String(f).padStart(5, "0")}.png`), Buffer.from(shot.result.data, "base64"));
  if (f % 60 === 0) console.log(`frame ${f}/${total}  t=${t.toFixed(2)}s  (${((Date.now() - t0) / 1000).toFixed(0)}s elapsed)`);
}
const scene = await send("Runtime.evaluate", { expression: `window.__sceneAt(${(dur - 0.01).toFixed(2)})`, returnByValue: true });
finished = true;
console.log("final scene:", scene.result?.result?.value, `| ${frames.length} frames -> ${outDir}`);
cp.kill();
await sleep(300);
try { rmSync(profile, { recursive: true, force: true }); } catch {}
ws.close();
console.log("done");
