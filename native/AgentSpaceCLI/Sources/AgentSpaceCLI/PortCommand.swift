import Foundation
import AgentSpaceCore

/// `agentspace ports …` — the generated ports that map an agent account's
/// local services onto `127.0.0.1`.
///
/// The requirement this serves: an API the agent account runs locally has to
/// be callable from the main system at an address generated for it, with no
/// network at all. Every mapping gets a fixed generated port (45,000–46,999,
/// derived from the account id and the internal port), and the app serves it
/// on `127.0.0.1` with a forwarder while it is open. A per-account distinct
/// *IP* is not available to an unprivileged process on macOS — only addresses
/// assigned to `lo0` can be bound, and adding one is root — so the generated
/// address is a port. The CLI reads, verifies and writes the shared mapping
/// file; it does not host forwarders itself, and every message that depends on
/// hosting says so.
enum PortCommand {

    static func run(
        action: [String],
        parsed: ParsedArgs,
        root: String?,
        emitter: Emitter
    ) -> Never {
        let paths = VirtualNetworkPaths(root: root)
        let registry = SpaceRegistry.load(root: root)

        // No account named: one line per attached account.
        guard let reference = action.first else {
            let store = PortMapStore(paths: paths)
            let rows: [JSONValue] = registry.spaces.map { space in
                .obj([
                    "id": .string(space.id.uuidString),
                    "name": .string(space.name),
                    "mappings": .int(store.mappings(account: space.id).count),
                ])
            }
            let human = registry.spaces.isEmpty
                ? "no agent accounts are attached"
                : registry.spaces
                    .map { space in
                        let count = store.mappings(account: space.id).count
                        return "  \(space.name)  (\(count) mapped)"
                    }
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
            return list(account: account, paths: paths, emitter: emitter)
        case "map":
            return map(account: account, args: Array(args.dropFirst()), paths: paths, emitter: emitter)
        case "unmap":
            return unmap(account: account, args: Array(args.dropFirst()), paths: paths, emitter: emitter)
        case "address":
            return address(account: account, args: Array(args.dropFirst()), paths: paths, emitter: emitter)
        default:
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "unknown ports command '\(sub)'. Try: `agentspace ports <account>`, `… map <port> [main-system-port]`, `… unmap <port>`, `… address on|off`."))
        }
    }

    // MARK: address

    /// The fixed per-account address: a choice record plus the machine's own
    /// word. `on`/`off` write the choice; the app — the one process that owns
    /// the helper calls — applies it within a few seconds. The status read
    /// needs no privilege at all: getifaddrs says what lo0 really holds.
    private static func address(
        account: AgentAccount,
        args: [String],
        paths: VirtualNetworkPaths,
        emitter: Emitter
    ) -> Never {
        let registry = SpaceRegistry.load(root: paths.root)
        guard let alias = AgentLoopbackAddress.address(for: account.id, among: registry.spaces.map(\.id)) else {
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "the account is not in the registry, so it has no address"))
        }
        let store = AccountAddressStore(paths: paths)
        let present = LocalNetworkProbe.interfaceSnapshot()?.addresses
            .first(where: { $0 == alias }) != nil

        switch args.first ?? "status" {
        case "status", "":
            emitter.success(.obj([
                "ok": .bool(true),
                "account": .string(account.id.uuidString),
                "address": .string(alias.description),
                "enabled": .bool(store.isEnabled(account.id)),
                "onInterface": .bool(present),
                "note": .string("On/off writes the choice; the app applies it (and only the app asks the helper) within a few seconds."),
            ]), human: """
            fixed address: \(alias.description)  \(store.isEnabled(account.id) ? "enabled" : "off")  \(present ? "on lo0" : "not on lo0")
              `agentspace ports \(account.name) address on` / `off`; the app applies the change.
            """)

        case "on":
            do {
                let changed = try store.setEnabled(account.id, true)
                _ = changed
            } catch {
                emitter.failure(AgentSpaceError(
                    code: .internalError, message: "could not write the choice: \(error)"))
            }
            emitter.success(.obj([
                "ok": .bool(true),
                "address": .string(alias.description),
                "note": .string("The app puts it on lo0 through the helper within a few seconds, and mapped ports answer there at their own port numbers. Nothing is authorized while the feature is off."),
            ]), human: "fixed address enabled for \(account.name): \(alias.description) — the app applies it within a few seconds")

        case "off":
            do {
                _ = try store.setEnabled(account.id, false)
            } catch {
                emitter.failure(AgentSpaceError(
                    code: .internalError, message: "could not write the choice: \(error)"))
            }
            emitter.success(.obj([
                "ok": .bool(true),
                "address": .string(alias.description),
                "note": .string("The app removes the alias within a few seconds; the mapping ports on 127.0.0.1 are untouched."),
            ]), human: "fixed address disabled for \(account.name) — the app removes the alias within a few seconds")

        default:
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "unknown address command '\(args.first!)'. Try: `agentspace ports <account> address on|off`."))
        }
    }

    // MARK: list

    private static func list(account: AgentAccount, paths: VirtualNetworkPaths, emitter: Emitter) -> Never {
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
            workerNotice = "the worker is offline (\(error)); mappings keep their configuration but refuse connections"
        }

        // Distinct ports: several sockets can share a port (several addresses
        // or file descriptors); a person maps a port, not a socket. A
        // loopback-bound socket wins the representative row.
        var distinct: [UInt16: ListeningPort] = [:]
        for row in listening {
            if let existing = distinct[row.port], existing.coversLoopback, !row.coversLoopback { continue }
            distinct[row.port] = row
        }
        let ports = distinct.values.sorted { $0.port < $1.port }

        let store = PortMapStore(paths: paths)
        let mappings = store.mappings(account: account.id)

        // The fixed address, if the feature is on for this account — read from
        // the machine, like every state this command reports.
        let registry = SpaceRegistry.load(root: paths.root)
        let alias = AgentLoopbackAddress.address(for: account.id, among: registry.spaces.map(\.id))
        let aliasOn = alias.map { AccountAddressStore(paths: paths).isEnabled(account.id) && LocalNetworkProbe.interfaceSnapshot()?.addresses.contains($0) == true }

        var mappedRows: [JSONValue] = []
        var humanMapped: [String] = []
        for mapping in mappings {
            let answering = TCPProbe.answers(host: "127.0.0.1", port: mapping.external)
            mappedRows.append(.obj([
                "port": .int(Int(mapping.port)),
                "externalPort": .int(Int(mapping.external)),
                "endpoint": .string(mapping.endpoint),
                "answering": .bool(answering),
                "serviceListening": .bool(distinct[mapping.port] != nil),
            ]))
            humanMapped.append(
                "  \(mapping.endpoint.padding(toLength: 15, withPad: " ", startingAt: 0)) → port \(mapping.port)  \(answering ? "answering" : "not answering")\(distinct[mapping.port] == nil ? "  (nothing is listening on it right now)" : "")")
        }

        let portRows: [JSONValue] = ports.map { port in
            .obj([
                "port": .int(Int(port.port)),
                "address": .string(port.address),
                "loopback": .bool(port.coversLoopback),
                "process": port.process.map { .string($0) } ?? .null,
                "pid": port.pid.map { .int($0) } ?? .null,
                "mapped": .bool(mappings.contains { $0.port == port.port }),
            ])
        }

        var human: [String] = [
            "\(account.name): services on 127.0.0.1, mapped onto fixed ports of 127.0.0.1",
        ]
        if let alias {
            human.append("  fixed address \(alias.description): \(AccountAddressStore(paths: paths).isEnabled(account.id) ? "enabled" : "off")\(aliasOn == true ? " — on lo0" : "")")
        }
        if let workerNotice { human.append("  \(workerNotice)") }
        for port in ports {
            let mapping = mappings.first { $0.port == port.port }
            let destination = mapping.map { "→ \($0.endpoint)" } ?? "[not mapped]"
            let loopback = port.coversLoopback ? "" : "  (not on loopback)"
            human.append("  \(String(port.port).padding(toLength: 6, withPad: " ", startingAt: 0)) \(port.process ?? "?")  on \(port.address)\(loopback)  \(destination)")
        }
        if !mappings.isEmpty { human.append("mapped ports:") }
        human.append(contentsOf: humanMapped)
        if mappings.isEmpty {
            human.append("  nothing mapped yet: `agentspace ports \(account.name) map <port>`")
        }
        let humanText = human.joined(separator: "\n")

        emitter.success(.obj([
            "ok": .bool(true),
            "account": .obj([
                "id": .string(account.id.uuidString),
                "name": .string(account.name),
            ]),
            "ports": .array(portRows),
            "mappings": .array(mappedRows),
            "fixedAddress": alias.map { address in
                .obj([
                    "address": .string(address.description),
                    "enabled": .bool(AccountAddressStore(paths: paths).isEnabled(account.id)),
                    "onInterface": .bool(aliasOn == true),
                ])
            } ?? .null,
            "workerNotice": workerNotice.map { .string($0) } ?? .null,
            "note": .string("Forwarders are served by the AgentSpace app while it is open; the CLI writes the shared mapping file."),
        ]), human: humanText)
    }

    // MARK: map / unmap

    private static func map(
        account: AgentAccount,
        args: [String],
        paths: VirtualNetworkPaths,
        emitter: Emitter
    ) -> Never {
        guard let text = args.first, let port = UInt16(text), port != 0 else {
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "usage: agentspace ports <account> map <port> [main-system-port]"))
        }
        // A person-chosen external port, like `map 8080 28080`; absent means
        // the generator picks one. `map 8080 8080` is refused — that port on
        // 127.0.0.1 belongs to the service itself.
        var chosen: UInt16?
        if let externalText = args.dropFirst().first {
            guard let parsed = UInt16(externalText), parsed != 0 else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "the main-system port must be a number between 1 and 65535"))
            }
            chosen = parsed
        }

        // Fail closed on ownership: a mapping is only written for a port this
        // account is really listening on, verified through its own worker.
        // Without that check the forwarder could point the generated port at
        // whichever other account holds the internal port on the shared stack.
        let connection = SpaceConnection(space: account)
        var owned = false
        var coversLoopback = false
        var reason = "the worker did not answer"
        do {
            let response = try connection.client.call(
                method: Method.portsList, token: connection.token, timeout: 5)
            if let error = response.error {
                reason = error.code == .methodNotFound
                    ? "the worker is older than this feature; let the app update it first"
                    : "\(error.code.rawValue): \(error.message)"
            } else if let rows = response.result?["ports"]?.arrayValue {
                let matches = rows.filter { $0["port"]?.intValue == Int(port) }
                owned = !matches.isEmpty
                coversLoopback = matches.contains { $0["loopback"]?.boolValue == true }
                if !owned {
                    reason = "nothing in this account's session is listening on port \(port)"
                } else if !coversLoopback {
                    reason = "port \(port) is bound only to a non-loopback address; the mapping could not reach it with no network"
                }
            }
        } catch {
            reason = "the worker is offline (\(error))"
        }
        guard owned, coversLoopback else {
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "port \(port) cannot be mapped for \(account.name): \(reason)."))
        }

        // The external port: the person's choice when given (validated —
        // outside the generated range, not the service's own port, not another
        // mapping's, nothing already listening), the deterministic generator
        // otherwise.
        let store = PortMapStore(paths: paths)
        let external: UInt16
        if let chosen {
            if let problem = AgentPortAllocator.manualPortProblem(chosen, internal: port) {
                emitter.failure(AgentSpaceError(code: .badRequest, message: problem))
            }
            if store.externalPortsInUse().contains(chosen) {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "port \(chosen) already belongs to another mapping"))
            }
            if TCPProbe.answers(host: "127.0.0.1", port: chosen, timeout: 0.6) {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "something on this Mac is already listening on 127.0.0.1:\(chosen)"))
            }
            external = chosen
        } else {
            let taken = store.externalPortsInUse()
            guard let generated = AgentPortAllocator.choose(account: account.id, port: port, isFree: { candidate in
                !taken.contains(candidate) && !TCPProbe.answers(host: "127.0.0.1", port: candidate, timeout: 0.6)
            }) else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "no free port in \(AgentPortAllocator.range.lowerBound)–\(AgentPortAllocator.range.upperBound); unmap one first"))
            }
            external = generated
        }

        do {
            let added = try store.add(account: account.id, port: port, external: external)
            emitter.success(.obj([
                "ok": .bool(true),
                "added": .bool(added),
                "account": .string(account.id.uuidString),
                "port": .int(Int(port)),
                "externalPort": .int(Int(external)),
                "endpoint": .string("127.0.0.1:\(external)"),
                "note": .string("The app serves this port within a few seconds while it is open."),
            ]), human: added
                ? "mapped: 127.0.0.1:\(external) → this account's port \(port) — the app serves it within a few seconds while it is open"
                : "already mapped")
        } catch {
            emitter.failure(AgentSpaceError(
                code: .internalError, message: "could not write the mapping file: \(error)"))
        }
    }

    private static func unmap(
        account: AgentAccount,
        args: [String],
        paths: VirtualNetworkPaths,
        emitter: Emitter
    ) -> Never {
        guard let text = args.first, let port = UInt16(text), port != 0 else {
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "usage: agentspace ports <account> unmap <port>"))
        }
        do {
            let removed = try PortMapStore(paths: paths).remove(account: account.id, port: port)
            emitter.success(.obj([
                "ok": .bool(true),
                "removed": .bool(removed),
                "account": .string(account.id.uuidString),
                "port": .int(Int(port)),
            ]), human: removed
                ? "unmapped: the app stops the forwarder within a few seconds"
                : "was not mapped")
        } catch {
            emitter.failure(AgentSpaceError(
                code: .internalError, message: "could not write the mapping file: \(error)"))
        }
    }
}
