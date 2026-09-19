import Foundation

/// Attaches AgentSpace to an existing standard macOS account.
///
/// This service never creates or deletes a directory-service user. Its machine
/// mutations are limited to the per-account runtime and LaunchAgent installed by
/// the helper, plus the user's explicitly selected workspace.
public struct AccountAttachService {
    public typealias Transport = (HelperRequest) throws -> HelperResponse
    public typealias Readiness = (AgentAccount) -> Bool

    public struct Options {
        public var root: String
        public var registryRoot: String?
        public var workspaceDirectory: String
        public var mainUser: String

        public init(root: String, registryRoot: String? = nil, workspaceDirectory: String, mainUser: String) {
            self.root = root
            self.registryRoot = registryRoot
            self.workspaceDirectory = workspaceDirectory
            self.mainUser = mainUser
        }

        public func worktreePath(accountID: UUID, repository: String) -> String {
            let name = (repository as NSString).lastPathComponent
            return workspaceDirectory + "/" + accountID.uuidString + "/" + (name.isEmpty ? "work" : name)
        }
    }

    public struct Step {
        public enum Outcome: Equatable {
            case done
            case skipped(String)
            case failed(String)
            case rolledBack(String)
            case rollbackFailed(String)
        }

        public var name: String
        public var outcome: Outcome
        public var detail: String

        public var isFailure: Bool {
            if case .failed = outcome { return true }
            if case .rollbackFailed = outcome { return true }
            return false
        }
    }

    public struct Outcome {
        public var account: AgentAccount?
        public var steps: [Step]
        public var error: AgentSpaceError?
        public var ok: Bool { account != nil && error == nil }
    }

    public static func attach(
        account: LocalAccount,
        displayName: String,
        workspace: Workspace,
        sharedFolders: [SharedFolder],
        purpose: AgentPurpose? = nil,
        options: Options,
        transport: @escaping Transport,
        readiness: Readiness? = nil,
        registry: SpaceRegistry = SpaceRegistry()
    ) -> Outcome {
        var steps: [Step] = []
        let accountID = UUID()

        guard account.uid >= 500,
              !account.isAdministrator,
              account.username != options.mainUser,
              account.homeDirectory.hasPrefix("/Users/") else {
            let error = AgentSpaceError(code: .helperRejected, message: "\(account.username) is not an attachable standard macOS account")
            return Outcome(account: nil, steps: [Step(name: "validate account", outcome: .failed(error.message), detail: "")], error: error)
        }
        guard !registry.spaces.contains(where: { $0.username == account.username }) else {
            let error = AgentSpaceError(code: .badRequest, message: "\(account.username) is already attached")
            return Outcome(account: nil, steps: [Step(name: "validate account", outcome: .failed(error.message), detail: "")], error: error)
        }
        if let error = HelperValidation.validateDisplayName(displayName) {
            return Outcome(account: nil, steps: [Step(name: "validate account", outcome: .failed(error.message), detail: "")], error: error)
        }
        steps.append(Step(name: "validate account", outcome: .done, detail: "\(account.username), uid \(account.uid), standard user"))

        let confinedWorkspace: Workspace
        if case .gitWorktree(let repository, let branch, _) = workspace {
            confinedWorkspace = .gitWorktree(
                repository: repository,
                branch: branch,
                path: options.worktreePath(accountID: accountID, repository: repository))
        } else {
            confinedWorkspace = workspace
        }
        let plan: WorkspacePreparer.Plan
        switch WorkspacePreparer.plan(
            workspace: confinedWorkspace,
            sharedFolders: sharedFolders,
            spaceID: accountID,
            workspaceDirectory: options.workspaceDirectory) {
        case .failure(let error):
            steps.append(Step(name: "plan workspace", outcome: .failed(error.message), detail: ""))
            return Outcome(account: nil, steps: steps, error: error)
        case .success(let value):
            plan = value
            steps.append(Step(name: "plan workspace", outcome: .done, detail: value.summary))
        }

        let prepared = call(transport, HelperRequest(
            operation: .prepareRuntimeDirectory,
            spaceID: accountID,
            username: account.username,
            mainUser: options.mainUser,
            runtimeRoot: options.root,
            uid: account.uid))
        guard prepared.ok, let runtimeDirectory = prepared.result?["runtimeDirectory"]?.stringValue else {
            let error = prepared.error ?? AgentSpaceError(code: .helperRejected, message: "the helper did not prepare the runtime")
            steps.append(Step(name: "prepare runtime directory", outcome: .failed(error.message), detail: ""))
            return Outcome(account: nil, steps: steps, error: error)
        }
        steps.append(Step(name: "prepare runtime directory", outcome: .done, detail: runtimeDirectory))

        var record = plan.spaceRecord
        record["spaceName"] = displayName
        record["home"] = account.homeDirectory
        record["mainUser"] = options.mainUser
        record["createdAt"] = ISO8601DateFormatter().string(from: Date())
        do {
            let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: runtimeDirectory + "/space.json"), options: .atomic)
        } catch {
            let failure = AgentSpaceError(code: .internalError, message: "could not write the account runtime record: \(error.localizedDescription)")
            steps.append(Step(name: "write runtime record", outcome: .failed(failure.message), detail: ""))
            rollbackRuntime(accountID: accountID, username: account.username, options: options, transport: transport, steps: &steps)
            return Outcome(account: nil, steps: steps, error: failure)
        }

        if case .failure(let error) = WorkspacePreparer.apply(plan) {
            steps.append(Step(name: "apply workspace", outcome: .failed(error.message), detail: ""))
            rollbackWorkspace(confinedWorkspace, steps: &steps)
            rollbackRuntime(accountID: accountID, username: account.username, options: options, transport: transport, steps: &steps)
            return Outcome(account: nil, steps: steps, error: error)
        }
        steps.append(Step(name: "apply workspace", outcome: .done, detail: plan.summary))

        let installed = call(transport, HelperRequest(
            operation: .installWorker,
            spaceID: accountID,
            username: account.username,
            mainUser: options.mainUser,
            runtimeRoot: options.root,
            uid: account.uid))
        guard installed.ok else {
            let error = installed.error ?? AgentSpaceError(code: .helperRejected, message: "the helper did not install the worker")
            steps.append(Step(name: "install worker", outcome: .failed(error.message), detail: ""))
            rollbackWorker(accountID: accountID, username: account.username, options: options, transport: transport, steps: &steps)
            rollbackWorkspace(confinedWorkspace, steps: &steps)
            rollbackRuntime(accountID: accountID, username: account.username, options: options, transport: transport, steps: &steps)
            return Outcome(account: nil, steps: steps, error: error)
        }
        let installDeferred = installed.result?["deferred"]?.boolValue == true
        if installDeferred {
            let reason = installed.result?["reason"]?.stringValue
            let detail = installed.result?["homeDirectory"]?.stringValue ?? account.homeDirectory
            steps.append(Step(
                name: "install worker",
                outcome: .skipped(reason == "homeDirectoryMissing"
                    ? "waiting for the account's first GUI login"
                    : "waiting for the worker installation to become available"),
                detail: detail))
        } else {
            steps.append(Step(name: "install worker", outcome: .done,
                              detail: installed.result?["label"]?.stringValue ?? "installed"))
        }

        // Start immediately when the account already has an Aqua session. An
        // offline account is still successfully attached; launchd will load the
        // LaunchAgent at its next login. A missing home is the one special case:
        // there is no LaunchAgent yet, so starting it would only manufacture a
        // second, misleading error in the provisioning overlay.
        let started: HelperResponse
        if installDeferred {
            started = HelperResponse(id: accountID.uuidString, result: .obj(["deferred": .bool(true)]))
            steps.append(Step(
                name: "start worker",
                outcome: .skipped("sign in to the account once, then refresh to finish worker setup"),
                detail: ""))
        } else {
            started = call(transport, HelperRequest(
                operation: .startWorker,
                spaceID: accountID,
                username: account.username,
                mainUser: options.mainUser,
                runtimeRoot: options.root,
                uid: account.uid))
            steps.append(Step(
                name: "start worker",
                outcome: started.ok ? .done : .skipped(started.error?.message ?? "the account has no active desktop session"),
                detail: ""))
        }

        var attached = AgentAccount(
            id: accountID,
            name: displayName,
            username: account.username,
            uid: account.uid,
            homeDirectory: account.homeDirectory,
            runtimeRoot: options.root,
            state: installDeferred || !started.ok ? .needsLogin : .offline,
            workspace: confinedWorkspace,
            sharedFolders: sharedFolders,
            purpose: purpose)
        if started.ok && !installDeferred {
            let online = readiness?(attached) ?? waitUntilWorkerReady(attached)
            attached.state = online ? .ready : .offline
            steps.append(Step(
                name: "verify worker",
                outcome: online ? .done : .skipped("the worker is not answering yet; it will start at the account's next login"),
                detail: ""))
        }
        do {
            var updated = registry
            updated.upsert(attached)
            try updated.save(root: options.registryRoot ?? options.root)
            steps.append(Step(name: "save agent", outcome: .done, detail: displayName))
        } catch {
            let failure = AgentSpaceError(code: .internalError, message: "could not save the attached account: \(error)")
            steps.append(Step(name: "save agent", outcome: .failed(failure.message), detail: ""))
            rollbackWorker(accountID: accountID, username: account.username, options: options, transport: transport, steps: &steps)
            rollbackWorkspace(confinedWorkspace, steps: &steps)
            rollbackRuntime(accountID: accountID, username: account.username, options: options, transport: transport, steps: &steps)
            return Outcome(account: nil, steps: steps, error: failure)
        }
        return Outcome(account: attached, steps: steps, error: nil)
    }

    /// Completes an attachment that was created before the macOS account had
    /// its first GUI login. macOS creates `/Users/<username>` lazily, so the
    /// initial attach can persist the runtime and registry record but cannot
    /// write the account's LaunchAgent yet. Calling this after the first login
    /// installs the worker, starts it when the Aqua session is available, and
    /// keeps the account in `needsLogin` when it is still not ready.
    public static func finishPendingSetup(
        account: AgentAccount,
        options: Options,
        transport: @escaping Transport,
        readiness: Readiness? = nil,
        registry: SpaceRegistry = SpaceRegistry()
    ) -> Outcome {
        var steps: [Step] = []
        let installed = call(transport, HelperRequest(
            operation: .installWorker,
            spaceID: account.id,
            username: account.username,
            mainUser: options.mainUser,
            runtimeRoot: options.root,
            uid: account.uid))
        guard installed.ok else {
            let error = installed.error ?? AgentSpaceError(
                code: .helperRejected, message: "the helper did not install the worker")
            steps.append(Step(name: "install worker", outcome: .failed(error.message), detail: ""))
            return Outcome(account: account, steps: steps, error: error)
        }

        if installed.result?["deferred"]?.boolValue == true {
            let reason = installed.result?["reason"]?.stringValue
            let detail = installed.result?["homeDirectory"]?.stringValue ?? account.macOSHomeDirectory
            steps.append(Step(
                name: "install worker",
                outcome: .skipped(reason == "homeDirectoryMissing"
                    ? "the account still needs its first GUI login"
                    : "the worker installation is still waiting"),
                detail: detail))
            var pending = account
            pending.state = .needsLogin
            return saveFinishedAccount(
                pending, steps: steps, options: options, registry: registry)
        }

        steps.append(Step(name: "install worker", outcome: .done,
                          detail: installed.result?["label"]?.stringValue ?? "installed"))
        let started = call(transport, HelperRequest(
            operation: .startWorker,
            spaceID: account.id,
            username: account.username,
            mainUser: options.mainUser,
            runtimeRoot: options.root,
            uid: account.uid))
        steps.append(Step(
            name: "start worker",
            outcome: started.ok ? .done : .skipped(
                started.error?.message ?? "the account has no active desktop session"),
            detail: ""))

        var finished = account
        finished.state = started.ok ? .offline : .needsLogin
        if started.ok {
            let online = readiness?(finished) ?? waitUntilWorkerReady(finished)
            finished.state = online ? .ready : .offline
            steps.append(Step(
                name: "verify worker",
                outcome: online ? .done : .skipped(
                    "the worker is not answering yet; refresh after the account's desktop is ready"),
                detail: ""))
        }
        return saveFinishedAccount(finished, steps: steps, options: options, registry: registry)
    }

    public static func detach(
        account: AgentAccount,
        options: Options,
        transport: @escaping Transport,
        registry: SpaceRegistry = SpaceRegistry()
    ) -> Outcome {
        var steps: [Step] = []
        for operation in [HelperOperation.stopWorker, .removeWorker] {
            let response = call(transport, HelperRequest(
                operation: operation,
                spaceID: account.id,
                username: account.username,
                mainUser: options.mainUser,
                runtimeRoot: options.root,
                uid: account.uid))
            let isRemoval = operation == .removeWorker
            steps.append(Step(
                name: operation == .stopWorker ? "stop worker" : "remove worker",
                outcome: response.ok ? .done : (isRemoval
                    ? .failed(response.error?.message ?? "the worker could not be removed")
                    : .skipped(response.error?.message ?? "already stopped")),
                detail: ""))
            if isRemoval, !response.ok {
                let failure = response.error ?? AgentSpaceError(
                    code: .internalError, message: "the helper did not remove the worker")
                return Outcome(account: account, steps: steps, error: failure)
            }
        }

        if case .gitWorktree(let repository, _, let path) = account.workspace {
            let result = WorkspacePreparer.run(["git", "-C", repository, "worktree", "remove", "--force", path])
            steps.append(Step(name: "remove git worktree", outcome: result.exitCode == 0 ? .done : .skipped(result.output), detail: path))
        }
        let removedRuntime = call(transport, HelperRequest(
            operation: .removeRuntimeDirectory,
            spaceID: account.id,
            username: account.username,
            mainUser: options.mainUser,
            runtimeRoot: options.root,
            uid: account.uid))
        guard removedRuntime.ok else {
            let failure = removedRuntime.error ?? AgentSpaceError(code: .internalError, message: "the helper did not remove the runtime")
            steps.append(Step(name: "remove runtime directory", outcome: .failed(failure.message), detail: ""))
            return Outcome(account: account, steps: steps, error: failure)
        }
        steps.append(Step(name: "remove runtime directory", outcome: .done,
                          detail: RuntimePaths(spaceID: account.id, root: options.root).directory))
        do {
            var updated = registry
            updated.remove(id: account.id)
            try updated.save(root: options.registryRoot ?? options.root)
            steps.append(Step(name: "remove agent record", outcome: .done, detail: account.username))
        } catch {
            let failure = AgentSpaceError(code: .internalError, message: "could not update the attached-account registry: \(error)")
            steps.append(Step(name: "remove agent record", outcome: .failed(failure.message), detail: ""))
            return Outcome(account: nil, steps: steps, error: failure)
        }
        return Outcome(account: nil, steps: steps, error: nil)
    }

    private static func call(_ transport: Transport, _ request: HelperRequest) -> HelperResponse {
        do {
            return try transport(request)
        } catch {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperUnavailable,
                message: "the privileged helper could not be reached: \(error)"))
        }
    }

    private static func saveFinishedAccount(
        _ account: AgentAccount,
        steps: [Step],
        options: Options,
        registry: SpaceRegistry
    ) -> Outcome {
        var steps = steps
        do {
            var updated = registry
            updated.upsert(account)
            try updated.save(root: options.registryRoot ?? options.root)
            steps.append(Step(name: "save agent", outcome: .done, detail: account.name))
            return Outcome(account: account, steps: steps, error: nil)
        } catch {
            let failure = AgentSpaceError(
                code: .internalError,
                message: "could not save the attached-account registry: \(error)")
            steps.append(Step(name: "save agent", outcome: .failed(failure.message), detail: ""))
            return Outcome(account: account, steps: steps, error: failure)
        }
    }

    private static func waitUntilWorkerReady(_ account: AgentAccount) -> Bool {
        let connection = SpaceConnection(space: account)
        for _ in 0..<20 {
            if let response = try? connection.client.call(
                method: Method.status,
                token: connection.token,
                timeout: 0.25), response.error == nil {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private static func rollbackWorker(
        accountID: UUID,
        username: String,
        uid: uid_t? = nil,
        options: Options,
        transport: Transport,
        steps: inout [Step]
    ) {
        let response = call(transport, HelperRequest(
            operation: .removeWorker,
            spaceID: accountID,
            username: username,
            mainUser: options.mainUser,
            runtimeRoot: options.root,
            uid: uid))
        steps.append(Step(
            name: "remove worker",
            outcome: response.ok ? .rolledBack("attach failed") : .rollbackFailed(response.error?.message ?? "helper refused cleanup"),
            detail: ""))
    }

    private static func rollbackRuntime(
        accountID: UUID,
        username: String,
        uid: uid_t? = nil,
        options: Options,
        transport: Transport,
        steps: inout [Step]
    ) {
        let response = call(transport, HelperRequest(
            operation: .removeRuntimeDirectory,
            spaceID: accountID,
            username: username,
            mainUser: options.mainUser,
            runtimeRoot: options.root,
            uid: uid))
        steps.append(Step(
            name: "remove runtime directory",
            outcome: response.ok ? .rolledBack("attach failed") : .rollbackFailed(response.error?.message ?? "helper refused cleanup"),
            detail: RuntimePaths(spaceID: accountID, root: options.root).directory))
    }

    private static func rollbackWorkspace(_ workspace: Workspace, steps: inout [Step]) {
        guard case .gitWorktree(let repository, _, let path) = workspace else { return }
        let result = WorkspacePreparer.run(["/usr/bin/git", "-C", repository, "worktree", "remove", "--force", path])
        steps.append(Step(
            name: "remove git worktree",
            outcome: result.exitCode == 0 ? .rolledBack("attach failed") : .rollbackFailed(result.output),
            detail: path))
    }
}
