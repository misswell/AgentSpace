import Foundation
import CryptoKit

/// WireGuard key material and the UAPI configuration a tunnel needs.
///
/// The private key is generated here and never leaves the machine: the control
/// plane only ever receives the public half, which is the plan's rule and also
/// the only way a hub can be untrusted with anything.
///
/// The UAPI text format is `wireguard-go`'s, not this product's invention. It is
/// asserted against a real `wireguard-go` peer in validation §398 rather than
/// assumed from the format's description, because a config that is *nearly*
/// right produces a tunnel that never handshakes, with no error to explain it.
public struct WireGuardPrivateKey: Equatable, Sendable {
    /// 32 raw bytes, already clamped as WireGuard requires.
    public let rawRepresentation: Data

    public init(rawRepresentation: Data) {
        self.rawRepresentation = rawRepresentation
    }

    /// Generate from the system CSPRNG and clamp.
    public static func generate() -> WireGuardPrivateKey? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        return WireGuardPrivateKey(rawRepresentation: clamp(Data(bytes)))
    }

    /// Curve25519 clamping: clear the three low bits, clear the top bit, set the
    /// second-highest bit. `wireguard-go` clamps again on load, but a stored key
    /// that is already in canonical form means the key printed once and the key
    /// in use are the same value.
    public static func clamp(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        guard bytes.count == 32 else { return data }
        bytes[0] &= 248
        bytes[31] &= 127
        bytes[31] |= 64
        return Data(bytes)
    }

    public var base64: String { rawRepresentation.base64EncodedString() }
    /// WireGuard's own spelling, and the one the UAPI protocol requires.
    public var hex: String { rawRepresentation.hexString }

    public init?(base64: String) {
        guard let data = Data(base64Encoded: base64), data.count == 32 else { return nil }
        self.rawRepresentation = WireGuardPrivateKey.clamp(data)
    }

    /// The matching public key, from CryptoKit's X25519.
    public var publicKey: WireGuardPublicKey? {
        guard let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawRepresentation) else {
            return nil
        }
        return WireGuardPublicKey(rawRepresentation: key.publicKey.rawRepresentation)
    }
}

public struct WireGuardPublicKey: Equatable, Hashable, Sendable {
    public let rawRepresentation: Data

    public init(rawRepresentation: Data) {
        self.rawRepresentation = rawRepresentation
    }

    public init?(base64: String) {
        guard let data = Data(base64Encoded: base64), data.count == 32 else { return nil }
        self.rawRepresentation = data
    }

    public var base64: String { rawRepresentation.base64EncodedString() }
    public var hex: String { rawRepresentation.hexString }
}

/// One peer as the tunnel sees it.
public struct WireGuardPeer: Equatable, Sendable {
    public var publicKey: WireGuardPublicKey
    /// `host:port`. Optional: a peer that only accepts incoming connections has
    /// no endpoint of its own.
    public var endpoint: String?
    /// The precise addresses this peer owns. Never a whole pool.
    public var allowedIPs: [IPv4Network]
    public var persistentKeepalive: Int?
    public var presharedKey: Data?

    public init(
        publicKey: WireGuardPublicKey,
        endpoint: String? = nil,
        allowedIPs: [IPv4Network] = [],
        persistentKeepalive: Int? = 25,
        presharedKey: Data? = nil
    ) {
        self.publicKey = publicKey
        self.endpoint = endpoint
        self.allowedIPs = allowedIPs
        self.persistentKeepalive = persistentKeepalive
        self.presharedKey = presharedKey
    }
}

public struct WireGuardTunnelConfiguration: Equatable, Sendable {
    public var privateKey: WireGuardPrivateKey
    public var localAddresses: [IPv4Address]
    public var listenPort: Int?
    public var mtu: Int
    public var peers: [WireGuardPeer]

    public init(
        privateKey: WireGuardPrivateKey,
        localAddresses: [IPv4Address],
        listenPort: Int? = nil,
        mtu: Int = 1420,
        peers: [WireGuardPeer] = []
    ) {
        self.privateKey = privateKey
        self.localAddresses = localAddresses
        self.listenPort = listenPort
        self.mtu = mtu
        self.peers = peers
    }

    /// The UAPI config `wireguard-go` applies.
    ///
    /// Keys are **hex**, not base64. `wg-quick` files spell keys in base64 but
    /// the UAPI protocol that `IpcSet` consumes expects hex, and a base64 key
    /// there is rejected with `encoding/hex: invalid byte` — measured against a
    /// real `wireguard-go` in validation §398, after a base64 version of this
    /// function had already been written and looked entirely reasonable. Only a
    /// real device caught it.
    ///
    /// Deliberately no `replace_peers=true` on a full config: the caller that
    /// wants replacement asks for it. A partial update that accidentally
    /// replaced every peer would silently disconnect a network while reporting
    /// success.
    public func uapiConfiguration(replacePeers: Bool = false) -> String {
        var lines: [String] = []
        lines.append("private_key=\(privateKey.hex)")
        if let listenPort {
            lines.append("listen_port=\(listenPort)")
        }
        if !peers.isEmpty && replacePeers {
            lines.append("replace_peers=true")
        }
        for peer in peers {
            lines.append("public_key=\(peer.publicKey.hex)")
            if let presharedKey = peer.presharedKey {
                lines.append("preshared_key=\(presharedKey.hexString)")
            }
            if let endpoint = peer.endpoint {
                lines.append("endpoint=\(endpoint)")
            }
            if !peer.allowedIPs.isEmpty {
                lines.append("replace_allowed_ips=true")
                for network in peer.allowedIPs {
                    lines.append("allowed_ip=\(network.description)")
                }
            }
            if let keepalive = peer.persistentKeepalive, keepalive > 0 {
                lines.append("persistent_keepalive_interval=\(keepalive)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Problems that would make a tunnel fail to handshake, named before the
    /// tunnel starts rather than discovered as silence.
    public func problems() -> [String] {
        var problems: [String] = []
        if localAddresses.isEmpty {
            problems.append("the tunnel has no local address, so nothing can be routed into it")
        }
        if peers.isEmpty {
            problems.append("the tunnel has no peers, so it will never handshake")
        }
        if !(576...9000).contains(mtu) {
            problems.append("MTU \(mtu) is outside 576–9000")
        }
        for peer in peers {
            if peer.allowedIPs.isEmpty {
                problems.append("peer \(peer.publicKey.base64.prefix(8))… has no allowed IPs, so no traffic will be routed to it")
            }
            if let endpoint = peer.endpoint, Self.parseEndpoint(endpoint) == nil {
                problems.append("peer endpoint '\(endpoint)' is not host:port")
            }
            if let keepalive = peer.persistentKeepalive, !(0...65535).contains(keepalive) {
                problems.append("peer keepalive \(keepalive) is outside 0–65535")
            }
        }
        return problems
    }

    /// `host:port`, with an IPv6 host in brackets. Returns nil for anything else
    /// so a malformed endpoint is refused rather than handed to the tunnel.
    public static func parseEndpoint(_ text: String) -> (host: String, port: Int)? {
        let host: String
        let portText: String
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]"),
                  text.index(after: close) < text.endIndex,
                  text[text.index(after: close)] == ":" else { return nil }
            host = String(text[text.index(after: text.startIndex)..<close])
            portText = String(text[text.index(close, offsetBy: 2)...])
        } else {
            guard let colon = text.lastIndex(of: ":") else { return nil }
            host = String(text[..<colon])
            portText = String(text[text.index(after: colon)...])
        }
        guard !host.isEmpty, let port = Int(portText), (1...65535).contains(port) else { return nil }
        return (host, port)
    }
}

/// This node's identity inside the virtual network, persisted beside the
/// configuration.
///
/// The private key lives in this file at 0600 under the root-owned runtime
/// directory, which is the same protection the Worker's session token has. It is
/// never written to the registry, never logged, and never sent anywhere.
public struct VirtualNodeIdentity: Codable, Equatable, Sendable {
    public var nodeID: String
    public var privateKeyBase64: String
    public var publicKeyBase64: String
    public var createdAt: Date

    public init(nodeID: String, privateKeyBase64: String, publicKeyBase64: String, createdAt: Date = Date()) {
        self.nodeID = nodeID
        self.privateKeyBase64 = privateKeyBase64
        self.publicKeyBase64 = publicKeyBase64
        self.createdAt = createdAt
    }

    public static func generate(nodeID: String = UUID().uuidString.lowercased()) -> VirtualNodeIdentity? {
        guard let key = WireGuardPrivateKey.generate(), let publicKey = key.publicKey else { return nil }
        return VirtualNodeIdentity(
            nodeID: nodeID,
            privateKeyBase64: key.base64,
            publicKeyBase64: publicKey.base64)
    }

    public var privateKey: WireGuardPrivateKey? { WireGuardPrivateKey(base64: privateKeyBase64) }
    public var publicKey: WireGuardPublicKey? { WireGuardPublicKey(base64: publicKeyBase64) }

    public static func load(paths: VirtualNetworkPaths = VirtualNetworkPaths()) -> VirtualNodeIdentity? {
        guard let data = FileManager.default.contents(atPath: paths.identityPath) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VirtualNodeIdentity.self, from: data)
    }

    public static func loadOrGenerate(paths: VirtualNetworkPaths = VirtualNetworkPaths()) -> VirtualNodeIdentity? {
        if let existing = load(paths: paths) { return existing }
        guard let generated = generate() else { return nil }
        try? save(generated, paths: paths)
        return generated
    }

    public static func save(_ identity: VirtualNodeIdentity, paths: VirtualNetworkPaths = VirtualNetworkPaths()) throws {
        try FileManager.default.createDirectory(
            atPath: paths.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(identity)
        // 0600 from creation: the private key must never be briefly readable.
        guard FileManager.default.createFile(
            atPath: paths.identityPath, contents: data,
            attributes: [.posixPermissions: 0o600]) else {
            throw AgentSpaceError(
                code: .internalError,
                message: "could not write the node identity to \(paths.identityPath)")
        }
    }
}

// MARK: - Building a tunnel from the committed configuration

extension VirtualNetworkConfig {
    /// The tunnel this configuration describes for this Mac.
    ///
    /// Every peer gets a `/32` (or the exact prefix it was assigned), never the
    /// pool: routing the pool would capture traffic meant for a physical LAN
    /// that happens to share the range.
    public func tunnelConfiguration(
        identity: VirtualNodeIdentity,
        endpoints: [String: String] = [:],
        listenPort: Int? = nil
    ) -> WireGuardTunnelConfiguration? {
        guard let privateKey = identity.privateKey else { return nil }
        var peers: [WireGuardPeer] = []
        for node in allNodes where node.address != local {
            guard let keyText = node.publicKey,
                  let publicKey = WireGuardPublicKey(base64: keyText) else { continue }
            let endpoint = endpoints[node.id] ?? node.endpoint
            peers.append(WireGuardPeer(
                publicKey: publicKey,
                endpoint: endpoint,
                allowedIPs: [IPv4Network(address: node.address, prefixLength: 32)!],
                persistentKeepalive: node.persistentKeepalive))
        }
        return WireGuardTunnelConfiguration(
            privateKey: privateKey,
            localAddresses: [local],
            listenPort: listenPort,
            peers: peers)
    }
}


extension Data {
    /// Lowercase hex, the spelling WireGuard's UAPI and `wg` use for keys.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
