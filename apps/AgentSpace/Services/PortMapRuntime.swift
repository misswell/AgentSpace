import Foundation
import Combine
import AgentSpaceCore
import os

/// Owns the mapped-port forwarders while the app is open.
///
/// The mapping list is shared state in `<root>/Network/port-map.json`, exactly
/// like the API's `api.json`: the account page and the CLI write the file, and
/// this runtime reconciles it into real listeners every few seconds — start a
/// `PortForwarder` for a mapping that has none, stop the ones the file no
/// longer names, and publish the state the account page shows. Nothing about a
/// mapping requires the person to keep a viewer open; closing the app closes
/// the forwarders, which the page says out loud.
@MainActor
final class PortMapRuntime: ObservableObject {

    enum MappingState: Equatable {
        /// The forwarder is serving the generated port.
        case forwarding
        /// Another local process holds the generated port. The mapping is kept;
        /// re-creating it chooses a fresh port.
        case busy
        /// The account is detached or its worker cannot prove ownership, so
        /// the mapping is kept but not served. Fail closed.
        case waiting
        case blocked(String)

        var displayName: String {
            switch self {
            case .forwarding: return NSLocalizedString("mapped", comment: "")
            case .busy: return NSLocalizedString("port taken by another process", comment: "")
            case .waiting: return NSLocalizedString("waiting for the worker", comment: "")
            case .blocked(let reason): return reason
            }
        }
    }

    struct Entry: Identifiable, Equatable {
        let account: UUID
        let accountName: String
        /// The port inside the agent account's session.
        let port: UInt16
        /// The generated port the main system calls.
        let external: UInt16
        let state: MappingState

        var id: String { "\(account.uuidString.lowercased())/\(port)" }
        var endpoint: String { "127.0.0.1:\(external)" }
    }

    @Published private(set) var entries: [Entry] = []

    private var forwarders: [String: PortForwarder] = [:]
    private var timer: Timer?
    private var reconciling = false
    private let ownership = PortOwnershipCache()
    private let log = Logger(subsystem: BundleIdentifiers.logSubsystem, category: "port-map")

    func start() {
        guard timer == nil else { return }
        reconcile()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
    }

    /// Map one port: verify the account owns it through its own worker, pick a
    /// generated external port nothing else holds, write the mapping. The
    /// reconcile that follows starts the forwarder.
    func map(account: UUID, port: UInt16) throws {
        let store = PortMapStore()
        let taken = store.externalPortsInUse()
        guard let external = AgentPortAllocator.choose(account: account, port: port, isFree: { candidate in
            !taken.contains(candidate) && !TCPProbe.answers(host: "127.0.0.1", port: candidate, timeout: 0.6)
        }) else {
            throw AgentSpaceError(
                code: .badRequest,
                message: "no free port in \(AgentPortAllocator.range.lowerBound)–\(AgentPortAllocator.range.upperBound); unmapping one first")
        }
        guard try store.add(account: account, port: port, external: external) else {
            throw AgentSpaceError(
                code: .badRequest,
                message: "port \(port) is already mapped for this account")
        }
        reconcile()
    }

    func unmap(account: UUID, port: UInt16) throws {
        try PortMapStore().remove(account: account, port: port)
        reconcile()
    }

    func isMapped(_ account: UUID, _ port: UInt16) -> Bool {
        PortMapStore().mappings(account: account).contains { $0.port == port }
    }

    /// Reconcile the file into forwarders. Runs its blocking work (listener
    /// binds, ownership checks) off the main thread, then publishes on the
    /// main actor.
    func reconcile() {
        guard !reconciling else { return }
        reconciling = true
        let ownership = self.ownership
        Task.detached(priority: .utility) { [weak self] in
            let outcome = await Self.reconcileOffMain(ownership: ownership)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apply(outcome)
                self.reconciling = false
            }
        }
    }

    /// One reconciliation pass, on a background task. Returns the forwarders
    /// to keep and the entries to publish; the caller applies both on the main
    /// actor.
    private static func reconcileOffMain(ownership: PortOwnershipCache)
        async -> (forwarders: [String: PortForwarder], entries: [Entry]) {

        let registry = SpaceRegistry.load()
        let file = PortMapStore().load()

        var forwarders: [String: PortForwarder] = [:]
        var entries: [Entry] = []

        // Keep the ownership cache's view of the registry current, so a gate
        // call can resolve the account even before its own first refresh.
        ownership.updateAccounts(registry.spaces)

        for mapping in file.mappings {
            let key = mapping.id
            guard let space = registry.spaces.first(where: { $0.id == mapping.account }) else {
                entries.append(Entry(
                    account: mapping.account,
                    accountName: mapping.account.uuidString,
                    port: mapping.port,
                    external: mapping.external,
                    state: .blocked(NSLocalizedString("the account is detached", comment: ""))))
                continue
            }

            // Trust, but verify: the mapping names a port, and the account has
            // to still own it. The verdict drives both the entry shown and the
            // forwarder's own per-connection gate.
            let owns = ownership.gate(mapping.account, mapping.port)
            let state: MappingState
            var forwarder: PortForwarder?

            if owns {
                let candidate = PortForwarder(
                    accountID: mapping.account,
                    externalPort: mapping.external,
                    internalPort: mapping.port)
                do {
                    try candidate.start(gate: { ownership.gate(mapping.account, mapping.port) })
                    forwarder = candidate
                    state = .forwarding
                } catch PortForwarder.StartError.addressBusy {
                    state = .busy
                } catch {
                    state = .blocked(String(describing: error))
                }
            } else {
                state = .waiting
            }

            if let forwarder {
                forwarders[key] = forwarder
            }
            entries.append(Entry(
                account: mapping.account,
                accountName: space.name,
                port: mapping.port,
                external: mapping.external,
                state: state))
        }

        entries.sort { ($0.accountName, $0.port) < ($1.accountName, $1.port) }
        return (forwarders, entries)
    }

    private func apply(_ outcome: (forwarders: [String: PortForwarder], entries: [Entry])) {
        for (key, forwarder) in forwarders where outcome.forwarders[key] == nil {
            forwarder.stop()
            log.info("forwarder \(key, privacy: .public) stopped")
        }
        self.forwarders = outcome.forwarders
        if entries != self.entries {
            self.entries = entries
        }
        for entry in entries where entry.state == .forwarding {
            log.debug("mapping \(entry.endpoint, privacy: .public) → port \(entry.port, privacy: .public)")
        }
    }
}

/// The forwarders' ownership gate, called on their own queues — not on the
/// main actor, and never allowed to answer "yes" without evidence.
///
/// All accounts on this Mac share one kernel network stack, which is what
/// makes the whole feature possible and what makes this check necessary:
/// `127.0.0.1:<port>` cannot say whose service it is, so before any byte is
/// forwarded the worker in that account's session is asked for the ports its
/// own uid listens on. A worker that cannot be asked — offline, restarting,
/// too old to know `ports.list` — means no evidence, and no evidence means the
/// connection is refused. A stale verdict (>2 s) is refreshed synchronously;
/// the cost lands on the forwarder's serial queue and only on the first
/// connection after the verdict expires.
final class PortOwnershipCache: @unchecked Sendable {

    private let lock = NSLock()
    private var accounts: [UUID: AgentAccount] = [:]
    private var verdicts: [UUID: (at: Date, ports: Set<UInt16>)] = [:]
    private let staleness: TimeInterval = 2

    func updateAccounts(_ spaces: [AgentAccount]) {
        lock.lock()
        defer { lock.unlock() }
        accounts = Dictionary(spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Whether this account listens on this port *right now*. Fail closed.
    func gate(_ account: UUID, _ port: UInt16) -> Bool {
        if fresh(account) { return cached(account).contains(port) }
        refresh(account)
        return cached(account).contains(port)
    }

    private func cached(_ account: UUID) -> Set<UInt16> {
        lock.lock()
        defer { lock.unlock() }
        return verdicts[account]?.ports ?? []
    }

    private func fresh(_ account: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let verdict = verdicts[account] else { return false }
        return Date().timeIntervalSince(verdict.at) < staleness
    }

    /// Ask the account's worker for its listening ports. Any failure records
    /// an empty set: the next gate call refuses rather than forwarding into
    /// whatever else might hold the port.
    func refresh(_ account: UUID) {
        lock.lock()
        let space = accounts[account]
        lock.unlock()
        guard let space else {
            store(account, ports: [])
            return
        }
        let connection = SpaceConnection(space: space)
        do {
            let response = try connection.client.call(
                method: Method.portsList, token: connection.token, timeout: 2.5)
            guard response.ok, let result = response.result,
                  let rows = result["ports"]?.arrayValue else {
                store(account, ports: [])
                return
            }
            let ports = Set(rows.compactMap { row in
                row["port"]?.intValue.flatMap { UInt16(exactly: $0) }
            })
            store(account, ports: ports)
        } catch {
            store(account, ports: [])
        }
    }

    private func store(_ account: UUID, ports: Set<UInt16>) {
        lock.lock()
        defer { lock.unlock() }
        verdicts[account] = (Date(), ports)
    }
}
