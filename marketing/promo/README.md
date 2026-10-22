# AgentSpace 宣传动画

本目录是产品宣传动画的**可复现源工程**：动画由一个纯时间驱动的 HTML
(`promo.html`) 定义，配乐由 `audio.mjs` 确定性合成，逐帧截图后由
`render.mjs` 调用 ffmpeg 合成带音轨的 H.264 MP4。成片四种版本：

- `AgentSpace-Promo-1080p.mp4` — 中文 · 1920×1080 · 30 fps · 45.0 s
- `AgentSpace-Promo-Vertical-1080x1920.mp4` — 中文 · 1080×1920（9:16）
- `AgentSpace-Promo-EN-1080p.mp4` — 英文 · 1920×1080 · 30 fps · 45.0 s
- `AgentSpace-Promo-EN-Vertical-1080x1920.mp4` — 英文 · 1080×1920
- `poster.png` — 封面图（中文 16:9 结尾定帧，t ≈ 43.5 s）

四版均为 H.264 High、yuv420p、CRF 18、faststart，附 AAC 192 kbps
48 kHz 立体声原创配乐。内容为八幕 motion graphics：开场 → 一台 Mac 两个
桌面 → 不是虚拟机（真实会话）→ 连接应用 → 多代理并行 → 安全内建（拒绝
在物理控制台注入）→ 24 个客户端 / 22 个 MCP 工具 → 结尾 CTA。文案口径与
README/v3-plan 一致；**全程不出现二维码**，下载地址只以文字
`github.com/misswell/AgentSpace` 呈现。

## 重新渲染

依赖：Node ≥ 22、Chrome（或 Edge/Chromium）、ffmpeg。零 npm 依赖。

```sh
# 配乐（48 kHz / 立体声 / 45 s，确定性合成，约 3 秒）
node audio.mjs --out /tmp/agentspace-promo.wav

# 预览若干关键时间点（快速自查）
node render.mjs --preview 3.8,9.8,20.5,32.6 --out /tmp/promo-preview
node render.mjs --vertical --lang en --preview 9.8,22.5 --out /tmp/promo-preview-v-en

# 全量渲染 + 合成：中文 16:9 / 中文竖版 / 英文 16:9 / 英文竖版
node render.mjs --lang zh --audio /tmp/agentspace-promo.wav \
  --mp4 AgentSpace-Promo-1080p.mp4
node render.mjs --lang zh --vertical --audio /tmp/agentspace-promo.wav \
  --mp4 AgentSpace-Promo-Vertical-1080x1920.mp4
node render.mjs --lang en --audio /tmp/agentspace-promo.wav \
  --mp4 AgentSpace-Promo-EN-1080p.mp4
node render.mjs --lang en --vertical --audio /tmp/agentspace-promo.wav \
  --mp4 AgentSpace-Promo-EN-Vertical-1080x1920.mp4

# 封面（从中文 16:9 的结尾定帧取）
node render.mjs --lang zh --preview 43.5 --out /tmp/promo-poster
cp /tmp/promo-poster/preview_43.50.png poster.png
```

`render.mjs` 会把 `--mp4` 之前的 PNG 帧留在 `--out` 目录（默认
`./frames`），并直接用 ffmpeg 混流；编码参数固定为
`libx264 -profile:v high -preset slow -crf 18 -pix_fmt yuv420p
-movflags +faststart`，音轨为 AAC 192 kbps / 48 kHz / 立体声。

## 结构

- `promo.html` — 全部场景、样式与时间线（`window.__seek(t)` 是唯一入口，
  同一 `t` 永远渲染同一画面；粒子/网格/飞行动画全部由种子化伪随机与
  确定性函数驱动，不含 `Math.random`/`Date.now`）。双语文案在文件内的
  `TX` 表中，`?lang=zh|en` 与 `?v=1`（竖版）由 `render.mjs` 传入。
- `audio.mjs` — 原创配乐合成器：80 BPM，Am9 → Fmaj9 → Cmaj9 → G6，
  加法合成 pad、低音、拨弦琶音、合成鼓组与转场音效，经 Schroeder 混响、
  乒乓延迟与软限幅后归一化到 -1 dBFS 峰值。无采样、无随机源。
- `icon.png` — 取自 `apps/AgentSpace/Resources/AppIcon.icns` 的 1024 px 导出。
- `render.mjs` — 无头 Chrome + CDP 逐帧截图（`Runtime.evaluate` seek →
  `Page.captureScreenshot`），可选直接调用 ffmpeg 混流。

改文案或配色只动 `promo.html`；改时长需同步调整各场景 `t0/t1`、
`audio.mjs` 的 `DUR` 与 `render.mjs --dur`。
