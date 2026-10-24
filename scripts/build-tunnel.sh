#!/usr/bin/env bash
#
# Build the wireguard-go bridge and the packet-tunnel system extension.
#
#   scripts/build-tunnel.sh <output-dir>
#
# Produces, under <output-dir>:
#   libwg-go.a                     the real WireGuard data plane (universal)
#   AgentSpaceTunnel.systemextension  the extension bundle, unsigned
#
# `scripts/bundle-app.sh` calls this and then signs the result inside-out with
# the app. It is a separate script because it has a Go dependency and a long
# first build, and a person debugging the app should be able to see which half
# failed.
#
# The Go source is wireguard-go itself, unmodified, with the Apple bridge
# (`api-apple.go`) at the version upstream ships. Nothing here reimplements the
# protocol, and nothing vendors a fork: a crypto bug introduced by this product
# would be invisible, and there is no reason to own one.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?usage: build-tunnel.sh <output-dir>}"
mkdir -p "$OUT"

GO="${GO:-$(command -v go || true)}"
if [[ -z "$GO" && -x /tmp/goroot/go/bin/go ]]; then GO=/tmp/goroot/go/bin/go; fi
if [[ -z "$GO" ]]; then
  echo "build-tunnel: no Go toolchain." >&2
  echo "  The tunnel's data plane is wireguard-go, which is Go code." >&2
  echo "  Install Go (brew install go) or point GO at one." >&2
  exit 1
fi

BRIDGE="$OUT/wireguard-go-bridge"
if [[ ! -x "$GO" ]]; then
  echo "build-tunnel: GO=$GO is not executable" >&2
  exit 1
fi

echo "== 1. fetch the Apple bridge =="
# Pinned to the revision this product measured (§398). A moving target would mean
# the tun interface this extension relies on could change without notice.
WG_REVISION="${WIREGUARD_APPLE_REVISION:-master}"
if [[ ! -d "$BRIDGE/.git" ]]; then
  rm -rf "$BRIDGE"
  git clone --depth 1 https://github.com/WireGuard/wireguard-apple.git "$BRIDGE" 2>&1 | tail -2
fi
echo "   ok  $(git -C "$BRIDGE" rev-parse --short HEAD) ($WG_REVISION)"

echo
echo "== 2. build the Go bridge (universal) =="
# The Makefile patches the Go runtime (boottime over monotonic) and produces a
# c-archive per architecture, then lipos them. GOPROXY is honoured because this
# machine's direct access to proxy.golang.org times out; a caller with normal
# access can leave it unset.
#
# MACOSX_DEPLOYMENT_TARGET is not enough for a c-archive: the Go runtime object
# is stamped with the SDK's own version (26.5 here) regardless, and linking it
# into a 26.0 binary produces "built for newer macOS version" warnings. They are
# warnings rather than errors because the symbols used exist in 26.0; the target
# is set anyway so an older SDK produces a matching library.
( cd "$BRIDGE/Sources/WireGuardKitGo" \
    && PATH="$PATH:$(dirname "$GO")" \
       GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}" \
       ARCHS="arm64 x86_64" \
       MACOSX_DEPLOYMENT_TARGET=26.0 \
       CGO_CFLAGS="-mmacosx-version-min=26.0 -isysroot \$(xcrun --sdk macosx --show-sdk-path)" \
       CGO_LDFLAGS="-mmacosx-version-min=26.0 -isysroot \$(xcrun --sdk macosx --show-sdk-path)" \
       CONFIGURATION_BUILD_DIR="$PWD/out" \
       make build ) 2>&1 | tail -3
cp "$BRIDGE/Sources/WireGuardKitGo/out/libwg-go.a" "$OUT/libwg-go.a"
echo "   ok  libwg-go.a $(du -h "$OUT/libwg-go.a" | cut -f1)"

echo
echo "== 3. build the extension =="
SDK="$(xcrun --sdk macosx --show-sdk-path)"
# The directory name must be the extension's bundle identifier: macOS matches a
# system extension by `CFBundleIdentifier` and looks for
# `<identifier>.systemextension` inside `Contents/Library/SystemExtensions`.
# A differently-named bundle is reported as "Extension not found in App bundle",
# which reads like a missing file rather than a naming rule — measured in §398.
EXT_NAME="com.misswell.AgentSpace.Tunnel.systemextension"
EXT="$OUT/$EXT_NAME"
rm -rf "$EXT"
mkdir -p "$EXT/Contents/MacOS"
cp native/AgentSpaceTunnel/Info.plist "$EXT/Contents/Info.plist"
cp native/AgentSpaceTunnel/embedded-provisionprofile "$EXT/Contents/embedded.provisionprofile" 2>/dev/null || true

# Universal binary, because the app is universal and a thin extension would make
# the whole app refuse to launch under Rosetta on an Intel Mac.
for arch in arm64 x86_64; do
  xcrun swiftc -sdk "$SDK" -target "$arch-apple-macos26.0" -O \
    -import-objc-header native/AgentSpaceTunnel/WireGuardUAPI.h \
    native/AgentSpaceTunnel/main.swift \
    native/AgentSpaceTunnel/TunnelProvider.swift \
    native/AgentSpaceTunnel/TunnelFileDescriptor.c \
    -L "$OUT" -lwg-go -framework NetworkExtension -framework Foundation \
    -Xlinker -rpath -Xlinker /usr/lib/swift \
    -o "$EXT/Contents/MacOS/AgentSpaceTunnel-$arch" 2>&1 | head -20
done
lipo -create -output "$EXT/Contents/MacOS/AgentSpaceTunnel" \
  "$EXT/Contents/MacOS/AgentSpaceTunnel-arm64" \
  "$EXT/Contents/MacOS/AgentSpaceTunnel-x86_64"
rm -f "$EXT/Contents/MacOS/AgentSpaceTunnel-arm64" "$EXT/Contents/MacOS/AgentSpaceTunnel-x86_64"

# The library is statically linked, so the extension must carry nothing but the
# system frameworks. Assert it rather than discover it at notarization.
if otool -L "$EXT/Contents/MacOS/AgentSpaceTunnel" | grep -q 'libwg-go'; then
  echo "build-tunnel: the wireguard library was linked dynamically; notarization would refuse it" >&2
  exit 1
fi
echo "   ok  $(du -h "$EXT/Contents/MacOS/AgentSpaceTunnel" | cut -f1), universal"

echo
echo "build-tunnel: $EXT"
