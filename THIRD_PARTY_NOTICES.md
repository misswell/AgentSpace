# Third-party notices

## offstage

<https://github.com/viraatdas/offstage>

```
MIT License

Copyright (c) 2026 Viraat Das

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### What AgentSpace took from it

The plan (§42) says to reuse or reference Offstage's *verified* logic and to
reimplement the product around it, rather than forking and renaming. That is what
was done.

**No source file was copied verbatim.** `native/sessiond/*.swift` was read for its
measured findings and its structure, and every file in this repository was written
fresh against AgentSpace's own protocol, error vocabulary, model types and
requirements. The notice above is reproduced anyway, because the debt is real and
because the honest thing to do with a real debt is to acknowledge it rather than
to argue about whether it clears a threshold.

Ideas and measurements taken from Offstage:

| | |
|---|---|
| The three `CGEvent` posting paths and their measured behaviour | `.cghidEventTap` routes to the console session; `postToPid` delivers nothing; `.cgSessionEventTap` is the only correct one from a background session. Reproduced and relied upon. |
| Always assigning `event.flags`, including the empty set | A fresh `CGEvent` inherits ambient modifier state, so a plain keystroke can arrive as a shortcut. |
| One event per grapheme cluster when typing | Packing several characters into one event is silently truncated by apps that read only the first. |
| `CGDisplayPixelsWide()` returns points on a scaled Retina display | Independently re-measured here on macOS 27.0; see `docs/validation.md` §2. |
| Reading the frontmost pid from the window list rather than `NSWorkspace` | The `NSWorkspace` cache goes stale in a process with no run loop. |
| The shape of a background Aqua session, its LaunchAgent, and the first-login setup flow | The architecture the plan describes. |
| `posix_spawn` details | `POSIX_SPAWN_SETSID` for process-group control, and setting an explicit signal mask and default dispositions because libdispatch worker threads block signals and that survives `exec`. |
| The observation that a socket directory's ownership must be checked before binding in it | Adopted as the `sun_path` length check rather than an ownership check, since AgentSpace creates the directory itself. |

Where AgentSpace deliberately diverges — the session-availability signal, the
error-code vocabulary, input validation messages, the session token, the
confinement model, the `exec` result shape — the differences are tabulated with
reasons in `docs/validation.md` §8.

### One correction worth recording

Offstage reads `kCGSSessionManagerNameKey` from
`CGSessionCopyCurrentDictionary()` and falls back to `"Aqua"`. On macOS 27.0 that
key **is not present in the dictionary at all**, so the fallback always fires and
the check is inert: it answers `"Aqua"` in every session, including ones with no
GUI. AgentSpace therefore uses `SessionGetInfo`'s `sessionHasGraphicAccess` bit
instead, which is a real answer from a supported API. The measurement is in
`docs/validation.md` §1.

## Apple

No Apple source code is included. The keycode table in
`shared/Core/Sources/AgentSpaceCore/InputActions.swift` and the modifier tables are
US-layout virtual keycodes, which are facts about the platform published in
`<HIToolbox/Events.h>`; any implementation of keyboard injection on macOS contains
the same list.

AgentSpace links only Apple system frameworks:

| Framework | Used for |
|---|---|
| Foundation, Darwin | Everything |
| CoreGraphics | `CGEvent`, display geometry, window list, TCC preflight |
| ApplicationServices | Accessibility (`AXUIElement`) |
| AppKit | `NSWorkspace`, `NSRunningApplication` |
| Security | `SecRandomCopyBytes`, `SessionGetInfo`, `timingsafe_bcmp` |
| ServiceManagement | `SMAppService` (phase 3) |
| os | `OSLog` |
| ImageIO | PNG header inspection |

## No other dependencies

The Swift package has no third-party dependencies at all — deliberately, because
the worker must start in milliseconds and must not need a package graph resolved
inside the agent user's account. The MCP server
(`packages/agentspace-mcp`) depends on `@modelcontextprotocol/sdk` and `zod`,
whose notices appear with their packages.
