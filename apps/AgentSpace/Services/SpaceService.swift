import AppKit
import Foundation
import AgentSpaceCore

/// Everything the GUI knows about one Space right now.
///
/// Kept separate from `AgentSpace` (the persisted record) because the record is
/// what the registry stores and this is what the worker last said. Conflating
/// them is how a GUI ends up showing a stale `ready` for a Space whose worker
/// died ten minutes ago.
struct SpaceSnapshot: Identifiable, Equatable {
    var space: AgentAccount
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
    ///
    /// The derivation itself lives in `SpaceState.effective` so the GUI, the CLI
    /// and the tests cannot disagree. The session lookup runs only on the
    /// offline path — the one case where it changes the answer — so a healthy
    /// refresh pays for none of it (§53: idle ≈ 0% CPU).
    var effectiveState: SpaceState {
        SpaceState.effective(
            stored: space.state,
            workerOnline: workerOnline,
            sessionVerdict: sessionVerdict,
            permissionProblem: problem?.code,
            hasGraphicalSession: workerOnline
                ? nil
                : SystemSessions.hasLiveProcesses(uid: space.uid))
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
    /// Where the registry, runtime and worktrees live. Exposed so the create and
    /// delete flows use the same resolved root as everything else, rather than a
    /// second lookup that could disagree.
    let root: String?
    private let queue = DispatchQueue(label: BundleIdentifiers.app + ".service", qos: .userInitiated)

    init(root: String? = AgentSpaceEnvironment.rootOverride) {
        self.root = root
    }

    func loadRegistry() -> SpaceRegistry {
        SpaceRegistry.load(root: root)
    }

    func save(_ registry: SpaceRegistry) throws {
        try registry.save(root: root)
    }

    func paths(for space: AgentAccount) -> RuntimePaths {
        AgentSpaceEnvironment.paths(spaceID: space.id)
    }

    /// Full status for one Space: worker liveness, session verdict, permissions,
    /// geometry and (on request) resources.
    /// Measure just the Space's home directory, on request.
    ///
    /// Separate from `snapshot` because it walks every file in the home and can
    /// take hundreds of milliseconds — the ordinary 2–5 s status poll must not pay
    /// for it (§53). The disk figure is the only thing this returns.
    func measureDisk(for space: AgentAccount, timeout: Double = 30) -> Result<ResourceUsage, AgentSpaceError> {
        let connection = SpaceConnection(space: space)
        guard connection.paths.socketPathFits else {
            return .failure(AgentSpaceError(
                code: .internalError,
                message: "the runtime path for '\(space.name)' is \(connection.paths.socketPath.utf8.count) bytes, over the \(RuntimePaths.maxSocketPathBytes)-byte unix socket limit"))
        }
        let response: RPCResponse
        do {
            response = try connection.client.call(
                method: Method.status,
                params: .object(["resources": .string("disk")]),
                token: connection.token)
        } catch {
            return .failure(AgentSpaceError(
                code: .workerOffline,
                message: "no worker is answering for '\(space.name)': \(error)",
                recoverable: true))
        }
        if let error = response.error { return .failure(error) }
        guard let resources = response.result?["resources"] else {
            return .success(ResourceUsage())
        }
        return .success(ResourceUsage(
            cpuPercent: resources["cpuPercent"]?.doubleValue ?? 0,
            memoryBytes: UInt64(resources["memoryBytes"]?.intValue ?? 0),
            processCount: resources["processCount"]?.intValue ?? 0,
            diskBytes: UInt64(resources["diskBytes"]?.intValue ?? 0),
            diskMeasured: resources["diskBytes"]?.intValue != nil,
            diskTruncated: resources["diskTruncated"]?.boolValue ?? false))
    }

    func snapshot(for space: AgentAccount, includeResources: Bool = false, timeout: Double = 4) -> SpaceSnapshot {
        var snapshot = SpaceSnapshot(space: space)
        let connection = SpaceConnection(space: space)
        guard connection.paths.socketPathFits else {
            snapshot.problem = AgentSpaceError(
                code: .internalError,
                message: "the runtime path for '\(space.name)' is \(connection.paths.socketPath.utf8.count) bytes, over the \(RuntimePaths.maxSocketPathBytes)-byte unix socket limit")
            return snapshot
        }

        let params: JSONValue = includeResources
            // "full" is CPU, memory and process count. Disk is a separate request
            // ("disk") because it walks the whole home; see `measureDisk`.
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
                    // `diskBytes` is absent or null unless the caller asked for
                    // "disk"; a null must not read as a measured zero.
                    diskBytes: UInt64(resources["diskBytes"]?.intValue ?? 0),
                    diskMeasured: resources["diskBytes"]?.intValue != nil,
                    diskTruncated: resources["diskTruncated"]?.boolValue ?? false)
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
    // MARK: - Stop / Logout (§40)

    /// **Stop Agent** — stop the worker, keep the GUI session. The worker
    /// exits 0, and the LaunchAgent's `KeepAlive.SuccessfulExit = false` means
    /// launchd leaves a clean exit stopped: this is a real stop, not a
    /// crash-restart loop. The session (WindowServer, frames) stays up, so the
    /// next start is instant.
    func stopWorker(for space: AgentAccount) -> Result<Bool, AgentSpaceError> {
        let connection = SpaceConnection(space: space)
        do {
            let response = try connection.client.call(
                method: Method.shutdown,
                params: .obj(["reason": .string("stop-agent")]),
                token: connection.token,
                timeout: 5)
            if let error = response.error { return .failure(error) }
            return .success(true)
        } catch {
            // A worker that is already gone is not a failed stop.
            return .success(true)
        }
    }

    /// **Logout Desktop** — end the Space's whole GUI session, keeping the
    /// account and home. This is root-only (`launchctl bootout gui/<uid>`), so
    /// it goes through the privileged helper as a typed RPC and fails typed
    /// when the helper is not installed — never by trying to `sudo` anything.
    func logoutDesktop(for space: AgentAccount) -> Result<Bool, AgentSpaceError> {
        do {
            let response = try HelperClient.call(
                HelperRequest(operation: .logoutSession, username: space.username, uid: space.uid))
            if let error = response.error { return .failure(error) }
            return .success(true)
        } catch {
            return .failure(AgentSpaceError(
                code: .helperUnavailable,
                message: "could not reach the privileged helper: \(error)"))
        }
    }

    // MARK: - Live preview (§52)

    /// Open the Space's live capture stream. Typed error untouched on failure —
    /// in particular a console-session Space refuses, and this view falls back
    /// to the screenshot MVP rather than trying anything local.
    func previewStart(for space: AgentAccount, maxFPS: Int = 5) -> Result<Int, AgentSpaceError> {
        let connection = SpaceConnection(space: space)
        do {
            let response = try connection.client.call(
                method: Method.previewStart, params: .obj(["maxFPS": .int(maxFPS)]), token: connection.token)
            if let error = response.error { return .failure(error) }
            return .success(response.result?["fps"]?.intValue ?? maxFPS)
        } catch {
            return .failure(AgentSpaceError(code: .workerOffline, message: "\(error)"))
        }
    }

    /// Pull the newest frame as an image, ready for the viewer.
    func previewFrame(for space: AgentAccount) -> Result<NSImage, AgentSpaceError> {
        let connection = SpaceConnection(space: space)
        do {
            let response = try connection.client.call(
                method: Method.previewFrame, params: .obj([:]), token: connection.token)
            if let error = response.error { return .failure(error) }
            guard let base64 = response.result?["inline"]?.stringValue,
                  let data = Data(base64Encoded: base64),
                  let image = NSImage(data: data) else {
                return .failure(AgentSpaceError(
                    code: .internalError,
                    message: "the worker answered a preview request with no decodable frame"))
            }
            return .success(image)
        } catch {
            return .failure(AgentSpaceError(code: .workerOffline, message: "\(error)"))
        }
    }

    /// Close the stream. Safe to call when it never started: the worker's stop
    /// is idempotent by contract.
    func previewStop(for space: AgentAccount) -> Result<Bool, AgentSpaceError> {
        let connection = SpaceConnection(space: space)
        do {
            let response = try connection.client.call(
                method: Method.previewStop, params: .obj([:]), token: connection.token)
            if let error = response.error { return .failure(error) }
            return .success(true)
        } catch {
            return .failure(AgentSpaceError(code: .workerOffline, message: "\(error)"))
        }
    }

    func screenshot(for space: AgentAccount, maxWidth: Int?, inline: Bool) -> Result<ScreenshotResult, AgentSpaceError> {
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
    func input(for space: AgentAccount, actions: [InputAction], timeout: Double = 10) -> AgentSpaceError? {
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

    // MARK: - App control (plan(v2) §10 groundwork)
    //
    // Thin wrappers over wire methods the CLI and MCP already speak. The
    // runtime manager will build on these; nothing here decides policy.

    /// Launch an app inside the agent's desktop session.
    func launch(_ space: AgentAccount, app: String, timeout: Double = 30) -> AgentSpaceError? {
        call(space, AgentSpaceCore.Method.launch, ["app": .string(app)], timeout: timeout)
    }

    /// Bring an already-running app to the front of the agent's desktop.
    func activate(_ space: AgentAccount, app: String, timeout: Double = 10) -> AgentSpaceError? {
        call(space, AgentSpaceCore.Method.activate, ["app": .string(app)], timeout: timeout)
    }

    /// Ask an app in the agent's desktop to quit.
    func quit(_ space: AgentAccount, app: String, force: Bool = false, timeout: Double = 10) -> AgentSpaceError? {
        call(space, force ? AgentSpaceCore.Method.forceQuit : AgentSpaceCore.Method.quit, ["app": .string(app)], timeout: timeout)
    }

    private func call(_ space: AgentAccount, _ method: String, _ params: JSONValue, timeout: Double) -> AgentSpaceError? {
        let connection = SpaceConnection(space: space)
        do {
            let response = try connection.client.call(
                method: method, params: params, token: connection.token, timeout: timeout)
            return response.error
        } catch {
            return AgentSpaceError(
                code: .workerOffline,
                message: "no worker is answering for '\(space.name)': \(error)")
        }
    }

    /// The apps running inside the Space.
    func apps(for space: AgentAccount) -> Result<[AppEntry], AgentSpaceError> {
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
