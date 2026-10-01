# AgentSpace 宣传动画

本目录是产品宣传动画的**可复现源工程**：动画由一个纯时间驱动的 HTML
(`promo.html`) 定义，逐帧截图后用 ffmpeg 合成 H.264 MP4。成片：

- `AgentSpace-Promo-1080p.mp4` — 1920×1080 · 30 fps · 38.0 s · H.264 · 无声
- `AgentSpace-Promo-Vertical-1080x1920.mp4` — 1080×1920（9:16）竖版，同源渲染
- `poster.png` — 封面图（取自结尾定帧）

内容为七幕 motion graphics：开场 → 产品定位（对比虚拟机/远程控制）→
真实驱动桌面 → 多代理并行 → 安全内建 → MCP/CLI 接入 → 结尾 CTA。
文案口径与 README/v3-plan 一致；**全程不出现二维码**，下载地址只以文字
`github.com/misswell/AgentSpace` 呈现。

## 重新渲染

依赖：Node ≥ 22、Chrome（或 Edge/Chromium）、ffmpeg。零 npm 依赖。

```sh
# 预览若干关键时间点（快速自查）
node render.mjs --preview 3.8,9.8,15.0,26.6 --out /tmp/promo-preview

# 全量渲染（38 s × 30 fps = 1140 帧，输出 PNG 到指定目录）
node render.mjs --out /tmp/promo-frames

# 竖版
node render.mjs --vertical --out /tmp/promo-frames-v

# 合成（像素格式 yuv420p，faststart，无声）
ffmpeg -y -framerate 30 -i /tmp/promo-frames/frame_%05d.png \
  -c:v libx264 -profile:v high -preset slow -crf 18 -pix_fmt yuv420p \
  -movflags +faststart AgentSpace-Promo-1080p.mp4

# 封面
cp /tmp/promo-frames/frame_01100.png poster.png   # t ≈ 36.7 s 的结尾定帧
```

## 结构

- `promo.html` — 全部场景、样式与时间线（`window.__seek(t)` 是唯一入口，
  同一 `t` 永远渲染同一画面；粒子/网格/飞行动画全部由种子化伪随机与
  确定性函数驱动，不含 `Math.random`/`Date.now`）。
- `icon.png` — 取自 `apps/AgentSpace/Resources/AppIcon.icns` 的 512 px 导出。
- `render.mjs` — 无头 Chrome + CDP 逐帧截图（`Runtime.evaluate` seek →
  `Page.captureScreenshot`）。

改文案或配色只动 `promo.html`；改时长需同步调整各场景 `t0/t1` 与
`render.mjs --dur`。
