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
            let tokens = APITokenStore.load(paths: paths)
            let active = tokens.tokens.filter(\.isActive)
            let policy = config.flatMap { $0.policy(network: network) }
                ?? APIListenPolicy.loopback(port: network?.apiPort ?? VirtualNetworkValidator.defaultPort)
            let host = policy.host
            let port = policy.port
            // The CLI does not own the listener, so it does not guess: it
            // connects. An answered probe is the honest "running"; a refused
            // one is "not running right now", not an error.
            let answering = TCPProbe.answers(host: host, port: UInt16(clamping: port))
            let onLink = network.map { LocalNetworkProbe.snapshot().addresses.contains($0.local) } ?? false
            let virtualMissing = config?.bindMode == "virtualNetwork" && !onLink

            emitter.success(.obj([
                "ok": .bool(true),
                "enabled": .bool(config?.enabled == true),
                "bindMode": .string(config?.bindMode ?? "loopback"),
                "host": .string(host),
                "port": .int(port),
                "baseURL": .string("http://\(host):\(port)"),
                "listenerAnswering": .bool(answering),
                "activeTokens": .int(active.count),
                "note": config?.enabled != true
                    ? .string("the API is disabled in the configuration")
                    : answering
                        ? .string("the listener answered a TCP probe")
                        : .string("no listener answered; the app (not the CLI) runs the listener — is AgentSpace open?"),
            ]), human: """
            API: \(config?.enabled == true ? "enabled" : "disabled")
              listen:   \(host):\(port) (\(config?.bindMode ?? "loopback"))\(answering ? " — answering" : " — no listener (open the app to serve)")
              tokens:   \(active.count) active\(virtualMissing ? "\n  \(network!.local) is not on an interface, so a virtual-address bind would refuse" : "")
            """)

        case "enable":
            var port = network?.apiPort ?? VirtualNetworkValidator.defaultPort
            if let portText = parsed.flag("port"), let parsedPort = Int(portText) {
                port = parsedPort
            }
            guard VirtualNetworkValidator.allowedPortRange.contains(port) else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "port \(port) is outside \(VirtualNetworkValidator.allowedPortRange.lowerBound)–\(VirtualNetworkValidator.allowedPortRange.upperBound)"))
            }
            // Loopback is the default: it is the one address that exists with
            // no network at all, and it never exposes the API on a physical
            // interface — which is also why it needs no virtual-network
            // configuration. A virtual address is opt-in through `--virtual`
            // and does need one.
            var bindMode = "loopback"
            if parsed.bool("virtual") {
                bindMode = "virtualNetwork"
                guard let network else {
                    emitter.failure(AgentSpaceError(
                        code: .badRequest,
                        message: "a virtual-address API needs a virtual-network configuration; run `agentspace network enable` first, or drop --virtual to listen on 127.0.0.1."))
                }
            }
            let config = APIConfiguration(enabled: true, bindMode: bindMode, port: port)
            do {
                try config.save(paths: paths)
            } catch {
                emitter.failure(AgentSpaceError(
                    code: .internalError, message: "could not write the API configuration: \(error)"))
            }
            let host = config.policy(network: network)?.host ?? "127.0.0.1"
            emitter.success(.obj([
                "ok": .bool(true),
                "enabled": .bool(true),
                "host": .string(host),
                "port": .int(port),
                "baseURL": .string("http://\(host):\(port)"),
                "note": .string("The app serves this listener while it is open, and picks this configuration up within a few seconds; `agentspace api status` probes whether it is answering."),
            ]), human: "API enabled: http://\(host):\(port)\n  The app serves it while open — `agentspace api status` says whether it is answering.")

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
                message: "the listener runs inside the AgentSpace app, which re-reads the configuration every few seconds — turn the API off and on in Settings → Virtual Network (or relaunch the app) and the new bind takes effect immediately there."))

        default:
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "unknown api command '\(action)'. Try: status, enable, disable."))
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
