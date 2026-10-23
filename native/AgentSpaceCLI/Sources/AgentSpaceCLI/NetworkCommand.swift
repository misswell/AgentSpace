import Foundation
import AgentSpaceCore

/// The `agentspace network …` commands.
///
/// Read-mostly and honest about what it has and has not measured: `status`
/// reports the committed configuration and the last validation, `doctor` says
/// which checks ran and which could not. Nothing here applies a change to a
/// tunnel — that is the app's job, with a preview and a rollback — because a CLI
/// subcommand that silently renumbers a working network is not a convenience.
enum NetworkCommand {

    static func run(
        action: String,
        args: [String],
        parsed: ParsedArgs,
        root: String?,
        emitter: Emitter
    ) -> Never {
        let paths = VirtualNetworkPaths(root: root)
        let store = VirtualNetworkStore(paths: paths)

        switch action {
        case "status", "":
            status(store: store, paths: paths, emitter: emitter)

        case "enable":
            // Enabling is a statement of intent, not an interface change. It
            // writes a default configuration when none exists, so the GUI has
            // something to edit, and says plainly that the tunnel itself is the
            // app's to bring up.
            var config = store.load()
            let created: Bool
            if config == nil {
                let snapshot = LocalNetworkProbe.snapshot()
                let seed = UInt64(Date().timeIntervalSince1970) ^ UInt64.random(in: 0...UInt64.max)
                let pool = VirtualAddressAllocator.choosePool(seed: seed, excluding: snapshot)
                let layout = VirtualAddressAllocator.defaultLayout(pool: pool)
                var candidate = VirtualNetworkConfig(
                    pool: pool, hub: layout.hub, controller: layout.controller, local: layout.local)
                candidate.mode = .automatic
                let validation = VirtualNetworkValidator.validate(candidate, local: snapshot)
                guard validation.isValid else {
                    emitter.failure(AgentSpaceError(
                        code: .badRequest,
                        message: "the automatically chosen pool \(pool) failed validation: "
                            + validation.conflicts.map(\.detail).joined(separator: "; ")))
                }
                config = candidate
                try? store.commit(candidate)
                created = true
            } else {
                created = false
            }
            let validation = VirtualNetworkValidator.validate(
                config!, local: LocalNetworkProbe.snapshot())
            emitter.success(.obj([
                "ok": .bool(true),
                "created": .bool(created),
                "version": .int(config!.version),
                "pool": .string(config!.pool.description),
                "local": .string(config!.local.description),
                "apiPort": .int(config!.apiPort),
                "valid": .bool(validation.isValid),
                "conflicts": .array(validation.conflicts.map(conflictJSON)),
                "note": .string("The configuration is committed. Bringing the tunnel up and starting the API are done by the app (Settings → Virtual Network), which previews the change and can roll it back."),
            ]), human: created
                ? "network enabled: \(config!.pool) — this Mac is \(config!.local), API port \(config!.apiPort)\n  The tunnel and the API are started from the app, which shows a preview and can roll back."
                : "network already configured: \(config!.pool) — this Mac is \(config!.local), API port \(config!.apiPort)")

        case "disable":
            // Disabling removes the committed configuration, which is what stops
            // the app from bringing the tunnel back on next launch. It does not
            // touch interfaces directly: the tunnel is the app's, and the app
            // notices a missing configuration.
            guard store.load() != nil else {
                emitter.success(.obj([
                    "ok": .bool(true), "changed": .bool(false),
                    "note": .string("no virtual-network configuration exists"),
                ]), human: "network is already disabled")
            }
            store.remove()
            emitter.success(.obj([
                "ok": .bool(true), "changed": .bool(true),
                "note": .string("the committed configuration was removed; the app stops the tunnel when it next checks"),
            ]), human: "network disabled (configuration removed)")

        case "configure":
            return configure(args: args, parsed: parsed, store: store, emitter: emitter)

        case "nodes":
            guard let config = store.load() else { return noConfiguration(emitter) }
            let validation = VirtualNetworkValidator.validate(
                config, local: LocalNetworkProbe.snapshot())
            let rows: [JSONValue] = config.allNodes.map { node in
                .obj([
                    "id": .string(node.id),
                    "name": .string(node.name),
                    "role": .string(node.role.rawValue),
                    "address": .string(node.address.description),
                    "publicKey": node.publicKey.map { .string($0) } ?? .null,
                    "endpoint": node.endpoint.map { .string($0) } ?? .null,
                    "lastSeen": node.lastSeen.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
                    "keyRegistered": .bool(node.publicKey != nil),
                ])
            }
            let human = ([
                "network \(config.pool) — version \(config.version)",
            ] + config.allNodes.map { node in
                "  \(node.address.description.padding(toLength: 15, withPad: " ", startingAt: 0)) "
                    + "\(node.role.displayName.padding(toLength: 14, withPad: " ", startingAt: 0)) "
                    + "\(node.name)\(node.publicKey == nil ? "  (no key yet)" : "")"
            }).joined(separator: "\n")
            emitter.success(.obj([
                "ok": .bool(true),
                "version": .int(config.version),
                "pool": .string(config.pool.description),
                "nodes": .array(rows),
                "valid": .bool(validation.isValid),
            ]), human: human)

        case "doctor":
            return doctor(paths: paths, store: store, emitter: emitter)

        case "connect", "disconnect":
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "`network \(action)` is not a CLI operation. The tunnel is a system extension owned by the app: use Settings → Virtual Network → \(action == "connect" ? "Connect" : "Disconnect"), which reports the extension's real state and can roll back."))

        case "revoke":
            guard let id = args.first, !id.isEmpty else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest, message: "usage: agentspace network revoke <node-id>"))
            }
            guard var config = store.load() else { return noConfiguration(emitter) }
            guard let index = config.nodes.firstIndex(where: { $0.id == id || $0.name == id }) else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "no node '\(id)'. Known nodes: \(config.nodes.map(\.name).joined(separator: ", "))"))
            }
            let removed = config.nodes.remove(at: index)
            config.version += 1
            config.updatedAt = Date()
            try? store.commit(config)
            emitter.success(.obj([
                "ok": .bool(true),
                "revoked": .string(removed.name),
                "address": .string(removed.address.description),
                "version": .int(config.version),
            ]), human: "revoked \(removed.name) (\(removed.address)) — version \(config.version)")

        default:
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "unknown network command '\(action)'. Try: status, enable, disable, configure, nodes, doctor, revoke."))
        }
    }

    // MARK: - status

    private static func status(store: VirtualNetworkStore, paths: VirtualNetworkPaths, emitter: Emitter) -> Never {
        guard let config = store.load() else {
            emitter.success(.obj([
                "ok": .bool(true),
                "enabled": .bool(false),
                "note": .string("no virtual-network configuration. `agentspace network enable` chooses a private pool."),
            ]), human: "virtual network: not configured\n  → agentspace network enable")
        }
        let snapshot = LocalNetworkProbe.snapshot()
        let validation = VirtualNetworkValidator.validate(config, local: snapshot)
        let apiRunning = APIConfiguration.load(paths: paths)?.enabled == true

        let payload = JSONValue.obj([
            "ok": .bool(true),
            "enabled": .bool(true),
            "version": .int(config.version),
            "mode": .string(config.mode.rawValue),
            "pool": .string(config.pool.description),
            "hub": .string(config.hub.description),
            "controller": .string(config.controller.description),
            "local": .string(config.local.description),
            "apiPort": .int(config.apiPort),
            "apiEnabled": .bool(apiRunning),
            "apiBaseURL": .string("http://\(config.local.description):\(config.apiPort)"),
            "ipv6Enabled": .bool(config.ipv6Enabled),
            "nodeCount": .int(config.allNodes.count),
            "valid": .bool(validation.isValid),
            "conflicts": .array(validation.conflicts.map(conflictJSON)),
            "localSnapshotComplete": .bool(snapshot.complete),
            "previousVersion": store.loadPrevious().map { .int($0.version) } ?? .null,
            "hostRoutes": .array(config.hostRoutes.map { .string($0.description) }),
        ])

        let human = """
        virtual network: \(config.pool) — version \(config.version) (\(config.mode.displayName))
          this Mac:    \(config.local)   (API port \(config.apiPort), \(apiRunning ? "API enabled" : "API disabled"))
          main system: \(config.controller)
          hub:         \(config.hub)
          nodes:       \(config.allNodes.count)
          conflict:    \(validation.isValid ? "none found" : "\(validation.blocking.count + validation.overrideable.count) to resolve")
        \(validation.conflicts.isEmpty ? "" : validation.conflicts.map { "  ! \($0.detail)\n    → \($0.remediation)" }.joined(separator: "\n"))
        """
        emitter.success(payload, human: human)
    }

    // MARK: - configure

    private static func configure(
        args: [String],
        parsed: ParsedArgs,
        store: VirtualNetworkStore,
        emitter: Emitter
    ) -> Never {
        guard var config = store.load() else {
            return noConfiguration(emitter)
        }
        var changed = false
        var candidate = config
        candidate.version = config.version + 1

        if let poolText = parsed.flag("pool") {
            guard let pool = IPv4Network(poolText) else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest,
                    message: "'\(poolText)' is not a CIDR network (expected e.g. 100.64.0.0/24)"))
            }
            candidate.pool = pool
            changed = true
        }
        if let text = parsed.flag("hub") {
            guard let address = IPv4Address(text) else {
                emitter.failure(AgentSpaceError(code: .badRequest, message: "'\(text)' is not an IPv4 address"))
            }
            candidate.hub = address
            changed = true
        }
        if let text = parsed.flag("controller") {
            guard let address = IPv4Address(text) else {
                emitter.failure(AgentSpaceError(code: .badRequest, message: "'\(text)' is not an IPv4 address"))
            }
            candidate.controller = address
            changed = true
        }
        if let text = parsed.flag("local") {
            guard let address = IPv4Address(text) else {
                emitter.failure(AgentSpaceError(code: .badRequest, message: "'\(text)' is not an IPv4 address"))
            }
            candidate.local = address
            changed = true
        }
        if let portText = parsed.flag("port"), let port = Int(portText) {
            candidate.apiPort = port
            changed = true
        }
        if parsed.bool("allow-non-private-pool") {
            candidate.allowNonPrivatePool = true
            changed = true
        }
        if parsed.bool("allow-overlap") {
            candidate.allowOverlap = true
            changed = true
        }
        if let mode = parsed.flag("mode") {
            guard let parsedMode = VirtualAddressMode(rawValue: mode) else {
                emitter.failure(AgentSpaceError(
                    code: .badRequest, message: "mode must be automatic or manual"))
            }
            candidate.mode = parsedMode
            changed = true
        }

        guard changed else {
            emitter.failure(AgentSpaceError(
                code: .badRequest,
                message: "nothing to change. Pass --pool CIDR, --local IP, --controller IP, --hub IP, --port N, --mode automatic|manual, --allow-overlap or --allow-non-private-pool."))
        }

        let snapshot = LocalNetworkProbe.snapshot()
        let validation = VirtualNetworkValidator.validate(candidate, local: snapshot)
        guard validation.isValid else {
            emitter.failure(AgentSpaceError(
                code: .networkConfigRejected,
                message: "the proposed configuration is refused: "
                    + validation.conflicts
                        .filter { $0.severity != .warning }
                        .map { "\($0.detail) → \($0.remediation)" }
                        .joined(separator: " | ")))
        }

        candidate.updatedAt = Date()
        let plan = NetworkMigrationPlan.plan(from: config, to: candidate, offlineNodes: [])
        try? store.saveCandidate(candidate)

        emitter.success(.obj([
            "ok": .bool(true),
            "applied": .bool(true),
            "version": .int(candidate.version),
            "pool": .string(candidate.pool.description),
            "local": .string(candidate.local.description),
            "migration": migrationJSON(plan),
            "note": .string("The configuration is committed and the previous one is kept for rollback. The tunnel takes the new addresses when the app next applies it."),
        ]), human: """
        configured version \(candidate.version): \(candidate.pool), this Mac \(candidate.local)
          changes: \(plan.addressChanges.map { "\($0.node) \($0.from) → \($0.to)" }.joined(separator: ", "))
          previous version kept for rollback
        """)
    }

    // MARK: - doctor

    private static func doctor(paths: VirtualNetworkPaths, store: VirtualNetworkStore, emitter: Emitter) -> Never {
        struct Check {
            let name: String
            let status: String
            let detail: String
        }
        var checks: [Check] = []

        let snapshot = LocalNetworkProbe.snapshot()
        checks.append(Check(
            name: "local-network snapshot",
            status: snapshot.complete ? "ok" : "fail",
            detail: snapshot.complete
                ? "\(snapshot.addresses.count) address(es), \(snapshot.routes.count) route(s) read"
                : "interfaces or routes could not be read, so overlap detection cannot run"))

        if let config = store.load() {
            let validation = VirtualNetworkValidator.validate(config, local: snapshot)
            checks.append(Check(
                name: "configuration",
                status: validation.isValid ? "ok" : "fail",
                detail: "version \(config.version), \(config.pool)\(validation.isValid ? "" : " — \(validation.conflicts.map(\.detail).joined(separator: "; "))")"))
            let onLink = snapshot.addresses.contains(config.local)
            checks.append(Check(
                name: "virtual address present",
                status: onLink ? "ok" : "warn",
                detail: onLink
                    ? "\(config.local) is assigned to an interface"
                    : "\(config.local) is not assigned yet; the tunnel is down or the extension is not activated"))
            let tokenList = APITokenStore.load(paths: paths)
            let active = tokenList.tokens.filter(\.isActive).count
            checks.append(Check(
                name: "API tokens",
                status: active > 0 ? "ok" : "warn",
                detail: active > 0
                    ? "\(active) active token(s)"
                    : "no active API token; the API refuses every remote request until one is created"))
        } else {
            checks.append(Check(name: "configuration", status: "fail",
                                detail: "none; run `agentspace network enable`"))
        }

        let extensionState = SystemExtensionProbe.installedState()
        checks.append(Check(
            name: "system extension",
            status: extensionState.isUsable ? "ok" : "warn",
            detail: extensionState.detail))

        let payload = JSONValue.obj([
            "ok": .bool(checks.allSatisfy { $0.status != "fail" }),
            "checks": .array(checks.map {
                .obj(["check": .string($0.name), "status": .string($0.status), "detail": .string($0.detail)])
            }),
        ])
        let human = checks.map { "  [\($0.status)] \($0.name): \($0.detail)" }.joined(separator: "\n")
        emitter.success(payload, human: "network doctor:\n\(human)",
                        exitCode: checks.contains { $0.status == "fail" } ? 1 : 0)
    }

    // MARK: Helpers

    private static func noConfiguration(_ emitter: Emitter) -> Never {
        emitter.failure(AgentSpaceError(
            code: .badRequest,
            message: "no virtual-network configuration yet. Run `agentspace network enable` first."))
    }

    private static func conflictJSON(_ conflict: NetworkConflict) -> JSONValue {
        .obj([
            "kind": .string(conflict.kind.rawValue),
            "severity": .string(conflict.severity.rawValue),
            "detail": .string(conflict.detail),
            "remediation": .string(conflict.remediation),
        ])
    }

    private static func migrationJSON(_ plan: NetworkMigrationPlan) -> JSONValue {
        .obj([
            "fromVersion": .int(plan.fromVersion),
            "toVersion": .int(plan.toVersion),
            "oldPool": .string(plan.oldPool.description),
            "newPool": .string(plan.newPool.description),
            "addressChanges": .array(plan.addressChanges.map {
                .obj(["node": .string($0.node), "from": .string($0.from.description), "to": .string($0.to.description)])
            }),
            "offlineNodes": .array(plan.offlineNodes.map { .string($0) }),
            "steps": .array(plan.steps.map { .string($0.rawValue) }),
        ])
    }
}
