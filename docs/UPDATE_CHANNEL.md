# The update channel

How an installed AgentSpace replaces itself, and what that path refuses to do.
The code is `native/AgentSpaceUpdaterSupport` (the decisions, testable),
`native/AgentSpaceUpdater` (the swap), and
`apps/AgentSpace/Services/SoftwareUpdate.swift` (the chain that runs before
either). The UI is the last tab of Settings.

## What is published

`scripts/release.sh` produces `dist/AgentSpace-<VERSION>.dmg` from the
notarized, stapled `dist/AgentSpace.app`; `scripts/notarize.sh` staples both.
A release is then pushed as tag `v<VERSION>` with that DMG as the asset named
`AgentSpace-<VERSION>.dmg`. Nothing else is a valid update source: the app is
not on the App Store, and there is no self-hosted manifest.

Two facts about a GitHub release are trusted:

* the asset list, including `assets[].digest` — GitHub's own `sha256:<64 hex>`
  of the uploaded bytes, which is what the download is compared against;
* the release `tag_name`, which must parse as the version and must equal the
  version the unpacked bundle declares.

Everything else about the bytes is verified locally, below.

## What is checked before anything is replaced

In order, and the update is refused if any step fails:

1. the asset URL is `https` and belongs to this repository's release downloads;
2. the downloaded file's SHA-256 equals GitHub's stored digest;
3. `hdiutil attach -readonly -nobrowse` mounts the DMG and it contains
   `AgentSpace.app`;
4. that bundle's `CFBundleIdentifier` is `com.agentspace.AgentSpace`, its
   `CFBundleExecutable` is `AgentSpace`, and its
   `CFBundleShortVersionString` equals the release's version — a bundle that
   merely *looks* like a new release is not one;
5. every nested piece of executable code the release is supposed to carry is
   present (`AgentSpaceIdentity.nestedCodePaths`: the worker, the CLI, the
   updater, the helper);
6. `codesign --verify --deep --strict` passes;
7. the team identifier is `U8U443D7ZL`;
8. the candidate's **designated requirement** is semantically the running
   app's. This is the step that decides whether macOS treats the updated copy as
   the same entity, so a rewritten requirement silently costs the user their
   Accessibility, Screen Recording and Full Disk Access grants;
9. `spctl --assess --type execute` accepts it — notarization and stapling,
   not just a signature.

Only then does the app quit and hand off to
`Contents/Helpers/agentspace-updater`, which is copied out of the bundle first
because the bundle is the thing being replaced.

## What the updater does, and refuses to do

`UpdaterLaunchPlan` is the whole contract between the two processes: parent pid,
verified source bundle, destination bundle, staging directory, the updater's own
copy, log path. Seven argv values or the updater exits 2 without touching
anything (`scripts/updater-e2e.sh` proves all three outcomes offline).

It waits for the old process to be gone, copies the verified bundle beside the
destination as `.AgentSpace-update-<token>.app`, swaps it in with
`replaceItemAt` keeping `.AgentSpace-backup-<token>.app`, re-checks that what
now sits at the app's path is AgentSpace, and relaunches
`Contents/MacOS/AgentSpace` **directly** — not through `open`, whose record for
a path that was just replaced is stale and which would hand the new process this
process's environment (§300). On any failure after the swap, the backup goes
back and the old copy is relaunched. A refusal never leaves a stranger at the
app's path. Scratch directories are removed on both paths; the log is
`~/Library/Logs/AgentSpace/update.log`.

Location is gated: only `/Applications/AgentSpace.app` (including its
`/System/Volumes/Data` spelling) may self-replace. A copy running from `dist/`,
Downloads, or a translocation path says so in the UI and offers the release
page instead — `dist/AgentSpace.app` is a notarized artifact, and a silently
"successful" update there would overwrite it with GitHub's bytes.

## What an app update does *not* change

The privileged helper (`/Library/PrivilegedHelperTools`) and the installed
worker (`/Library/Application Support/AgentSpace/Worker/active/agentspace-worker`)
live outside the bundle. An in-app update cannot and does not touch them; they
change when the user presses 「重新安装助手…」, which is the only path with a
password prompt. Workers already running are unaffected either way, because
they run from the installed copy, not from the bundle.

So after an update the *助手版本过旧* card can still be correct, and it is: the
bundle moved, the root components did not.

## Download sources

Release metadata always comes from GitHub directly; a mirror can never change
which version or which digest is expected. The DMG itself is fetched from, in
order:

1. Xget — `https://xget.xi-xu.me/gh/misswell/AgentSpace/releases/download/...`
2. GHFast — `https://ghfast.top/https://github.com/...`
3. GH-Proxy — `https://gh-proxy.org/https://github.com/...`
4. GitHub's own asset URL, always last as the fallback.

The host that last served a download that passed its digest check is remembered
(`updateDownloadMirrorHost`) and tried first next time, with the rest keeping
default order; a run that only succeeded directly resets to default order. Only
these builtin hosts are ever preferred, and only this repository's
release-download paths are ever rewritten — an arbitrary address is never
accepted as a mirror. Per source: 15 s without network response, a failed
request, a non-200 status, or a digest mismatch moves to the next source. A
steady transfer is not cut off by the idle window, and a user cancellation stops
the rotation instead of falling through to the next host. Every source's failure
reason is written to the update log.

## Publishing is not finished until `latest` answers

The channel is one derived GitHub endpoint, `GET
/repos/misswell/AgentSpace/releases/latest` — `SoftwareUpdater.latestReleaseURL`
— so a release can be live, correct, and still invisible. Measured on 0.1.27:
flipping a draft with `draft: false` left that endpoint answering the *previous*
tag for six minutes (nine samples, cache-busting query strings included) while
`releases/tags/v0.1.27` already reported the new release and its digest; a write
to the release itself (`make_latest=true`) moved it within five seconds (§318 row
820). Treat the assertion as part of releasing: publish, then require `latest` to
name the new tag *and* carry the digest of the file `scripts/check-all.sh`
approved, and pull the asset back once to prove the bytes that leave this machine
are the bytes that come back.

## Who builds the release

The release is cut by `.github/workflows/release.yml`, on a `macos-15` runner,
triggered by a `v*` tag push (or `workflow_dispatch`, which takes a `dry_run`
input that builds and signs without publishing). It calls this repository's own
`scripts/release.sh` and `scripts/notarize.sh` rather than reimplementing them: a
CI path that forked the release logic would be testing a different product than
the one users install.

Two jobs, in order:

1. **gate** — layers 1–3 of `scripts/check-all.sh`: `scripts/test.sh` (Swift
   unit + safety + integration), `scripts/updater-e2e.sh`, `scripts/mcp-smoke.sh`,
   plus the MCP package's own `npm test`.
2. **release** — imports the Developer ID certificate into a throwaway keychain,
   registers the notary credential, builds, signs, notarizes, staples, verifies
   what a user will actually get, publishes, and then asserts the update channel.

**Layer 4 does not run on the runner.** `scripts/gui-verify.sh` drives the
Accessibility tree of a console Aqua session, which needs a TCC grant that cannot
be given to a hosted runner non-interactively. The gate job measures that
prerequisite and says so in the run's job summary rather than failing thirteen
checks for a permission reason and calling it a broken build. A release whose
layer 4 matters must still be checked locally with `scripts/check-all.sh`, and
the workflow appends that sentence to the release notes.

### Required repository secrets

Set these under *Settings → Secrets and variables → Actions*. The workflow fails
with a named `::error::` for the first one that is missing, so a half-configured
repository cannot publish.

| Secret | What it is | Where it comes from |
|---|---|---|
| `APPLE_CERTIFICATE_P12` | The `Developer ID Application: Guofeng Liu (U8U443D7ZL)` certificate **and its private key**, as a `.p12`, base64-encoded | Keychain Access → export the identity, then `base64 -i DeveloperID.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | The password that `.p12` was exported with | chosen at export time |
| `APPLE_DEVELOPER_ID` | The full identity string `Developer ID Application: Guofeng Liu (U8U443D7ZL)` | exactly as `security find-identity -v -p codesigning` prints it |
| `APPLE_TEAM_ID` | `U8U443D7ZL` | the team the certificate belongs to |
| `ASC_KEY_ID` | App Store Connect API key id | `asc auth status`, or App Store Connect → Users and Access → Integrations |
| `ASC_ISSUER_ID` | The API key's issuer UUID | same |
| `ASC_PRIVATE_KEY` | The `.p8` file's **contents** (not a path) | downloaded once when the key was created; Apple does not offer it again |

Notarization uses the API key rather than an Apple ID and an app-specific
password, because `scripts/notarize.sh` builds its `notarytool` profile from it
and then verifies that profile with a live `notarytool history` call before
submitting anything — a profile *name* proves nothing.

### Release notes live in the tree

The workflow requires `docs/releases/<tag>.md` and fails without it. The first
line (a `# ` heading) becomes the release title and the rest becomes the body,
with the gated digest and size appended by the workflow.

This exists because this repository's release notes have a rule that
`--generate-notes` cannot satisfy: a note must say the thing a person has to do
and say it **first**. For the 0.1.38 cycle that is the two-press rule —
「检查更新」 then 「重新安装助手…」 — and a generated log of commits would have
buried it. Keeping the notes in the tree also means they are reviewed in the same
commit as the version bump.

## Automatic checks

Once per launch, after the window is up. A check that fails *automatically* is
not announced — no modal, no badge, nothing that interrupts; the pane just
records the state for when the user looks. The toggle is
`automaticallyChecksForUpdates`. An instance launched with `AGENTSPACE_ROOT`
set — which is what `scripts/gui-verify.sh` does — makes no outbound call at
all, so a verification run cannot be blamed for traffic it did not cause.
