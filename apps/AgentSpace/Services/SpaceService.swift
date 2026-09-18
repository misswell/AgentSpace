import Foundation
import AgentSpaceCore

/// Everything the GUI knows about one Space right now.
///
/// Kept separate from `AgentSpace` (the persisted record) because the record is
/// what the registry stores and this is what the worker last said. Conflating
/// them is how a GUI ends up showing a stale `ready` for a Space whose worker
/// died ten minutes ago.
struct SpaceSnapshot: Identifiable, Equatable {
    var space: AgentSpace
    var workerOnline: Bool = false
    var workerPID: Int?
    var sessionVerdict: String?
    var acceptsInput: Bool = false
    var screenRecording: Bool = false
    var accessibility: Bool = false
    var display: DisplayGeometry?
    var resources: ResourceUsage?
    /// Set when the last refresh failed, so the detail view can explain why
    /// rather than just looking empty.
    var problem: AgentSpaceError?
    var lastRefreshed: Date?

    var id: UUID { space.id }

    /// The state to *show*, which is not always the state that was stored. A
    /// Space recorded as ready whose worker is gone is offline, and saying so is
    /// the difference between "nothing is happening" and "nothing can happen".
    var effectiveState: SpaceState {
        if let problem, problem.code == .accessibilityDenied || problem.code == .screenRecordingDenied {
            return .needsPermission
        }
        if !workerOnline && (space.state == .ready || space.state == .running) {
            return .offline
        }
        if sessionVerdict == "isConsole" { return .console }
        return space.state
    }

    var isRefusalExpected: Bool {
        effectiveState == .console || effectiveState == .needsPermission || effectiveState == .offline
    }
}

/// The GUI's bridge to the core, and the only place the app touches the worker.
///
/// Two rules are visible in this file on purpose:
///
/// 1. Every call goes through `WorkerClient` — the same transport the CLI and the
///    MCP server use (plan §49). There is no GUI-only path to the worker, so the
///    GUI cannot acquire behaviour the other front ends lack.
/// 2. Nothing here retries, substitutes or invents a result. A failure comes back
///    as a failure and is displayed with its `fix` text.
final class SpaceService {
    private let root: String?
    private let queue = DispatchQueue(label: "com.agentspace.app.service", qos: .userInitiated)

    init(root: String? = AgentSpaceEnvironment.rootOverride) {
        self.root = root
    }

    func loadRegistry() -> SpaceRegistry {
        SpaceRegistry.load(root: root)
    }

    func save(_ registry: SpaceRegistry) throws {
        try registry.save(root: root)
    }

    func paths(for space: AgentSpace) -> RuntimePaths {
        AgentSpaceEnvironment.paths(spaceID: space.id)
    }

    /// Full status for one Space: worker liveness, session verdict, permissions,
    /// geometry and (on request) resources.
    func snapshot(for space: AgentSpace, includeResources: Bool = false, timeout: Double = 4) -> SpaceSnapshot {
        var snapshot = SpaceSnapshot(space: space)
        let connection = SpaceConnection(space: space)
        guard connection.paths.socketPathFits else {
            snapshot.problem = AgentSpaceError(
                code: .internalError,
                message: "the runtime path for '\(space.name)' is \(connection.paths.socketPath.utf8.count) bytes, over the \(RuntimePaths.maxSocketPathBytes)-byte unix socket limit")
            return snapshot
        }

        let params: JSONValue = includeResources
            ? .object(["resources": .string("full")])
            : .object([:])

        let response: RPCResponse
        do {
            response = try connection.client.call(method: Method.status, params: params, token: connection.token)
        } catch {
            snapshot.problem = AgentSpaceError(
                code: .workerOffline,
                message: "no worker is answering for '\(space.name)': \(error)")
            return snapshot
        }

        if let error = response.error {
            snapshot.problem = error
            // A refusal still means the worker is alive and talking, which is
            // worth recording: the Space is not offline, it is declining.
            snapshot.workerOnline = error.code != .workerOffline
            return snapshot
        }
        if let result = response.result {
            snapshot.workerOnline = true
            snapshot.workerPID = result["workerPid"]?.intValue
            snapshot.sessionVerdict = result["session"]?["verdict"]?.stringValue
            snapshot.acceptsInput = result["acceptsInput"]?.boolValue ?? false
            snapshot.screenRecording = result["screenRecording"]?.boolValue ?? false
            snapshot.accessibility = result["accessibility"]?.boolValue ?? false
            if let display = result["display"] {
                snapshot.display = DisplayGeometry(
                    width: display["width"]?.intValue ?? 0,
                    height: display["height"]?.intValue ?? 0,
                    pixelWidth: display["pixelWidth"]?.intValue ?? 0,
                    pixelHeight: display["pixelHeight"]?.intValue ?? 0,
                    scale: display["scale"]?.intValue ?? 1)
            }
            if let resources = result["resources"] {
                snapshot.resources = ResourceUsage(
                    cpuPercent: resources["cpuPercent"]?.doubleValue ?? 0,
                    memoryBytes: UInt64(resources["memoryBytes"]?.intValue ?? 0),
                    processCount: resources["processCount"]?.intValue ?? 0,
                    diskBytes: UInt64(resources["diskBytes"]?.intValue ?? 0))
            }
            snapshot.lastRefreshed = Date()
        }
        return snapshot
    }

    /// A screenshot of the Space's own desktop.
    ///
    /// Returns the worker's typed error untouched on failure. In particular this
    /// never falls back to capturing *this* session's screen, which would hand the
    /// user a picture of their own desktop and call it the agent's.
    func screenshot(for space: AgentSpace, maxWidth: Int?, inline: Bool) -> Result<ScreenshotResult, AgentSpaceError> {
        let connection = SpaceConnection(space: space)
        var params: [String: JSONValue] = [:]
        if let maxWidth { params["maxWidth"] = .int(maxWidth) }
        if inline { params["inline"] = .bool(true) }

        do {
            let response = try connection.client.call(
                method: Method.screenshot, params: .object(params), token: connection.token)
            if let error = response.error { return .failure(error) }
            guard let result = response.result else {
                return .failure(AgentSpaceError(
                    code: .internalError, message: "the worker answered with neither a result nor an error"))
            }
            guard let path = result["path"]?.stringValue else {
                return .failure(AgentSpaceError(
                    code: .internalError,
                    message: "the worker answered a screenshot request with no path"))
            }
            return .success(ScreenshotResult(
                path: path,
                width: result["width"]?.intValue ?? 0,
                height: result["height"]?.intValue ?? 0,
                pixelWidth: result["pixelWidth"]?.intValue ?? 0,
                pixelHeight: result["pixelHeight"]?.intValue ?? 0,
                scale: result["scale"]?.intValue ?? 1,
                base64: result["pngBase64"]?.stringValue))
        } catch {
            return .failure(AgentSpaceError(
                code: .workerOffline,
                message: "no worker is answering for '\(space.name)': \(error)"))
        }
    }

    /// Send a batch of input actions. `nil` means it was delivered.
    ///
    /// Deliberately takes a batch rather than one action: the plan's §14 wants
    /// agents to amortise the round trip, and the viewer uses the same entry point
    /// so it cannot drift from what an agent does.
    func input(for space: AgentSpace, actions: [InputAction], timeout: Double = 10) -> AgentSpaceError? {
        guard !actions.isEmpty else { return nil }
        let connection = SpaceConnection(space: space)
        let encoded = actions.map { $0.wireValue }

        do {
            let response = try connection.client.call(
                method: Method.input,
                params: .object(["actions": .array(encoded)]),
                token: connection.token,
                timeout: timeout)
            return response.error
        } catch {
            return AgentSpaceError(
                code: .workerOffline,
                message: "no worker is answering for '\(space.name)': \(error)")
        }
    }

    /// The apps running inside the Space.
    func apps(for space: AgentSpace) -> Result<[AppEntry], AgentSpaceError> {
        let connection = SpaceConnection(space: space)
        do {
            let response = try connection.client.call(method: Method.apps, token: connection.token)
            if let error = response.error { return .failure(error) }
            let result = response.result ?? .object([:])
            let entries = (result["apps"]?.arrayValue ?? []).compactMap { item -> AppEntry? in
                guard let pid = item["pid"]?.intValue else { return nil }
                return AppEntry(
                    pid: pid,
                    name: item["name"]?.stringValue ?? "pid \(pid)",
                    bundleID: item["bundleId"]?.stringValue,
                    policy: item["policy"]?.stringValue ?? "regular",
                    active: item["active"]?.boolValue ?? false)
            }
            return .success(entries)
        } catch {
            return .failure(AgentSpaceError(
                code: .workerOffline,
                message: "no worker is answering for '\(space.name)': \(error)"))
        }
    }
}

struct ScreenshotResult: Equatable {
    var path: String
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var scale: Int
    var base64: String?
}

struct AppEntry: Identifiable, Equatable {
    var pid: Int
    var name: String
    var bundleID: String?
    var policy: String
    var active: Bool
    var id: Int { pid }

    var isAccessory: Bool { policy == "accessory" }
}

// MARK: - JSONValue convenience

extension JSONValue {
    /// Core exposes `stringValue`/`intValue`/… publicly; the only thing missing
    /// for reading status fields is dictionary lookup.
    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }
}
