import Foundation
import AgentSpaceCore

/// `agentspace ports <account>` — the TCP ports this account's own processes
/// are listening on, from its own worker (`ports.list`, lsof as that uid).
///
/// This is the one piece of the port map that survived its removal (§406).
/// The mapping and the fixed per-account address are gone — measured straight
/// into the ground: every account on this Mac shares one kernel loopback and
/// one port table, so the main system already reaches each of these ports at
/// `127.0.0.1:<the same port number>` with no forwarding at all, and a second
/// account can never hold the same port that the first one holds. The list
/// stays because the question it answers is still real.
enum PortCommand {

    static func run(
        action: [String],
        parsed: ParsedArgs,
        root: String?,
        emitter: Emitter
    ) -> Never {
        let registry = SpaceRegistry.load(root: root)

        // No account named: one line per attached account.
        guard let reference = action.first else {
            let rows: [JSONValue] = registry.spaces.map { space in
                .obj([
                    "id": .string(space.id.uuidString),
                    "name": .string(space.name),
                ])
            }
            let human = registry.spaces.isEmpty
                ? "no agent accounts are attached"
                : registry.spaces
                    .map { "  \($0.name)" }
                    .joined(separator: "\n")
            emitter.success(.obj(["ok": .bool(true), "accounts": .array(rows)]), human: human)
        }

        // An account is named: resolve it like every other command does.
        let account: AgentAccount
        switch registry.resolve(reference) {
        case .success(let found): account = found
        case .failure(let error): emitter.failure(error)
        }
        let args = Array(action.dropFirst())
        let sub = args.first ?? "list"

        switch sub {
        case "list", "":
            return list(account: account, emitter: emitter)
        case "map", "unmap":
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "port mapping was removed in 0.1.105: every account shares one loopback, so the main system already reaches an account's port at 127.0.0.1 with the same port number — `agentspace ports \(account.name)` lists them"))
        case "address":
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "the fixed per-account address was removed in 0.1.105: a service bound to 127.0.0.1 never moves to it, and the app removes any alias it left on lo0 at launch"))
        default:
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "unknown ports command '\(sub)'. Try: `agentspace ports <account>`."))
        }
    }

    // MARK: list

    private static func list(account: AgentAccount, emitter: Emitter) -> Never {
        // The account's own worker is the only attribution there is: lsof as
        // that uid lists exactly this account's listeners and nobody else's.
        let connection = SpaceConnection(space: account)
        let listening: [ListeningPort]
        var workerNotice: String?
        do {
            let response = try connection.client.call(
                method: Method.portsList, token: connection.token, timeout: 5)
            if response.ok, let rows = response.result?["ports"]?.arrayValue {
                listening = rows.compactMap { row in
                    guard let port = row["port"]?.intValue,
                          let portNumber = UInt16(exactly: port),
                          let address = row["address"]?.stringValue else { return nil }
                    return ListeningPort(
                        address: address, port: portNumber,
                        process: row["process"]?.stringValue,
                        pid: row["pid"]?.intValue)
                }
            } else if let error = response.error, error.code == .methodNotFound {
                listening = []
                workerNotice = "the worker is older than this feature; let the app update it (offered after an app update) and the list appears"
            } else {
                listening = []
                workerNotice = "the worker could not list this account's ports: \(response.error.map { "\($0.code.rawValue) \($0.message)" } ?? "no result")"
            }
        } catch {
            listening = []
            workerNotice = "the worker is offline (\(error))"
        }

        // Distinct ports: several sockets can share a port (several addresses
        // or file descriptors); a person reads a port, not a socket. A
        // loopback-bound socket wins the representative row.
        var distinct: [UInt16: ListeningPort] = [:]
        for row in listening {
            if let existing = distinct[row.port], existing.coversLoopback, !row.coversLoopback { continue }
            distinct[row.port] = row
        }
        let ports = distinct.values.sorted { $0.port < $1.port }

        let portRows: [JSONValue] = ports.map { port in
            .obj([
                "port": .int(Int(port.port)),
                "address": .string(port.address),
                "loopback": .bool(port.coversLoopback),
                "process": port.process.map { .string($0) } ?? .null,
                "pid": port.pid.map { .int($0) } ?? .null,
            ])
        }

        var human: [String] = [
            "\(account.name): TCP ports this account's own processes are listening on",
        ]
        if let workerNotice { human.append("  \(workerNotice)") }
        for port in ports {
            let loopback = port.coversLoopback ? "" : "  (not on loopback)"
            human.append("  \(String(port.port).padding(toLength: 6, withPad: " ", startingAt: 0)) \(port.process ?? "?")  on \(port.address)\(loopback)")
        }
        if ports.isEmpty && workerNotice == nil {
            human.append("  nothing is listening right now")
        }
        human.append("  the main system reaches each of these at 127.0.0.1 with the same port number — no mapping needed")

        emitter.success(.obj([
            "ok": .bool(true),
            "account": .obj([
                "id": .string(account.id.uuidString),
                "name": .string(account.name),
            ]),
            "ports": .array(portRows),
            "workerNotice": workerNotice.map { .string($0) } ?? .null,
        ]), human: human.joined(separator: "\n"))
    }
}
