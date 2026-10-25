import Foundation
import Combine
import AgentSpaceCore
import os

/// Owns the mapped-port forwarders and, when a person switches it on per
/// account, the fixed loopback address — while the app is open.
///
/// Two reconciles run on the same 3-second tick, and both treat the machine,
/// not a file, as the truth they converge to:
///
/// - **Mappings** (`<root>/Network/port-map.json`) become real listeners:
///   one on `127.0.0.1:<external>` — the generated or person-chosen port —
///   and, when the account's fixed address is really on `lo0`, a second one
///   on `127.100.x.y:<internal>` where the port number stays the service's
///   own. Both ask the ownership gate before forwarding a single byte.
/// - **Addresses** (`<root>/Network/account-addresses.json`) become aliases
///   on `lo0` through the helper's typed `addLoopbackAlias`/`removeLoopbackAlias`
///   operations. The helper's reply is never the verdict: `getifaddrs` is
///   re-read afterwards, and what the UI reports is what the interface really
///   holds. An alias no enabled account owns is removed — the crash-cleanup
///   path — and nothing happens at all until somebody switches the feature
///   on, which is the 「不开启就不需要多余授权」 promise.
@MainActor
final class PortMapRuntime: ObservableObject {

    enum MappingState: Equatable {
        case forwarding
        /// Another local process holds the external port. The mapping is kept;
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

    /// The fixed-address feature's per-account state, read from the machine.
    enum AddressState: Equatable {
        case off
        case pending
        case active(String)
        case failed(String)
    }

    struct Entry: Identifiable, Equatable {
        let account: UUID
        let accountName: String
        /// The port inside the agent account's session.
        let port: UInt16
        /// The generated or person-chosen port on 127.0.0.1.
        let external: UInt16
        let state: MappingState
        /// The account's fixed address endpoint for this mapping, when the
        /// address is really on the interface.
        let aliasEndpoint: String?
        let aliasState: MappingState?

        var id: String { "\(account.uuidString.lowercased())/\(port)" }
        var endpoint: String { "127.0.0.1:\(external)" }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var addressStates: [UUID: AddressState] = [:]

    private var forwarders: [String: PortForwarder] = [:]
    private var timer: Timer?
    private var reconciling = false
    private let ownership = PortOwnershipCache()
    /// A failed helper call is retried no sooner than this, so a missing or
    /// too-old helper is asked a question every 20 s, not every tick.
    private var nextHelperAttempt: Date = .distantPast
    private let log = Logger(subsystem: BundleIdentifiers.logSubsystem, category: "port-map")

    func start() {
        guard timer == nil else { return }
        reconcile()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
    }

    // MARK: Choices the surfaces write

    /// Every way adding a mapping or switching the address can fail, with the
    /// sentence a person reads for each — a normal user never sees a raw
    /// NSError or an English product message in the card.
    enum ActionError: Error, Equatable {
        /// The worker could not be asked: offline, or older than `ports.list`.
        case workerUnavailable(notice: WorkerNotice)
        case rule(PortMapRules.Problem)
        /// The port answers on the shared loopback, but the account's own
        /// worker reports no listener of its own — the holder is outside this
        /// account, and no mapping is what that service needs.
        case listeningOutsideAccount(UInt16)
        case externalPortInUse(UInt16)
        case noFreePort
        case storePermissionDenied
        case accountDetached

        enum WorkerNotice: Error, Equatable { case offline, tooOld }

        var message: String {
            switch self {
            case .workerUnavailable(.offline):
                return NSLocalizedString("The agent account's worker is offline — its desktop may be signed out or asleep. The list refreshes automatically every few seconds; open the desktop once and it comes back.", comment: "")
            case .workerUnavailable(.tooOld):
                return NSLocalizedString("The worker is older than this feature. Press “更新 Worker” above once (the app guides the one-time update), and the port list appears.", comment: "")
            case .rule(.notListening(let port)):
                return String(format: NSLocalizedString("Nothing in this account is listening on port %d right now. Start the service in the agent's desktop first, or pick a port from the “正在监听” row.", comment: ""), Int(port))
            case .listeningOutsideAccount(let port):
                return String(format: NSLocalizedString("Port %d answers on this Mac's loopback, but nothing in this account is listening on it — the listener is held outside this account (the main system, another account, or a system service). Every account shares one loopback, so the main system already reaches it at 127.0.0.1:%d with no mapping; a mapping only names a port this account itself listens on.", comment: ""), Int(port), Int(port))
            case .rule(.invalidInternal):
                return NSLocalizedString("The agent account port must be a number between 1 and 65535.", comment: "")
            case .rule(.notOnLoopback(let port)):
                return String(format: NSLocalizedString("Port %d is bound only to a non-loopback address, so it cannot be reached with no network. Re-bind the service to 127.0.0.1 (or all interfaces) inside the agent's desktop.", comment: ""), Int(port))
            case .rule(.alreadyMapped(let port)):
                return String(format: NSLocalizedString("Port %d is already mapped — remove that mapping first if you want to recreate it.", comment: ""), Int(port))
            case .rule(.invalidExternal(.belowPrivilegedFloor)):
                return NSLocalizedString("The main-system port must be 1024 or higher — lower ports are reserved for the system.", comment: "")
            case .rule(.invalidExternal(.isInternalPort)):
                return NSLocalizedString("The main-system port cannot equal the account's own port — that one belongs to the service itself.", comment: "")
            case .rule(.invalidExternal(.insideGeneratedRange)):
                return String(format: NSLocalizedString("Ports %d–%d are reserved for automatic generation; choose a port outside that range or leave the field empty.", comment: ""), Int(AgentPortAllocator.range.lowerBound), Int(AgentPortAllocator.range.upperBound))
            case .rule(.externalTakenByMapping(let port)):
                return String(format: NSLocalizedString("Port %d already belongs to another mapping.", comment: ""), Int(port))
            case .rule(.externalInUse(let port)), .externalPortInUse(let port):
                return String(format: NSLocalizedString("Something else on this Mac is already listening on 127.0.0.1:%d — pick another port.", comment: ""), Int(port))
            case .externalPortInUse(let port):
                return String(format: NSLocalizedString("Something else on this Mac is already listening on 127.0.0.1:%d — pick another port.", comment: ""), Int(port))
            case .noFreePort:
                return NSLocalizedString("No automatic port is free right now — remove one mapping or choose a port by hand.", comment: "")
            case .storePermissionDenied:
                return NSLocalizedString("The configuration folder is not ready on this Mac yet. Update AgentSpace and allow the one-time helper and worker updates — they create it — then try again. Nothing you chose was lost.", comment: "")
            case .accountDetached:
                return NSLocalizedString("This account is detached, so its ports cannot be mapped. Re-attach it from the dashboard first.", comment: "")
            }
        }
    }

    /// Map one port: verify the account owns it through its own worker, apply
    /// every rule before anything is written, then pick the external port —
    /// the person's choice when given, the generator's otherwise. The worker
    /// call and the freeness probes run OFF the main actor (§404: a hung
    /// worker must never freeze the interface), so the card awaits this.
    func map(account: UUID, port: UInt16, external chosen: UInt16? = nil) async throws -> UInt16 {
        // Ownership first, fail closed: without the account's own worker there
        // is no evidence, and no evidence means no mapping.
        guard let space = SpaceRegistry.load().spaces.first(where: { $0.id == account }) else {
            throw ActionError.accountDetached
        }
        let external: UInt16 = try await Task.detached(priority: .userInitiated) { () -> UInt16 in
            let listening: [ListeningPort]
            switch Self.ownershipEvidence(for: space) {
            case .failure(let notice):
                throw ActionError.workerUnavailable(notice: notice)
            case .success(let ports):
                listening = ports
            }
            let store = PortMapStore()
            let takenExternals = store.externalPortsInUse()
            if let problem = PortMapRules.validate(
                internal: port,
                listening: listening,
                mappedPorts: Set(store.mappings(account: account).map(\.port)),
                chosenExternal: chosen,
                takenExternals: takenExternals) {
                if case .notListening = problem,
                   PortMapRules.notListeningRefinement(
                    probeAnswers: TCPProbe.answers(host: "127.0.0.1", port: port, timeout: 0.6),
                    portIsAMappingEndpoint: takenExternals.contains(port)) == .heldOutsideAccount {
                    throw ActionError.listeningOutsideAccount(port)
                }
                throw ActionError.rule(problem)
            }
            if let chosen, TCPProbe.answers(host: "127.0.0.1", port: chosen, timeout: 0.6) {
                throw ActionError.externalPortInUse(chosen)
            }
            if let chosen {
                return chosen
            }
            let taken = store.externalPortsInUse()
            guard let generated = AgentPortAllocator.choose(
                account: account, port: port,
                isFree: { candidate in
                    // 0.2 s is enough on loopback, where a closed port refuses
                    // instantly; only a genuinely held port pays the timeout,
                    // and the walk stops at the first free candidate anyway.
                    !taken.contains(candidate)
                        && !TCPProbe.answers(host: "127.0.0.1", port: candidate, timeout: 0.2)
                }) else {
                throw ActionError.noFreePort
            }
            return generated
        }.value

        do {
            guard try PortMapStore().add(account: account, port: port, external: external) else {
                throw ActionError.rule(.alreadyMapped(port))
            }
        } catch let error where SharedRootWrite.isPermissionDenied(error) {
            throw ActionError.storePermissionDenied
        }
        reconcile()
        return external
    }
    nonisolated static func ownershipEvidence(for space: AgentAccount) -> Result<[ListeningPort], ActionError.WorkerNotice> {
        let connection = SpaceConnection(space: space)
        do {
            let response = try connection.client.call(
                method: Method.portsList, token: connection.token, timeout: 5)
            if response.ok, let rows = response.result?["ports"]?.arrayValue {
                return .success(rows.compactMap { row in
                    guard let port = row["port"]?.intValue,
                          let portNumber = UInt16(exactly: port),
                          let address = row["address"]?.stringValue else { return nil }
                    return ListeningPort(
                        address: address, port: portNumber,
                        process: row["process"]?.stringValue,
                        pid: row["pid"]?.intValue)
                })
            }
            if let error = response.error, error.code == .methodNotFound {
                return .failure(.tooOld)
            }
            return .failure(.offline)
        } catch {
            return .failure(.offline)
        }
    }

    /// Ask for the fixed address (or a failed helper call) to be retried
    /// immediately instead of waiting for the 20-second throttle.
    func retryNow() {
        nextHelperAttempt = .distantPast
        reconcile()
    }

    func unmap(account: UUID, port: UInt16) throws {
        do {
            try PortMapStore().remove(account: account, port: port)
        } catch let error where SharedRootWrite.isPermissionDenied(error) {
            throw ActionError.storePermissionDenied
        }
        reconcile()
    }

    func isMapped(_ account: UUID, _ port: UInt16) -> Bool {
        PortMapStore().mappings(account: account).contains { $0.port == port }
    }

    /// The account's fixed address if the feature is switched on, resolved
    /// against the other attached accounts so every observer agrees.
    func alias(for account: UUID) -> IPv4Address? {
        let registry = SpaceRegistry.load()
        return AgentLoopbackAddress.address(for: account, among: registry.spaces.map(\.id))
    }

    func isAddressEnabled(_ account: UUID) -> Bool {
        AccountAddressStore().isEnabled(account)
    }

    /// Switch the fixed-address feature. The reconcile that follows is what
    /// asks the helper — nothing about the switch itself needs a privilege.
    func setAddressEnabled(_ account: UUID, _ enabled: Bool) throws {
        do {
            try AccountAddressStore().setEnabled(account, enabled)
        } catch let error where SharedRootWrite.isPermissionDenied(error) {
            throw ActionError.storePermissionDenied
        }
        nextHelperAttempt = .distantPast
        reconcile()
    }

    /// For the UI: the listening ports of one account's session, from its own
    /// worker. Failures surface as nil; the card decides how to word them.
    func listeningPorts(_ account: AgentAccount) -> [ListeningPort]? {
        let connection = SpaceConnection(space: account)
        guard let response = try? connection.client.call(
            method: Method.portsList, token: connection.token, timeout: 5),
            response.ok, let rows = response.result?["ports"]?.arrayValue else {
            return nil
        }
        return rows.compactMap { row in
            guard let port = row["port"]?.intValue,
                  let portNumber = UInt16(exactly: port),
                  let address = row["address"]?.stringValue else { return nil }
            return ListeningPort(
                address: address, port: portNumber,
                process: row["process"]?.stringValue,
                pid: row["pid"]?.intValue)
        }
    }

    // MARK: Reconcile

    func reconcile() {
        guard !reconciling else { return }
        reconciling = true
        let ownership = self.ownership
        let helperAllowed = Date() >= nextHelperAttempt
        // The live forwarders travel with the pass: a healthy, identity-matching
        // listener is KEPT — starting a new one on the same endpoint every pass
        // is the flapping defect §404 found, and this is its fix.
        let existing = self.forwarders
        Task.detached(priority: .utility) { [weak self] in
            let outcome = await Self.reconcileOffMain(
                ownership: ownership, helperAllowed: helperAllowed, existing: existing)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apply(outcome)
                self.reconciling = false
            }
        }
    }

    /// The keep-or-recreate decision for one mapping's forwarders, as one pure
    /// function so the flapping fix itself can be pinned by a test: a forwarder
    /// is kept when it is running AND still serves this mapping's identity
    /// (endpoint for the primary, alias+internal port for the alias), and is
    /// recreated otherwise — including when the mapping was recreated with a
    /// different external port under the same key.
    nonisolated static func forwarderPlan(
        for mapping: PortMapping,
        aliasAddress: IPv4Address?,
        existing: [String: PortForwarder]
    ) -> (keepPrimary: PortForwarder?, recreatePrimary: Bool,
          keepAlias: PortForwarder?, recreateAlias: Bool) {
        let primary = existing[mapping.id]
        let alias = existing[mapping.id + "#alias"]
        let healthyPrimary = primary.map { $0.isRunning && $0.endpoint == "127.0.0.1:\(mapping.external)" } == true
        let healthyAlias = alias.map {
            $0.isRunning && aliasAddress != nil
                && $0.listenHost == aliasAddress!.description
                && $0.externalPort == mapping.port
        } == true
        return (healthyPrimary ? primary : nil, !healthyPrimary,
                healthyAlias ? alias : nil, aliasAddress != nil && !healthyAlias)
    }

    /// One pass, off the main actor. Returns the forwarders to keep, the
    /// entries and address states to publish, and whether the next pass may
    /// talk to the helper again.
    private static func reconcileOffMain(ownership: PortOwnershipCache, helperAllowed: Bool,
                                         existing: [String: PortForwarder])
        async -> (forwarders: [String: PortForwarder], entries: [Entry],
                 addresses: [UUID: AddressState], retryHelper: Bool) {

        let registry = SpaceRegistry.load()
        let file = PortMapStore().load()
        let addressFile = AccountAddressStore().load()

        // The aliases the machine really holds, from getifaddrs — the truth
        // the helper's replies are checked against.
        let present: Set<UInt32> = Set(
            (LocalNetworkProbe.interfaceSnapshot()?.addresses ?? [])
                .filter(AgentLoopbackAddress.isAlias)
                .map(\.rawValue))

        let attached = registry.spaces.map(\.id)
        let attachedSet = Set(attached)
        let enabled = addressFile.enabled.filter { attachedSet.contains($0) }
        let table = AgentLoopbackAddress.addresses(for: attached)
        let desired: Set<UInt32> = Set(enabled.compactMap { table[$0]?.rawValue })

        var addresses: [UUID: AddressState] = [:]
        var retryHelper = true
        var helperSucceededSinceRead = false

        func callHelper(_ operation: HelperOperation, _ address: IPv4Address) -> String? {
            do {
                let reply = try HelperClient.call(
                    HelperRequest(operation: operation, address: address.description),
                    timeout: 10)
                if let error = reply.error {
                    return "\(error.code.rawValue): \(error.message)"
                }
                helperSucceededSinceRead = true
                return nil
            } catch {
                return String(describing: error)
            }
        }

        // Add what an enabled account is missing. While a previous failure is
        // still throttled the state stays .pending — "not yet", not "broken".
        for account in enabled {
            guard let address = table[account] else { continue }
            addresses[account] = .pending
            if !present.contains(address.rawValue), helperAllowed {
                if let failure = callHelper(.addLoopbackAlias, address) {
                    addresses[account] = .failed(failure)
                    retryHelper = false
                }
            }
        }

        // Remove what no enabled account owns: switched off, account detached,
        // or left behind by a crash — same path, because the file never was
        // the truth. Only aliases this product could have derived are touched:
        // a person who put their own 127.100.x.y on lo0 by hand keeps it, even
        // if they never use this feature (§404's review finding).
        if helperAllowed {
            let derivable = Set(table.values.map(\.rawValue))
            for raw in present where !desired.contains(raw) && derivable.contains(raw) {
                _ = callHelper(.removeLoopbackAlias, IPv4Address(rawValue: raw))
            }
        }

        // Re-read the machine. What it holds *now* is what the UI reports and
        // what the alias forwarders bind, regardless of what the helper said.
        let presentNow: Set<UInt32> = helperSucceededSinceRead
            ? Set((LocalNetworkProbe.interfaceSnapshot()?.addresses ?? [])
                .filter(AgentLoopbackAddress.isAlias)
                .map(\.rawValue))
            : present
        for account in enabled {
            guard let address = table[account] else { continue }
            if presentNow.contains(address.rawValue) {
                addresses[account] = .active(address.description)
            } else if case .failed = addresses[account] {
                // keep the failure reason for the person to read
            } else {
                addresses[account] = .pending
            }
        }

        // Forwarders: the 127.0.0.1 one every mapping has, plus the alias one
        // when the address is really held.
        var forwarders: [String: PortForwarder] = [:]
        var entries: [Entry] = []
        ownership.updateAccounts(registry.spaces)

        for mapping in file.mappings {
            guard let space = registry.spaces.first(where: { $0.id == mapping.account }) else {
                entries.append(Entry(
                    account: mapping.account, accountName: mapping.account.uuidString,
                    port: mapping.port, external: mapping.external,
                    state: .blocked(NSLocalizedString("the account is detached", comment: "")),
                    aliasEndpoint: nil, aliasState: nil))
                continue
            }

            // A kept forwarder is kept regardless of this pass's ownership
            // verdict: its own per-connection gate refuses when the account
            // stops owning the port, and churning the listener on every
            // verdict change is the flapping §404 removed.
            let aliasAddress = table[mapping.account].flatMap {
                presentNow.contains($0.rawValue) ? $0 : nil
            }
            let plan = forwarderPlan(for: mapping, aliasAddress: aliasAddress, existing: existing)

            let owns = ownership.gate(mapping.account, mapping.port)
            var primaryFailure: String?
            var aliasFailure: String?
            var primary: PortForwarder?
            var aliasForwarder: PortForwarder?

            if let kept = plan.keepPrimary {
                primary = kept
            } else if plan.recreatePrimary, owns {
                let candidate = PortForwarder(
                    accountID: mapping.account,
                    externalPort: mapping.external,
                    internalPort: mapping.port)
                do {
                    try candidate.start(gate: { ownership.gate(mapping.account, mapping.port) })
                    primary = candidate
                } catch PortForwarder.StartError.addressBusy {
                    // Someone else holds the external port; the mapping keeps
                    // its stored port and the badge says so.
                } catch {
                    primaryFailure = String(describing: error)
                }
            }
            var aliasEndpoint: String?
            if let aliasAddress {
                aliasEndpoint = "\(aliasAddress.description):\(mapping.port)"
                if let kept = plan.keepAlias {
                    aliasForwarder = kept
                } else if plan.recreateAlias, owns {
                    let aliasCandidate = PortForwarder(
                        accountID: mapping.account,
                        externalPort: mapping.port,
                        internalPort: mapping.port,
                        listenHost: aliasAddress.description)
                    do {
                        try aliasCandidate.start(gate: { ownership.gate(mapping.account, mapping.port) })
                        aliasForwarder = aliasCandidate
                    } catch PortForwarder.StartError.addressBusy {
                        // The service itself binds the alias's port — which only
                        // its own wide-bound (0.0.0.0) listener could do, since
                        // the alias exists solely for this account: direct.
                    } catch {
                        aliasFailure = String(describing: error)
                    }
                }
            }

            // The badge says what the next connection will meet: the gate's
            // answer first, then the bind's.
            let state: MappingState
            if !owns {
                state = .waiting
            } else if primary != nil {
                state = .forwarding
            } else if let primaryFailure {
                state = .blocked(primaryFailure)
            } else {
                state = .busy
            }
            let aliasState: MappingState?
            if aliasEndpoint == nil {
                aliasState = nil
            } else if !owns {
                aliasState = .waiting
            } else if aliasForwarder != nil {
                aliasState = .forwarding
            } else if let aliasFailure {
                aliasState = .blocked(aliasFailure)
            } else {
                // Owned, and the alias port is held by the account's own
                // wide-bound service: it answers directly.
                aliasState = .forwarding
            }

            if let primary {
                forwarders[mapping.id] = primary
            }
            if let aliasForwarder {
                forwarders[mapping.id + "#alias"] = aliasForwarder
            }
            entries.append(Entry(
                account: mapping.account,
                accountName: space.name,
                port: mapping.port,
                external: mapping.external,
                state: state,
                aliasEndpoint: aliasEndpoint,
                aliasState: aliasState))
        }

        entries.sort { ($0.accountName, $0.port) < ($1.accountName, $1.port) }
        return (forwarders, entries, addresses, retryHelper)
    }

    private func apply(_ outcome: (forwarders: [String: PortForwarder], entries: [Entry],
                                  addresses: [UUID: AddressState], retryHelper: Bool)) {
        for (key, forwarder) in forwarders where outcome.forwarders[key] == nil {
            forwarder.stop()
            log.info("forwarder \(key, privacy: .public) stopped")
        }
        self.forwarders = outcome.forwarders
        if entries != self.entries {
            self.entries = entries
        }
        if outcome.addresses != self.addressStates {
            self.addressStates = outcome.addresses
        }
        if !outcome.retryHelper {
            nextHelperAttempt = Date().addingTimeInterval(20)
        }
        for (account, state) in outcome.addresses {
            if case .failed(let reason) = state {
                log.error("account address for \(account.uuidString, privacy: .public): \(reason, privacy: .public)")
            }
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
