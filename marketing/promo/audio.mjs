#!/usr/bin/env node
// Original score for the AgentSpace promo, synthesized from scratch.
// No samples, no dependencies, fully deterministic: the same file always
// produces the same WAV. 48 kHz / 16-bit stereo, 45 s, cut to the storyboard.
//
//   node audio.mjs --out /tmp/agentspace-promo.wav
import { writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const get = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const OUT = get("--out", path.join(path.dirname(fileURLToPath(import.meta.url)), "score.wav"));

const SR = 48000;
const DUR = 45;
const N = SR * DUR;
const TAU = Math.PI * 2;
const BAR = 3.0;          // 80 BPM, 4/4
const BEAT = 0.75;

const dryL = new Float32Array(N), dryR = new Float32Array(N);
const sendL = new Float32Array(N), sendR = new Float32Array(N);
const arpL = new Float32Array(N), arpR = new Float32Array(N);

const NOTE = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
function freq(name, octave = 0) {
  const m = /^([A-G])(#|b)?(-?\d)$/.exec(name);
  if (!m) throw new Error(`bad note ${name}`);
  const midi = 12 * (Number(m[3]) + 1) + NOTE[m[1]] + (m[2] === "#" ? 1 : m[2] === "b" ? -1 : 0) + octave * 12;
  return 440 * Math.pow(2, (midi - 69) / 12);
}
function mulberry32(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

function render(t0, dur, pan, send, fn, busL = dryL, busR = dryR) {
  const i0 = Math.max(0, Math.round(t0 * SR));
  const i1 = Math.min(N, Math.round((t0 + dur) * SR));
  const a = (clamp(pan, -1, 1) + 1) * Math.PI / 4;
  const gl = Math.cos(a), gr = Math.sin(a);
  for (let i = i0; i < i1; i++) {
    const v = fn((i - i0) / SR, i - i0);
    busL[i] += v * gl;
    busR[i] += v * gr;
    if (send) { sendL[i] += v * gl * send; sendR[i] += v * gr * send; }
  }
}

// ---------------------------------------------------------------- harmony
const CH = {
  Am9:   { root: "A1", pad: ["A3", "C4", "E4", "G4", "B4"], arp: ["A4", "C5", "E5", "G5", "B5"] },
  Fmaj9: { root: "F1", pad: ["F3", "A3", "C4", "E4", "G4"], arp: ["F4", "A4", "C5", "E5", "G5"] },
  Cmaj9: { root: "C2", pad: ["C4", "E4", "G4", "B4", "D5"], arp: ["C5", "E5", "G5", "B5", "D6"] },
  G6:    { root: "G1", pad: ["G3", "B3", "D4", "E4", "A4"], arp: ["G4", "B4", "D5", "E5", "A5"] },
};
const ORDER = ["Am9", "Fmaj9", "Cmaj9", "G6"];
const chordAt = t => {
  const b = Math.floor(t / BAR);
  return CH[b === 14 ? "Am9" : ORDER[b % 4]];
};
const PANS = [-0.38, 0.22, -0.12, 0.36, 0.04];

const pad = (t0, note, dur, pan, gain) => {
  const F = freq(note);
  const det = [0.9971, 1, 1.0029];
  const seed = mulberry32(Math.round(t0 * 97) + note.length * 13);
  const ph = [seed() * TAU, seed() * TAU, seed() * TAU];
  render(t0 + 0.03, dur, pan, 0.34, t => {
    const env = Math.min(1, t / 1.05) * Math.min(1, Math.max(0, (dur - t) / 1.5));
    const trem = 1 + 0.06 * Math.sin(TAU * 0.13 * t + ph[0]);
    let s = 0;
    for (let k = 0; k < 3; k++) {
      const p = TAU * F * det[k] * t + ph[k];
      s += Math.sin(p) + 0.22 * Math.sin(2 * p + 0.6) + 0.075 * Math.sin(3 * p + 1.4);
    }
    return s * env * trem * gain / 3;
  });
};

const bass = (t0, note, dur, gain) => {
  const F = freq(note);
  render(t0, dur, 0, 0.05, t => {
    const env = Math.min(1, t / 0.012)
      * (0.55 + 0.45 * Math.exp(-t * 0.7))
      * Math.min(1, Math.max(0, (dur - t) / 0.07));
    const p = TAU * F * t;
    const v = Math.sin(p) + 0.18 * Math.sin(2 * p) + 0.055 * Math.sin(3 * p);
    return Math.tanh(v * 1.25) * env * gain;
  });
};

const pluck = (t0, note, gain, pan) => {
  const F = freq(note);
  render(t0, 0.95, pan, 0.55, t => {
    const env = (1 - Math.exp(-t * 420)) * Math.exp(-t * 7.4);
    const p = TAU * F * t;
    return (Math.sin(p) + 0.26 * Math.sin(2 * p) + 0.08 * Math.sin(3 * p)) * env * gain;
  }, arpL, arpR);
};

const kick = (t0, gain) => {
  const rng = mulberry32(Math.round(t0 * 7919) + 11);
  let p = 0;
  render(t0, 0.5, 0, 0.02, t => {
    const f = 44 + 96 * Math.exp(-t * 28);
    p += TAU * f / SR;
    return Math.sin(p) * Math.exp(-t * 7.6) * gain + (rng() * 2 - 1) * Math.exp(-t * 260) * gain * 0.07;
  });
};

const hat = (t0, gain) => {
  const rng = mulberry32(Math.round(t0 * 104729) + 3);
  let prev = 0;
  render(t0, 0.085, 0, 0.04, t => {
    const n = rng() * 2 - 1;
    const hp = n - prev;
    prev = n;
    return hp * Math.exp(-t * 58) * gain;
  });
};

const impact = (t0, gain) => {
  const rng = mulberry32(Math.round(t0 * 3301) + 9);
  let p = 0;
  render(t0, 1.1, 0, 0.2, t => {
    const f = 34 + 66 * Math.exp(-t * 9);
    p += TAU * f / SR;
    const body = Math.sin(p) * Math.exp(-t * 3.4);
    const air = (rng() * 2 - 1) * Math.exp(-t * 14) * 0.22;
    return (body + air) * gain;
  });
};

const riser = (t0, t1, gain) => {
  const dur = t1 - t0;
  const rng = mulberry32(Math.round(t0 * 811) + 13);
  let p = 0;
  render(t0, dur, 0, 0.3, t => {
    const x = t / dur;
    p += TAU * (170 + 760 * x * x) / SR;
    return (Math.sin(p) * 0.55 + (rng() * 2 - 1) * 0.22) * Math.pow(x, 2.2) * gain;
  });
};

const bell = (t0, note, gain, pan = 0) => {
  const F = freq(note);
  const parts = [[1, 1, 4.2], [2.01, 0.52, 3.1], [2.76, 0.30, 2.3], [4.07, 0.16, 1.7], [5.43, 0.09, 1.25]];
  render(t0, 2.8, pan, 0.62, t => {
    let s = 0;
    for (const [m, a, d] of parts) s += Math.sin(TAU * F * m * t + m * 0.4) * a * Math.exp(-t * d);
    return (1 - Math.exp(-t * 320)) * s * gain;
  });
};

const tick = (t0, gain, pan = 0) => {
  const F = freq("A5");
  render(t0, 0.11, pan, 0.2, t => Math.sin(TAU * F * t) * Math.exp(-t * 55) * gain);
};

// ---------------------------------------------------------------- score
// 01 · intro: one chord, no pulse.
for (let b = 0; b < 15; b++) {
  const t = b * BAR;
  const ch = b === 14 ? CH.Am9 : CH[ORDER[b % 4]];
  ch.pad.forEach((n, i) => pad(t, n, BAR + 1.5, PANS[i], b === 0 ? 0.024 : 0.028));
}
impact(0.62, 0.20);
riser(3.0, 4.18, 0.035);

// 02 · pulse enters with the story. Bass and kick on the 4.2 s beat grid.
for (let t = 4.2; t < 40.19; t += BEAT) {
  const ch = chordAt(t);
  const sparse = t >= 30 && t < 35.4;
  if (sparse) {
    if (Math.abs(((t - 30) % 1.5 + 1.5) % 1.5) < 0.01) bass(t, ch.root, 0.7, 0.12);
  } else {
    bass(t, ch.root, 0.62, 0.145);
  }
}

const ARP = [0, 2, 1, 3, 2, 4, 3, 1];
for (let t = 4.2, i = 0; t < 44.0; t += BEAT / 2, i++) {
  if (t >= 29.9 && t < 35.4) {
    if (i % 4 === 0) pluck(t, "E5", 0.05, 0.1);
    continue;
  }
  const ch = chordAt(t);
  const n = ch.arp[ARP[i % ARP.length]];
  pluck(t, n, t >= 40.2 ? 0.045 : i % 2 ? 0.055 : 0.07, i % 2 ? 0.3 : -0.28);
}

for (let t = 4.2; t < 40.2; t += BEAT) {
  const fourth = t >= 24.6 && t < 30.0;
  const two = t >= 35.4;
  if (fourth || two) { kick(t, 0.115); }
  else if (Math.round((t - 4.2) / BEAT) % 2 === 0) { kick(t, 0.10); }
}
for (let t = 4.2 + BEAT / 2; t < 30.0; t += BEAT) hat(t, 0.015);
for (let t = 35.4 + BEAT / 2; t < 40.2; t += BEAT) hat(t, 0.018);

// 03 · transitions and hits, placed on what is on screen.
impact(4.2, 0.13);
riser(15.5, 16.95, 0.05);
impact(17.0, 0.16);
[12.12, 12.24, 12.36].forEach((t, i) => tick(t, 0.05 - i * 0.006, -0.2 + i * 0.2));
bell(21.55, "E5", 0.055, -0.2);
bell(21.55, "A5", 0.042, 0.25);
bell(23.05, "C6", 0.04, 0.15);
riser(23.4, 24.58, 0.045);
impact(24.6, 0.16);

// 04 · safety: pulse drops out, a low hit marks the refusal.
impact(30.0, 0.20);
impact(32.08, 0.16);
riser(34.0, 35.38, 0.05);
impact(35.4, 0.16);

// 05 · connect: the client wall arrives as a run of soft high plucks.
[36.9, 37.15, 37.4, 37.7, 38.0, 38.25].forEach((t, i) =>
  pluck(t, ["E5", "G5", "B5", "E6", "G6", "B6"][i], 0.035, i % 2 ? 0.35 : -0.35));
bell(38.6, "A5", 0.05, 0);
bell(38.6, "E6", 0.034, 0.2);
riser(38.9, 40.18, 0.04);

// 06 · outro: the last chord resolves, then one soft bell.
impact(40.2, 0.12);
bell(43.6, "A4", 0.05, 0);
bell(43.6, "E5", 0.038, 0.2);
bell(44.15, "A5", 0.028, 0);

// ---------------------------------------------------------------- delay
{
  const d = Math.round(0.375 * SR);
  const outL = new Float32Array(N), outR = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    outL[i] = arpL[i] + (i >= d ? arpR[i - d] * 0.30 : 0);
    outR[i] = arpR[i] + (i >= d ? arpL[i - d] * 0.30 : 0);
  }
  for (let i = 0; i < N; i++) {
    dryL[i] += outL[i] * 0.55;
    dryR[i] += outR[i] * 0.55;
    sendL[i] += outL[i] * 0.30;
    sendR[i] += outR[i] * 0.30;
  }
}

// ---------------------------------------------------------------- reverb
function reverb(input, spread) {
  const damp = 0.34, room = 0.82;
  const combs = [1116, 1188, 1277, 1356, 1422, 1491].map(v => Math.round((v + spread) * SR / 44100));
  const out = new Float32Array(N);
  for (const d of combs) {
    const buf = new Float32Array(d);
    let idx = 0, lp = 0;
    for (let i = 0; i < N; i++) {
      const y = buf[idx];
      lp = y * (1 - damp) + lp * damp;
      buf[idx] = input[i] + lp * room;
      out[i] += y;
      idx = (idx + 1) % d;
    }
  }
  for (let i = 0; i < N; i++) out[i] *= 1 / combs.length;
  for (const d0 of [556, 441, 341, 225]) {
    const d = Math.round(d0 * SR / 44100);
    const buf = new Float32Array(d);
    let idx = 0;
    for (let i = 0; i < N; i++) {
      const b = buf[idx];
      const y = -out[i] + b;
      buf[idx] = out[i] + b * 0.5;
      out[i] = y;
      idx = (idx + 1) % d;
    }
  }
  return out;
}
const wetL = reverb(sendL, 0);
const wetR = reverb(sendR, 23);

// ---------------------------------------------------------------- master
let peak = 0, sum = 0;
const hpA = 0.9963;
let hpL = 0, hpR = 0, prevL = 0, prevR = 0;
for (let i = 0; i < N; i++) {
  let l = dryL[i] + wetL[i] * 0.60;
  let r = dryR[i] + wetR[i] * 0.60;
  const a = hpA;
  const yl = a * (hpL + l - prevL); hpL = yl; prevL = l;
  const yr = a * (hpR + r - prevR); hpR = yr; prevR = r;
  l = Math.tanh(yl * 1.12) * 0.98;
  r = Math.tanh(yr * 1.12) * 0.98;
  const t = i / SR;
  const fade = Math.min(1, t / 0.22) * Math.min(1, Math.max(0, (DUR - t) / 1.15));
  l *= fade; r *= fade;
  dryL[i] = l; dryR[i] = r;
  peak = Math.max(peak, Math.abs(l), Math.abs(r));
  sum += l * l + r * r;
}
const norm = peak > 0 ? 0.89 / peak : 1;
for (let i = 0; i < N; i++) { dryL[i] *= norm; dryR[i] *= norm; }
const rms = Math.sqrt(sum / (N * 2)) * norm;
console.log(`score: ${DUR}s, peak ${(0.89).toFixed(2)} after x${norm.toFixed(2)}, rms ${rms.toFixed(3)}`);

// ---------------------------------------------------------------- wav
mkdirSync(path.dirname(OUT), { recursive: true });
const buf = Buffer.alloc(44 + N * 4);
buf.write("RIFF", 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write("WAVE", 8);
buf.write("fmt ", 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20);
buf.writeUInt16LE(2, 22); buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28);
buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34);
buf.write("data", 36); buf.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) {
  buf.writeInt16LE(Math.round(clamp(dryL[i], -1, 1) * 32767), 44 + i * 4);
  buf.writeInt16LE(Math.round(clamp(dryR[i], -1, 1) * 32767), 46 + i * 4);
}
writeFileSync(OUT, buf);
console.log(`wrote ${OUT}`);
