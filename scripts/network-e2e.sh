#!/usr/bin/env bash
#
# Prove the virtual network end to end, without root and without a utun:
#
#   hub (real control plane)  →  fixed addresses handed out
#   product Core              →  WireGuard UAPI configuration
#   real wireguard-go         →  handshake + a packet in both directions
#
# The kernel interface is the only fake part. The WireGuard implementation, its
# crypto, its UDP transport, the hub's HTTP control plane and the Swift code that
# builds the configuration are the shipping ones.
#
# Why this exists: a WireGuard configuration that is *nearly* right produces a
# tunnel that never handshakes with no error to explain it. §398 records this
# script catching exactly that — the UAPI protocol wants hex keys, not base64.
#
# Requirements: Go 1.22+ (the hub uses method patterns) and network access for
# the wireguard-go module. Skipped with exit 3 when Go is absent, like the other
# instruments here: exit 3 means "nothing was verified", never "passed".
set -euo pipefail
cd "$(dirname "$0")/.."

GO="${GO:-$(command -v go || true)}"
if [[ -z "$GO" && -x /tmp/goroot/go/bin/go ]]; then GO=/tmp/goroot/go/bin/go; fi
if [[ -z "$GO" ]]; then
  echo "network-e2e: no Go toolchain, so nothing was verified" >&2
  exit 3
fi
echo "== go =="
"$GO" version

WORK="$(mktemp -d /tmp/agentspace-net-e2e.XXXXXX)"
HUB_PID=""
cleanup() {
  [[ -n "$HUB_PID" ]] && kill "$HUB_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo
echo "== 1. build the hub and run its tests =="
( cd network/hub && "$GO" test ./... 2>&1 | sed 's/^/   /' )
( cd network/hub && "$GO" build -o "$WORK/agentspace-hub" . )
echo "   ok  hub built"

echo
echo "== 2. start a hub and allocate fixed addresses =="
"$WORK/agentspace-hub" init --state "$WORK/hub.json" --pool 100.64.9.0/24 > "$WORK/init.log"
# A fixed port made this script talk to a hub somebody else had left running —
# measured: the run enrolled into a stale state file and the tokens were
# refused. An ephemeral port plus an identity check is the difference between
# "the network works" and "some network worked".
PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
BASE="http://127.0.0.1:$PORT"
NETWORK_ID="$(sed -n 's/^network \(.*\)$/\1/p' "$WORK/init.log")"
"$WORK/agentspace-hub" serve --state "$WORK/hub.json" --listen "127.0.0.1:$PORT" > "$WORK/serve.log" 2>&1 &
HUB_PID=$!
HEALTH=""
for _ in $(seq 1 100); do
  HEALTH="$(curl -fsS "$BASE/healthz" 2>/dev/null || true)"
  [[ -n "$HEALTH" ]] && break
  sleep 0.1
done
[[ -n "$HEALTH" ]] || { echo "the hub did not answer on $BASE" >&2; cat "$WORK/serve.log" >&2; exit 1; }
case "$HEALTH" in
  *"$NETWORK_ID"*) : ;;
  *) echo "the hub on $BASE is not the one just started (want network $NETWORK_ID): $HEALTH" >&2; exit 1 ;;
esac
echo "   $HEALTH"
echo

TOKEN_A="$("$WORK/agentspace-hub" enroll-token --state "$WORK/hub.json" --label node-a --role agentspace | sed -n 's/.*token: //p')"
TOKEN_B="$("$WORK/agentspace-hub" enroll-token --state "$WORK/hub.json" --label node-b --role controller | sed -n 's/.*token: //p')"
[[ -n "$TOKEN_A" && -n "$TOKEN_B" ]] || { echo "no enrollment tokens" >&2; exit 1; }

echo "== 3. build both UAPI configurations from AgentSpaceCore =="
PKG="$WORK/pkg"
mkdir -p "$PKG/Sources/netconfig"
cat > "$PKG/Package.swift" <<SWIFT
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "netconfig",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "$PWD")],
    targets: [.executableTarget(name: "netconfig", dependencies: [
        .product(name: "AgentSpaceCore", package: "AgentSpace"),
    ])]
)
SWIFT
cat > "$PKG/Sources/netconfig/main.swift" <<'SWIFT'
import Foundation
import AgentSpaceCore

struct HubNode: Decodable {
    let id: String; let name: String; let address: String
    let publicKey: String; let endpoint: String?; let allowedIPs: [String]
}
struct Network: Decodable {
    let pool: String; let hubAddress: String; let listenPort: Int; let nodes: [HubNode]
}
struct Envelope: Decodable {
    struct Node: Decodable { let id: String; let address: String }
    let node: Node; let network: Network
}
struct NetworkEnvelope: Decodable { let network: Network }

let args = CommandLine.arguments
let tokenA = args[1], tokenB = args[2], outDir = args[3]

let base = ProcessInfo.processInfo.environment["HUB_BASE"] ?? "http://127.0.0.1:18788"

func request(_ method: String, _ path: String, _ body: [String: String]? = nil) -> Data {
    var req = URLRequest(url: URL(string: base + path)!)
    req.httpMethod = method
    if let body {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try! JSONSerialization.data(withJSONObject: body)
    }
    let sem = DispatchSemaphore(value: 0)
    var out = Data()
    URLSession.shared.dataTask(with: req) { data, _, _ in out = data ?? Data(); sem.signal() }.resume()
    sem.wait()
    return out
}

let a = VirtualNodeIdentity.generate(nodeID: "node-a")!
let b = VirtualNodeIdentity.generate(nodeID: "node-b")!
let firstResponse = request("POST", "/v1/enroll", ["token": tokenA, "name": "node-a",
    "publicKey": a.publicKeyBase64, "endpoint": "127.0.0.1:51820"])
guard let first = try? JSONDecoder().decode(Envelope.self, from: firstResponse) else {
    // Printing the hub's own answer is what turns a decode failure into a
    // diagnosis instead of a crash.
    FileHandle.standardError.write(Data("enroll node-a failed: \(String(data: firstResponse, encoding: .utf8) ?? "<no body>")\n".utf8))
    exit(1)
}
let secondResponse = request("POST", "/v1/enroll", ["token": tokenB, "name": "node-b",
    "publicKey": b.publicKeyBase64, "endpoint": "127.0.0.1:51821"])
guard let enrolled = try? JSONDecoder().decode(Envelope.self, from: secondResponse) else {
    FileHandle.standardError.write(Data("enroll node-b failed: \(String(data: secondResponse, encoding: .utf8) ?? "<no body>")\n".utf8))
    exit(1)
}
_ = first
let network = enrolled.network

func config(_ identity: VirtualNodeIdentity, own: String, listen: Int, otherPort: Int) -> WireGuardTunnelConfiguration {
    let peers: [WireGuardPeer] = network.nodes.compactMap { node in
        guard node.address != own, let key = WireGuardPublicKey(base64: node.publicKey) else { return nil }
        let endpoint = node.name == "node-a" ? "127.0.0.1:51820"
            : node.name == "node-b" ? "127.0.0.1:51821" : "127.0.0.1:\(otherPort)"
        return WireGuardPeer(publicKey: key, endpoint: endpoint,
            allowedIPs: node.allowedIPs.compactMap { IPv4Network($0) }, persistentKeepalive: 0)
    }
    return WireGuardTunnelConfiguration(privateKey: identity.privateKey!,
        localAddresses: [IPv4Address(own)!], listenPort: listen, peers: peers)
}

let ownA = network.nodes.first { $0.publicKey == a.publicKeyBase64 }!
let ownB = network.nodes.first { $0.publicKey == b.publicKeyBase64 }!
let cfgA = config(a, own: ownA.address, listen: 51820, otherPort: 51821)
let cfgB = config(b, own: ownB.address, listen: 51821, otherPort: 51820)
precondition(cfgA.problems().isEmpty, "A: \(cfgA.problems())")
precondition(cfgB.problems().isEmpty, "B: \(cfgB.problems())")
try! cfgA.uapiConfiguration(replacePeers: true).write(toFile: outDir + "/a.uapi", atomically: true, encoding: .utf8)
try! cfgB.uapiConfiguration(replacePeers: true).write(toFile: outDir + "/b.uapi", atomically: true, encoding: .utf8)
print("   ok  pool \(network.pool), hub \(network.hubAddress)")
print("   ok  node-a \(ownA.address), node-b \(ownB.address)")
SWIFT
swift build --package-path "$PKG" -q 2>&1 | sed 's/^/   /'
HUB_BASE="$BASE" "$PKG/.build/debug/netconfig" "$TOKEN_A" "$TOKEN_B" "$WORK" | sed 's/^/   /'

echo
echo "== 4. real wireguard-go handshake and a packet in both directions =="
# The harness lives in the repository, not in a scratch path: a verification
# script that depends on something outside the tree verifies nothing on another
# machine.
( cd network/e2e && GOFLAGS=-mod=mod "$GO" mod tidy > /dev/null 2>&1 && "$GO" build -o "$WORK/harness" . )
"$WORK/harness" "$WORK/a.uapi" "$WORK/b.uapi"

echo
echo "network-e2e: PASS — fixed addresses from the hub reach a real tunnel in both directions"
