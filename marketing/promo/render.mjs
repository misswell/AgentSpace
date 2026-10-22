#!/usr/bin/env node
// Deterministic frame renderer for marketing/promo/promo.html.
// Drives headless Chrome over CDP: seek(t) -> screenshot, one PNG per frame.
// No npm dependencies (Node >= 22 global fetch/WebSocket).
//
// Usage:
//   node render.mjs --preview 3.2,8.4,20.1 --lang en --out /tmp/promo-preview
//   node render.mjs --lang zh                    # 45 s @ 30 fps, 1920x1080
//   node render.mjs --lang en --vertical         # 1080x1920
//   node render.mjs --lang zh --audio score.wav --mp4 promo.mp4
//   node render.mjs --fps 30 --dur 45 --from 10 --to 20 --out ./frames
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, rmSync, readdirSync, unlinkSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const get = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const has = k => args.includes(k);

const fps = Number(get("--fps", 30));
const dur = Number(get("--dur", 45));
const outDir = get("--out", path.join(__dirname, "frames"));
const preview = get("--preview", null);
const vertical = has("--vertical");
const lang = get("--lang", "zh") === "en" ? "en" : "zh";
const from = Number(get("--from", 0));
const to = Number(get("--to", dur));
const mp4 = get("--mp4", null);
const audio = get("--audio", null);
const crf = get("--crf", "18");
const preset = get("--preset", "slow");
const W = vertical ? 1080 : 1920;
const H = vertical ? 1920 : 1080;
if (mp4 && preview) { console.error("--mp4 needs a full render, not --preview"); process.exit(1); }
if (audio) { try { readFileSync(path.resolve(audio)); } catch { console.error(`audio file not found: ${audio}`); process.exit(1); } }

const CHROME_CANDIDATES = [
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
];
const chrome = CHROME_CANDIDATES.find(p => { try { readFileSync(p); return true; } catch { return false; } });
if (!chrome) { console.error("no Chrome/Edge/Chromium found"); process.exit(1); }

mkdirSync(outDir, { recursive: true });
if (!preview) {
  // Never mix a new render with stale frames from a previous one.
  for (const f of readdirSync(outDir)) {
    if (/^frame_\d{5}\.png$/.test(f) || /^preview_.*\.png$/.test(f)) unlinkSync(path.join(outDir, f));
  }
}
const profile = mkdtempSync("/tmp/agentspace-promo-chrome-");
const query = `?lang=${lang}${vertical ? "&v=1" : ""}`;
const url = "file://" + path.join(__dirname, "promo.html") + query;
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

let page = null;
for (let i = 0; i < 50 && !page; i++) {
  const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  page = list.find(t => t.type === "page" && t.url.includes("promo.html"));
  if (!page) await sleep(100);
}
if (!page) { console.error("no promo page target"); cp.kill(); process.exit(1); }

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
// Exact viewport: the previous pipeline depended on window chrome being
// exactly W×H and left a black band when it was not.
await send("Emulation.setDeviceMetricsOverride", {
  width: W, height: H, deviceScaleFactor: 1, mobile: false,
  screenWidth: W, screenHeight: H, positionX: 0, positionY: 0,
});
await send("Page.reload", { ignoreCache: true });
await sleep(500);
await send("Runtime.evaluate", {
  expression: `(async () => {
    await document.fonts.ready;
    await Promise.all([...document.images].map(i => i.decode().catch(() => {})));
    for (let i = 0; i < 100 && !window.__meta; i++) await new Promise(r => setTimeout(r, 50));
    return JSON.stringify(window.__meta || null);
  })()`,
  awaitPromise: true,
});
const metaRaw = await send("Runtime.evaluate", { expression: `JSON.stringify(window.__meta)`, returnByValue: true });
const meta = JSON.parse(metaRaw.result?.result?.value || "null");
if (!meta || meta.lang !== lang || meta.vertical !== vertical) {
  console.error("page did not boot with the requested meta", meta); cp.kill(); process.exit(1);
}
const stageBox = await send("Runtime.evaluate", {
  expression: `(() => { const s = document.getElementById("stage"); const r = s.getBoundingClientRect();
     return JSON.stringify({ x: r.x, y: r.y, w: s.offsetWidth, h: s.offsetHeight, vw: innerWidth, vh: innerHeight }); })()`,
  returnByValue: true,
});
const box = JSON.parse(stageBox.result.result.value);
if (box.w !== W || box.h !== H || box.vw !== W || box.vh !== H) {
  console.error("viewport/stage mismatch", box); cp.kill(); process.exit(1);
}
const clip = { x: box.x, y: box.y, width: box.w, height: box.h, scale: 1 };
console.log(`${lang}${vertical ? " vertical" : ""}: stage ${box.w}x${box.h}, viewport ${box.vw}x${box.vh}`);
{
  const probe = await send("Runtime.evaluate", {
    expression: `(() => { try {
      window.__seek(2.6);
      return JSON.stringify({ ok:true, fade:document.getElementById("fade").style.opacity,
        s0:getComputedStyle(document.getElementById("s0")).opacity,
        tag:document.getElementById("s0tag").style.opacity,
        seek:typeof window.__seek });
    } catch (e) { return JSON.stringify({ ok:false, err:String(e), stack:String(e.stack) }); } })()`,
    returnByValue: true,
  });
  const pv = probe.result?.result?.value;
  if (pv && !JSON.parse(pv).ok) { console.error("seek probe failed", pv); cp.kill(); process.exit(1); }
  if (has("--debug")) console.log("probe:", pv);
}

const total = Math.round(dur * fps);
const startFrame = Math.max(0, Math.round(from * fps));
const endFrame = Math.min(total, Math.round(to * fps));
const frames = preview
  ? preview.split(",").map(s => Math.round(Number(s) * fps))
  : Array.from({ length: endFrame - startFrame }, (_, i) => startFrame + i);

const t0 = Date.now();
for (const f of frames) {
  const t = f / fps;
  await send("Runtime.evaluate", { expression: `window.__seek(${t.toFixed(4)})` });
  const shot = await send("Page.captureScreenshot", { format: "png", optimizeForSpeed: true, clip, captureBeyondViewport: false });
  if (!shot.result?.data) { console.error(`frame ${f}: empty screenshot`); cp.kill(); process.exit(1); }
  const name = preview ? `preview_${t.toFixed(2)}.png` : `frame_${String(f).padStart(5, "0")}.png`;
  writeFileSync(path.join(outDir, name), Buffer.from(shot.result.data, "base64"));
  if (f % 30 === 0) console.log(`frame ${f}/${total}  t=${t.toFixed(2)}s  (${((Date.now() - t0) / 1000).toFixed(0)}s elapsed)`);
}
if (mp4) {
  const ffArgs = [
    "-y", "-hide_banner", "-loglevel", "warning",
    "-framerate", String(fps), "-start_number", String(frames[0] ?? startFrame),
    "-i", path.join(outDir, "frame_%05d.png"),
  ];
  if (audio) ffArgs.push("-i", path.resolve(audio));
  ffArgs.push("-map", "0:v:0");
  if (audio) ffArgs.push("-map", "1:a:0", "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-shortest");
  ffArgs.push("-c:v", "libx264", "-profile:v", "high", "-preset", preset, "-crf", String(crf),
    "-pix_fmt", "yuv420p", "-movflags", "+faststart", path.resolve(mp4));
  const dest = path.resolve(mp4);
  await new Promise((res, rej) => {
    const ff = spawn("ffmpeg", ffArgs, { stdio: ["ignore", "ignore", "inherit"] });
    ff.on("error", rej);
    ff.on("close", code => code === 0 ? res() : rej(new Error(`ffmpeg exited ${code}`)));
  });
  console.log(`wrote ${dest}${audio ? " (with audio)" : ""}`);
}
finished = true;
console.log(`rendered ${frames.length} frames -> ${outDir} in ${((Date.now() - t0) / 1000).toFixed(0)}s`);
cp.kill();
await sleep(300);
try { rmSync(profile, { recursive: true, force: true }); } catch {}
ws.close();
