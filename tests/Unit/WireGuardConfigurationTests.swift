import XCTest
@testable import AgentSpaceCore

/// WireGuard key material and the UAPI text a tunnel is configured with.
///
/// The format claims here are not inferred from documentation: §398 records a
/// real `wireguard-go` peer applying this exact output, handshaking, and passing
/// a packet in both directions. The one thing that measurement changed is
/// `testUAPIKeysAreHexBecauseWireGuardRejectsBase64` — a base64 version looked
/// entirely correct and was refused by the device with
/// `encoding/hex: invalid byte`.
final class WireGuardConfigurationTests: XCTestCase {

    func testGeneratedKeysAre32BytesAndClamped() throws {
        let key = try XCTUnwrap(WireGuardPrivateKey.generate())
        XCTAssertEqual(key.rawRepresentation.count, 32)
        let bytes = [UInt8](key.rawRepresentation)
        // Curve25519 clamping: low three bits clear, top bit clear, bit 254 set.
        XCTAssertEqual(bytes[0] & 0b111, 0)
        XCTAssertEqual(bytes[31] & 0b1000_0000, 0)
        XCTAssertEqual(bytes[31] & 0b0100_0000, 0b0100_0000)
    }

    func testPublicKeyIsDerivedAndStable() throws {
        let key = try XCTUnwrap(WireGuardPrivateKey.generate())
        let publicKey = try XCTUnwrap(key.publicKey)
        XCTAssertEqual(publicKey.rawRepresentation.count, 32)
        // The same private key always produces the same public key, which is what
        // makes a stored identity usable after a restart.
        XCTAssertEqual(key.publicKey, publicKey)
        XCTAssertNotEqual(publicKey.rawRepresentation, key.rawRepresentation)
    }

    func testBase64RoundTripKeepsTheKeyCanonical() throws {
        let key = try XCTUnwrap(WireGuardPrivateKey.generate())
        let restored = try XCTUnwrap(WireGuardPrivateKey(base64: key.base64))
        XCTAssertEqual(restored, key)
        XCTAssertEqual(restored.publicKey, key.publicKey)
        XCTAssertNil(WireGuardPrivateKey(base64: "not-a-key"))
        XCTAssertNil(WireGuardPrivateKey(base64: Data(repeating: 3, count: 31).base64EncodedString()))
    }

    func testUAPIKeysAreHexBecauseWireGuardRejectsBase64() throws {
        // Measured: a base64 key in `private_key=` makes a real wireguard-go
        // answer `IPC error -22: failed to set private_key: encoding/hex:
        // invalid byte: U+006D`. The format is hex, and this test is the guard
        // against "fixing" it back to base64 because base64 looks more familiar.
        let identity = try XCTUnwrap(VirtualNodeIdentity.generate())
        let privateKey = try XCTUnwrap(identity.privateKey)
        let peer = WireGuardPeer(
            publicKey: try XCTUnwrap(WireGuardPublicKey(base64: identity.publicKeyBase64)),
            endpoint: "127.0.0.1:51821",
            allowedIPs: [IPv4Network("100.64.0.11/32")!])

        let config = WireGuardTunnelConfiguration(
            privateKey: privateKey,
            localAddresses: [IPv4Address("100.64.0.10")!],
            listenPort: 51820,
            peers: [peer])
        let text = config.uapiConfiguration(replacePeers: true)

        XCTAssertTrue(text.contains("private_key=\(privateKey.hex)"))
        XCTAssertTrue(text.contains("public_key=\(peer.publicKey.hex)"))
        XCTAssertFalse(text.contains("private_key=\(privateKey.base64)"))
        for line in text.split(separator: "\n") where line.hasPrefix("private_key=")
            || line.hasPrefix("public_key=") {
            let value = line.split(separator: "=", maxSplits: 1)[1]
            XCTAssertEqual(value.count, 64, "\(line) is not a 32-byte hex key")
            XCTAssertTrue(value.allSatisfy(\.isHexDigit), "\(line) contains a non-hex character")
        }
    }

    func testUAPICarriesOnlyThePreciseAllowedIPs() throws {
        let identity = try XCTUnwrap(VirtualNodeIdentity.generate())
        let peer = WireGuardPeer(
            publicKey: try XCTUnwrap(WireGuardPublicKey(base64: identity.publicKeyBase64)),
            endpoint: "hub.example.com:51820",
            allowedIPs: [IPv4Network("100.64.0.11/32")!],
            persistentKeepalive: 25)
        let config = WireGuardTunnelConfiguration(
            privateKey: try XCTUnwrap(identity.privateKey),
            localAddresses: [IPv4Address("100.64.0.10")!],
            peers: [peer])
        let text = config.uapiConfiguration()
        XCTAssertTrue(text.contains("allowed_ip=100.64.0.11/32"))
        XCTAssertFalse(text.contains("allowed_ip=100.64.0.0/24"),
                       "routing the whole pool would capture a LAN that shares the range")
        XCTAssertTrue(text.contains("persistent_keepalive_interval=25"))
        XCTAssertFalse(text.contains("replace_peers=true"),
                       "a partial update must not silently replace every peer")
    }

    func testProblemsAreNamedBeforeTheTunnelStarts() throws {
        let key = try XCTUnwrap(WireGuardPrivateKey.generate())
        let empty = WireGuardTunnelConfiguration(privateKey: key, localAddresses: [], peers: [])
        XCTAssertTrue(empty.problems().contains { $0.contains("no local address") })
        XCTAssertTrue(empty.problems().contains { $0.contains("no peers") })

        let badEndpoint = WireGuardTunnelConfiguration(
            privateKey: key,
            localAddresses: [IPv4Address("100.64.0.10")!],
            mtu: 100,
            peers: [WireGuardPeer(
                publicKey: try XCTUnwrap(key.publicKey),
                endpoint: "no-port",
                allowedIPs: [])])
        let problems = badEndpoint.problems()
        XCTAssertTrue(problems.contains { $0.contains("MTU 100") })
        XCTAssertTrue(problems.contains { $0.contains("no allowed IPs") })
        XCTAssertTrue(problems.contains { $0.contains("not host:port") })
    }

    func testEndpointParsing() {
        XCTAssertEqual(WireGuardTunnelConfiguration.parseEndpoint("hub.example.com:51820")?.host,
                       "hub.example.com")
        XCTAssertEqual(WireGuardTunnelConfiguration.parseEndpoint("hub.example.com:51820")?.port, 51820)
        XCTAssertEqual(WireGuardTunnelConfiguration.parseEndpoint("1.2.3.4:1")?.port, 1)
        XCTAssertEqual(WireGuardTunnelConfiguration.parseEndpoint("[::1]:51820")?.host, "::1")
        XCTAssertNil(WireGuardTunnelConfiguration.parseEndpoint("host"))
        XCTAssertNil(WireGuardTunnelConfiguration.parseEndpoint("host:0"))
        XCTAssertNil(WireGuardTunnelConfiguration.parseEndpoint("host:70000"))
        XCTAssertNil(WireGuardTunnelConfiguration.parseEndpoint(":51820"))
    }

    // MARK: - Identity persistence

    func testIdentityIsGeneratedOnceAndReused() throws {
        let root = NSTemporaryDirectory() + "/agentspace-ident-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let paths = VirtualNetworkPaths(root: root)

        let first = try XCTUnwrap(VirtualNodeIdentity.loadOrGenerate(paths: paths))
        let second = try XCTUnwrap(VirtualNodeIdentity.loadOrGenerate(paths: paths))
        // Compared field by field rather than as a whole struct: the store uses
        // the registry's `.iso8601` date strategy, which drops sub-second
        // precision, so a stored `createdAt` necessarily differs in its
        // fractional part from the in-memory value that produced it.
        XCTAssertEqual(second.nodeID, first.nodeID)
        XCTAssertEqual(second.privateKeyBase64, first.privateKeyBase64)
        XCTAssertEqual(second.publicKeyBase64, first.publicKeyBase64)

        let attributes = try FileManager.default.attributesOfItem(atPath: paths.identityPath)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600,
                       "the private key must be readable only by its owner")

        XCTAssertEqual(first.privateKey?.publicKey?.base64, first.publicKeyBase64,
                       "the stored public key must match the stored private key")
    }

    func testTunnelConfigurationUsesThisMacsAddressAndExactPeerRoutes() throws {
        let root = NSTemporaryDirectory() + "/agentspace-tunnel-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        let identity = try XCTUnwrap(VirtualNodeIdentity.generate())
        try VirtualNodeIdentity.save(identity, paths: VirtualNetworkPaths(root: root))

        let peers = [
            VirtualNode(id: "hub", name: "Network hub", role: .hub,
                        address: IPv4Address("100.64.0.1")!,
                        publicKey: try XCTUnwrap(WireGuardPrivateKey.generate()?.publicKey?.base64)),
            VirtualNode(id: "laptop", name: "Laptop", role: .node,
                        address: IPv4Address("100.64.0.11")!,
                        publicKey: try XCTUnwrap(WireGuardPrivateKey.generate()?.publicKey?.base64)),
        ]
        let config = VirtualNetworkConfig(
            pool: IPv4Network("100.64.0.0/24")!,
            hub: IPv4Address("100.64.0.1")!,
            controller: IPv4Address("100.64.0.2")!,
            local: IPv4Address("100.64.0.10")!,
            nodes: peers)

        let tunnel = try XCTUnwrap(config.tunnelConfiguration(
            identity: identity, endpoints: ["hub": "hub.example.com:51820"]))
        XCTAssertEqual(tunnel.localAddresses.map(\.description), ["100.64.0.10"])
        XCTAssertEqual(tunnel.peers.count, 2, "this Mac is not its own peer")
        let hub = try XCTUnwrap(tunnel.peers.first { $0.endpoint != nil })
        XCTAssertEqual(hub.endpoint, "hub.example.com:51820")
        XCTAssertEqual(hub.allowedIPs.map(\.description), ["100.64.0.1/32"])
        XCTAssertTrue(tunnel.problems().isEmpty, "\(tunnel.problems())")
    }

    func testANodeWithoutAKeyIsSkippedRatherThanProducingAnInvalidPeer() throws {
        let identity = try XCTUnwrap(VirtualNodeIdentity.generate())
        let config = VirtualNetworkConfig(
            pool: IPv4Network("100.64.0.0/24")!,
            hub: IPv4Address("100.64.0.1")!,
            controller: IPv4Address("100.64.0.2")!,
            local: IPv4Address("100.64.0.10")!,
            nodes: [VirtualNode(id: "laptop", name: "Laptop", role: .node,
                                address: IPv4Address("100.64.0.11")!)])
        let tunnel = try XCTUnwrap(config.tunnelConfiguration(identity: identity))
        XCTAssertTrue(tunnel.peers.isEmpty,
                      "a node with no registered key cannot be a peer")
    }
}
