import Foundation
import AgentSpaceCore

/// `agentspace api …` and `agentspace api-token …`.
///
/// The API's listener belongs to the app: it needs the virtual address, the
/// token store and the same registry the GUI reads. The CLI therefore manages the
/// configuration and the credentials and reports state, and it says plainly when
/// an action has to happen in the app rather than pretending a flag started a
/// service.
enum APICommand {

    // MARK: - api

    static func run(
        action: String,
        args: [String],
        parsed: ParsedArgs,
        root: String?,
        emitter: Emitter
    ) -> Never {
        let paths = VirtualNetworkPaths(root: root)
        let network = VirtualNetworkStore(paths: paths).load()

        switch action {
        case "status", "":
            let config = APIConfiguration.load(paths: paths)
            guard let network else {
                emitter.success(.obj([
                    "ok": .bool(true),
                    "enabled": .bool(false),
                    "note": .string("no virtual-network configuration; the API cannot bind to a virtual address"),
                ]), human: "API: not configured (no virtual network)")
            }
            let tokens = APITokenStore.load(paths: paths)
            let active = tokens.tokens.filter(\.isActive)
            let policy = config.flatMap { $0.policy(network: network) }
            let host = policy?.host ?? "—"
            let port = policy?.port ?? network.apiPort
            let onLink = LocalNetworkProbe.snapshot().addresses.contains(network.local)
            let extensionState = SystemExtensionProbe.installedState()

            emitter.success(.obj([
                "ok": .bool(true),
                "enabled": .bool(config?.enabled == true),
                "bindMode": config.map { .string($0.bindMode) } ?? .string("virtualNetwork"),
                "host": .string(host),
                "port": .int(port),
                "baseURL": .string("http://\(host):\(port)"),
                "virtualAddressPresent": .bool(onLink),
                "extension": .string(extensionState.detail),
                "activeTokens": .int(active.count),
                "note": config == nil
                    ? .string("no API configuration yet; `agentspace api enable` writes one")
                    : .null,
            ]), human: """
            API: \(config?.enabled == true ? "enabled" : "disabled")
              listen:   \(host):\(port) (\(config?.bindMode ?? "virtualNetwork"))
              address:  \(onLink ? "\(network.local) is present" : "\(network.local) is not assigned yet — the tunnel is down")
              tokens:   \(active.count) active
              extension: \(extensionState.detail)
            """)

        case "enable":
            guard let network else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "enable the virtual network first: the API binds to its address, never to all interfaces."))
            }
            var port = network.apiPort
            if let portText = parsed.flag("port"), let parsedPort = Int(portText) {
                port = parsedPort
            }
            guard VirtualNetworkValidator.allowedPortRange.contains(port) else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "port \(port) is outside \(VirtualNetworkValidator.allowedPortRange.lowerBound)–\(VirtualNetworkValidator.allowedPortRange.upperBound)"))
            }
            // Loopback is the default: it is the only address that exists with
            // no network at all, and it never exposes the API on a physical
            // interface. A virtual address is opt-in through `--virtual`.
            var bindMode = "loopback"
            if parsed.bool("virtual") { bindMode = "virtualNetwork" }
            let config = APIConfiguration(enabled: true, bindMode: bindMode, port: port)
            do {
                try config.save(paths: paths)
            } catch {
                emitter.failure(AgentSpaceError(
                    code: .internalError, message: "could not write the API configuration: \(error)"))
            }
            let host = config.policy(network: network)?.host ?? network.local.description
            emitter.success(.obj([
                "ok": .bool(true),
                "enabled": .bool(true),
                "host": .string(host),
                "port": .int(port),
                "baseURL": .string("http://\(host):\(port)"),
                "note": .string("The app starts the listener and reports its real state in Settings → Virtual Network."),
            ]), human: "API enabled: http://\(host):\(port)\n  The app starts the listener; `agentspace api status` reports the configuration.")

        case "disable":
            var config = APIConfiguration.load(paths: paths)
                ?? APIConfiguration(enabled: false, port: network?.apiPort ?? VirtualNetworkValidator.defaultPort)
            let was = config.enabled
            config.enabled = false
            config.updatedAt = Date()
            do {
                try config.save(paths: paths)
            } catch {
                emitter.failure(AgentSpaceError(
                    code: .internalError, message: "could not write the API configuration: \(error)"))
            }
            emitter.success(.obj([
                "ok": .bool(true), "changed": .bool(was),
            ]), human: was ? "API disabled" : "API was already disabled")

        case "restart":
            guard APIConfiguration.load(paths: paths)?.enabled == true else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest, message: "the API is disabled; enable it first"))
            }
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "restarting the listener is the app's job — it owns the port and the extension. Use Settings → Virtual Network → Restart API, which reports whether the new listener actually bound."))

        default:
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "unknown api command '\(action)'. Try: status, enable, disable, restart."))
        }
    }

    // MARK: - api-token

    static func runToken(
        action: String,
        args: [String],
        parsed: ParsedArgs,
        root: String?,
        emitter: Emitter
    ) -> Never {
        let paths = VirtualNetworkPaths(root: root)

        switch action {
        case "list", "":
            let list = APITokenStore.load(paths: paths)
            let rows = list.tokens.map { token -> JSONValue in
                .obj([
                    "id": .string(token.id),
                    "name": .string(token.name),
                    "scopes": .array(token.scopes.map { .string($0.rawValue) }),
                    "createdAt": .string(ISO8601DateFormatter().string(from: token.createdAt)),
                    "lastUsedAt": token.lastUsedAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
                    "revoked": .bool(!token.isActive),
                ])
            }
            let human = list.tokens.isEmpty
                ? "no API tokens. `agentspace api-token create --name NAME --scope read`"
                : list.tokens.map { token in
                    let state = token.isActive ? "active" : "revoked"
                    return "  \(token.id)  \(token.name)  [\(token.scopes.map(\.displayName).joined(separator: ","))]  \(state)"
                }.joined(separator: "\n")
            emitter.success(.obj(["ok": .bool(true), "tokens": .array(rows)]), human: human)

        case "create":
            guard let name = parsed.flag("name"), !name.isEmpty else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "usage: agentspace api-token create --name NAME [--scope read|observe|control|exec]..."))
            }
            var scopes: Set<APIScope> = []
            for raw in parsed.list("scope") {
                guard let scope = APIScope(rawValue: raw) else {
                    emitter.failure(AgentSpaceError(
                        code: .badRequest,
                        message: "unknown scope '\(raw)'. Scopes: read, observe, control, exec."))
                }
                scopes.insert(scope)
            }
            if scopes.isEmpty {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "a token needs at least one --scope. read, observe, control, exec."))
            }
            do {
                let (record, secret) = try APITokenStore.create(name: name, scopes: scopes, paths: paths)
                // The secret is printed once and never stored; say so, because a
                // person who scrolls past it cannot get it back.
                emitter.success(.obj([
                    "ok": .bool(true),
                    "id": .string(record.id),
                    "name": .string(record.name),
                    "scopes": .array(record.scopes.map { .string($0.rawValue) }),
                    "token": .string(secret),
                    "note": .string("This is the only time the token is shown. Only its SHA-256 digest is stored."),
                ]), human: """
                created token \(record.id) "\(record.name)" [\(record.scopes.map(\.displayName).joined(separator: ","))]
                  token: \(secret)
                  This is the only time it is shown; only its digest is stored.
                """)
            } catch let error as AgentSpaceError {
                emitter.failure(error)
            } catch {
                emitter.failure(AgentSpaceError(code: .internalError, message: "\(error)"))
            }

        case "revoke":
            guard let id = args.first ?? parsed.flag("id"), !id.isEmpty else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest, message: "usage: agentspace api-token revoke <token-id>"))
            }
            do {
                guard let record = try APITokenStore.revoke(id: id, paths: paths) else {
                    emitter.failure(AgentSpaceError(
                        code: .badRequest, message: "no token with id '\(id)'"))
                }
                emitter.success(.obj([
                    "ok": .bool(true), "id": .string(record.id), "revoked": .bool(true),
                ]), human: "revoked token \(record.id) \"\(record.name)\"")
            } catch {
                emitter.failure(AgentSpaceError(code: .internalError, message: "\(error)"))
            }

        case "rotate":
            guard let id = args.first ?? parsed.flag("id"), !id.isEmpty else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest, message: "usage: agentspace api-token rotate <token-id>"))
            }
            do {
                guard let rotated = try APITokenStore.rotate(id: id, paths: paths) else {
                    emitter.failure(AgentSpaceError(
                        code: .badRequest,
                        message: "no active token with id '\(id)'"))
                }
                emitter.success(.obj([
                    "ok": .bool(true),
                    "id": .string(rotated.record.id),
                    "revoked": .string(id),
                    "token": .string(rotated.secret),
                    "note": .string("The old token stops working immediately. This is the only time the new one is shown."),
                ]), human: """
                rotated \(id) → \(rotated.record.id)
                  token: \(rotated.secret)
                  The old token no longer works. This is the only time the new one is shown.
                """)
            } catch let error as AgentSpaceError {
                emitter.failure(error)
            } catch {
                emitter.failure(AgentSpaceError(code: .internalError, message: "\(error)"))
            }

        default:
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "unknown api-token command '\(action)'. Try: list, create, revoke, rotate."))
        }
    }
}
