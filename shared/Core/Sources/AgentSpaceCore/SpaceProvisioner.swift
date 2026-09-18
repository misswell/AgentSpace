import Foundation

/// Creating and deleting a Space — plan §28, §41, and the whole of phase 10.
///
/// This is the only place in AgentSpace that changes the machine: it makes a macOS
/// account, installs a launchd job into it, and later removes them. It is therefore
/// written as a **sequence of steps with a recorded outcome for each**, so that a
/// failure half way through can be undone rather than left as a broken Space that
/// the user cannot fix and cannot remove.
///
/// ## Why the helper call is injected
///
/// The helper needs root, and this machine has no root. If `SpaceProvisioner`
/// called `HelperClient` directly, none of this file could ever be tested, and the
/// rollback logic — which is the part that only runs on failure, and therefore the
/// part least likely to be exercised by hand — would ship unverified.
///
/// So the transport is a closure. Production passes `HelperClient.call`; tests pass
/// a scripted double that can fail at any step, and the rollback is tested for real.
public struct SpaceProvisioner {

    /// Anything that can answer a `HelperRequest`.
    public typealias Transport = (HelperRequest) throws -> HelperResponse

    public struct Options {
        public var root: String
        /// The *parent* directory for a git worktree. The Space's own id is added
        /// below it, so two Spaces can never be given the same checkout.
        ///
        /// Plan §24 puts the space-id in the path and this is why. A path derived
        /// from the Space's *name* collides the moment two Spaces are named `Test`
        /// and `test` — on a case-insensitive filesystem those are one directory,
        /// and two agents would be editing the same working tree, which is the
        /// exact thing the worktree exists to prevent. A name is also not stable:
        /// renaming a Space would move the agent's checkout out from under it.
        public var workspaceDirectory: String
        public var mainUser: String

        public init(root: String, workspaceDirectory: String, mainUser: String) {
            self.root = root
            self.workspaceDirectory = workspaceDirectory
            self.mainUser = mainUser
        }

        /// The worktree path for one Space: `<parent>/<space-id>/<repo name>`.
        public func worktreePath(spaceID: UUID, repository: String) -> String {
            let repoName = (repository as NSString).lastPathComponent
            let safe = repoName.isEmpty ? "work" : repoName
            return workspaceDirectory + "/" + spaceID.uuidString + "/" + safe
        }
    }

    /// One step, and what happened to it.
    public struct Step {
        public enum Outcome: Equatable {
            case done
            case skipped(String)
            case failed(String)
            /// Succeeded, then undone because a later step failed.
            case rolledBack(String)
            /// Failed to undo. The Space is in a state the user must be told about.
            case rollbackFailed(String)
        }

        public var name: String
        public var outcome: Outcome
        public var detail: String

        public var isFailure: Bool {
            switch outcome {
            case .failed, .rollbackFailed: return true
            default: return false
            }
        }
    }

    public struct Outcome {
        public var space: AgentSpace?
        public var steps: [Step]
        public var error: AgentSpaceError?

        public var ok: Bool { error == nil && space != nil }
        /// A run that changed the machine and then failed. Distinguished from a
        /// clean failure because it is the case that needs the user's attention.
        public var leftPartialState: Bool {
            steps.contains { step in
                if case .rollbackFailed = step.outcome { return true }
                return false
            }
        }
    }

    // MARK: - Create

    /// Create a Space: account, runtime, worker, Keychain, registry.
    ///
    /// The order is deliberate and each step exists because of what happens when it
    /// is missing or moved:
    ///
    /// 1. **account** first, because everything else needs its uid.
    /// 2. **runtime directory** before the worker, because the LaunchAgent's log
    ///    paths point into it and launchd refuses to spawn a job whose log file it
    ///    cannot open — producing a worker that never starts with no error anyone
    ///    can see.
    /// 3. **worker** last, because it starts immediately (`RunAtLoad`) and would
    ///    otherwise begin running before its runtime directory exists.
    /// 4. **Keychain** before the registry, so a saved Space always has a password
    ///    to show. The reverse order can produce a Space the user cannot log into.
    public static func create(
        name: String,
        workspace: Workspace,
        sharedFolders: [SharedFolder],
        options: Options,
        transport: @escaping Transport,
        registry: SpaceRegistry = SpaceRegistry(),
        keychain: KeychainStore = KeychainStore(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isGitRepository: (String) -> Bool = { WorkspacePreparer.isGitRepository(at: $0) }
    ) -> Outcome {

        var steps: [Step] = []
        var cleanup: [() -> Step] = []
        let spaceID = UUID()

        func bail(_ error: AgentSpaceError) -> Outcome {
            let code = error.code
            let message = error.message
            // Undo in reverse, so a step is only undone after the things that
            // depended on it have already gone.
            for undo in cleanup.reversed() {
                steps.append(undo())
            }
            let partial = steps.contains { step in
                if case .rollbackFailed = step.outcome { return true }
                return false
            }
            if partial {
                // The Space record is written even on a failed cleanup, because an
                // account that exists and is not in the registry is invisible to
                // the app — the user would have an `_agentspace_…` user they cannot
                // see or remove. `state: .error` makes it visible and deletable.
                //
                // The username is recovered from the step list rather than tracked
                // separately, because the step is the record of what actually
                // happened on the machine and a second copy could disagree with it.
                let created = steps.first { $0.name == "create account" }
                var broken = AgentSpace(
                    id: spaceID, name: name, username: usernameFrom(steps) ?? "",
                    uid: 0, state: .error, createdAt: Date(),
                    workspace: workspace, sharedFolders: sharedFolders)
                _ = created
                var updated = registry
                updated.upsert(broken)
                try? updated.save(root: options.root)
            }
            return Outcome(space: nil, steps: steps, error: error)
        }

        // 0. Validate what can be validated before touching the machine. Doing this
        //    first means a typo in a repository path cannot leave half a Space.
        //
        //    A git worktree's path is rewritten here, where the Space's id exists,
        //    so it is unique by construction rather than by luck. Everything else
        //    the caller asked for is passed through unchanged.
        let workspace = Self.confined(workspace, spaceID: spaceID, options: options)
        switch WorkspacePreparer.plan(
            workspace: workspace, sharedFolders: sharedFolders, spaceID: spaceID,
            workspaceDirectory: options.workspaceDirectory,
            fileExists: fileExists, isGitRepository: isGitRepository) {
        case .failure(let error):
            return bail(error)
        case .success(let plan):
            steps.append(Step(name: "plan workspace", outcome: .done, detail: plan.summary))

            // 1. The account.
            let username = HelperValidation.generateAccountName()
            let password = SpacePassword()
            let created = call(transport, HelperRequest(
                operation: .createUser, username: username,
                displayName: name, password: password.value))
            guard created.ok else {
                // The helper's own code is preserved: an unreachable helper is
                // HELPER_UNAVAILABLE ("install it"), a refusal is HELPER_REJECTED
                // ("it said no"). Those need different fixes.
                return bail(created.error ?? AgentSpaceError(
                    code: .helperRejected, message: "the helper did not create the account"))
            }
            let uid = created.result?["uid"]?.intValue ?? 0
            steps.append(Step(name: "create account", outcome: .done, detail: "\(username), uid \(uid), standard user"))

            cleanup.append {
                let response = call(transport, HelperRequest(
                    operation: .deleteUser, username: username, removeHome: true))
                return response.ok
                    ? Step(name: "undo create account", outcome: .rolledBack("removed \(username)"), detail: "")
                    : Step(name: "undo create account", outcome: .rollbackFailed(response.error?.message ?? "unknown"),
                           detail: "the account \(username) still exists. `agentspace doctor` will show it as an orphan Space you can delete.")
            }

            // 2. The runtime directory, with its ACLs.
            let prepared = call(transport, HelperRequest(
                operation: .prepareRuntimeDirectory, spaceID: spaceID, username: username,
                mainUser: options.mainUser, runtimeRoot: options.root))
            guard prepared.ok, let runtimeDirectory = prepared.result?["runtimeDirectory"]?.stringValue else {
                return bail(prepared.error ?? AgentSpaceError(
                    code: .helperRejected, message: "the helper did not prepare the runtime directory"))
            }
            steps.append(Step(name: "prepare runtime directory", outcome: .done, detail: runtimeDirectory))

            // 2b. The workspace record the worker reads at startup. Written here,
            //     where it can be attributed to this Space's creation, rather than
            //     lazily by the worker — a worker that starts without it reports
            //     `confined: false`, which is honest but not what the user chose.
            let recordURL = URL(fileURLWithPath: runtimeDirectory).appendingPathComponent("space.json")
            var record = plan.spaceRecord
            record["spaceName"] = name
            // The helper's own answer for where this account's home is. The worker
            // reads it back for disk measurement; recording it here rather than
            // letting the worker guess keeps one source of truth.
            if let home = created.result?["home"]?.stringValue, !home.isEmpty {
                record["home"] = home
            }
            record["mainUser"] = options.mainUser
            record["createdAt"] = ISO8601DateFormatter().string(from: Date())
            if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
                if (try? data.write(to: recordURL)) == nil {
                    // Not fatal: the worker's confinement is a guardrail, and a
                    // missing record makes it report `confined: false` rather than
                    // silently pretending. Reported, not hidden.
                    steps.append(Step(name: "write workspace record", outcome: .skipped(
                        "could not write \(recordURL.path); the worker will report confined: false"),
                        detail: ""))
                } else {
                    steps.append(Step(name: "write workspace record",
                                      outcome: .done,
                                      detail: "\(plan.allowedRoots.count) allowed, \(plan.writableRoots.count) writable"))
                }
            }

            // 2c. The workspace itself — the git worktree, if there is one.
            switch WorkspacePreparer.apply(plan) {
            case .failure(let error):
                return bail(error)
            case .success:
                if plan.gitCommand != nil {
                    steps.append(Step(name: "create git worktree", outcome: .done, detail: plan.summary))
                } else {
                    steps.append(Step(name: "create workspace directories", outcome: .done, detail: plan.directories.joined(separator: ", ")))
                }
            }

            // 3. The worker.
            let workerRoot = options.root
            let installed = call(transport, HelperRequest(
                operation: .installWorker, spaceID: spaceID, username: username,
                runtimeRoot: workerRoot))
            guard installed.ok else {
                return bail(installed.error ?? AgentSpaceError(
                    code: .helperRejected, message: "the helper did not install the worker"))
            }
            steps.append(Step(name: "install worker LaunchAgent", outcome: .done,
                              detail: installed.result?["label"]?.stringValue ?? "installed"))

            cleanup.append {
                let response = call(transport, HelperRequest(
                    operation: .removeWorker, spaceID: spaceID, username: username))
                return response.ok
                    ? Step(name: "undo install worker", outcome: .rolledBack("removed the LaunchAgent"), detail: "")
                    : Step(name: "undo install worker", outcome: .rollbackFailed(response.error?.message ?? "unknown"), detail: "")
            }

            // 4. The Keychain, and the registry.
            do {
                try keychain.store(password: password.value, for: spaceID)
                steps.append(Step(name: "store password in Keychain", outcome: .done,
                                  detail: "so you can sign in to this Space once"))
            } catch {
                return bail(AgentSpaceError(code: .internalError, message: "\(error)"))
            }
            cleanup.append {
                do {
                    try keychain.delete(for: spaceID)
                    return Step(name: "undo store password", outcome: .rolledBack("removed the Keychain item"), detail: "")
                } catch {
                    return Step(name: "undo store password", outcome: .rollbackFailed("\(error)"), detail: "")
                }
            }

            var space = AgentSpace(
                id: spaceID, name: name, username: username, uid: uid_t(uid),
                // Created but not logged in yet: the account exists, the worker
                // cannot start until the user signs in once. Reporting `ready` here
                // would make the UI offer a desktop that does not exist.
                state: .needsLogin, createdAt: Date(), workspace: workspace,
                sharedFolders: sharedFolders)

            do {
                var updated = registry
                updated.upsert(space)
                try updated.save(root: options.root)
                steps.append(Step(name: "save Space", outcome: .done, detail: name))
            } catch {
                return bail(AgentSpaceError(code: .internalError, message: "could not save the Space: \(error)"))
            }

            return Outcome(space: space, steps: steps, error: nil)
        }
    }

    // MARK: - Delete

    /// Delete a Space — plan §41.
    ///
    /// The order is the reverse of creation, and the two steps that need care are
    /// both about *not* destroying the user's work:
    ///
    /// - A **git worktree** is removed with `git worktree remove`, which refuses if
    ///   the worktree is dirty unless forced. The **branch is kept**: it holds the
    ///   agent's commits, and deleting them along with the Space would destroy the
    ///   only copy of work the user might still want. The original repository is
    ///   never touched.
    /// - The **home directory** is only removed when the caller asks, and is a
    ///   separate question in the UI, because it is the one irreversible step.
    public static func delete(
        space: AgentSpace,
        removeHome: Bool,
        options: Options,
        transport: @escaping Transport,
        registry: SpaceRegistry = SpaceRegistry(),
        keychain: KeychainStore = KeychainStore()
    ) -> Outcome {

        var steps: [Step] = []
        var warnings: [String] = []

        // 1. Stop the worker. Before removing the LaunchAgent, because removing
        //    the plist of a running job leaves it running until the next boot.
        let stopped = call(transport, HelperRequest(
            operation: .stopWorker, spaceID: space.id, username: space.username))
        steps.append(Step(
            name: "stop worker",
            outcome: stopped.ok ? .done : .skipped("the worker was not running"),
            detail: stopped.ok ? "" : (stopped.error?.message ?? "")))

        // 2. The worktree, if there is one, and only ever the worktree.
        if case .gitWorktree(let repository, let branch, let path) = space.workspace {
            // `--force` because the agent almost certainly left uncommitted
            // changes; `git worktree remove` refuses without it, and the Space is
            // being deleted at the user's explicit request. The branch survives,
            // which is where any work worth keeping actually lives.
            let result = WorkspacePreparer.run([
                "git", "-C", repository, "worktree", "remove", "--force", path,
            ])
            if result.exitCode == 0 {
                steps.append(Step(name: "remove git worktree", outcome: .done,
                                  detail: "removed \(path); the branch \(branch) and your repository are untouched"))
            } else {
                // A failure here must not stop the deletion: the account is the
                // important part, and a worktree the user can remove by hand is a
                // far better outcome than an account that cannot be removed.
                steps.append(Step(name: "remove git worktree", outcome: .skipped(
                    "could not remove \(path): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines)). Your repository and branch are untouched."),
                    detail: ""))
            }
        }

        // 3. The LaunchAgent and the password.
        let removed = call(transport, HelperRequest(
            operation: .removeWorker, spaceID: space.id, username: space.username))
        steps.append(Step(
            name: "remove worker",
            outcome: removed.ok ? .done : .skipped(removed.error?.message ?? "already removed"),
            detail: ""))

        do {
            try keychain.delete(for: space.id)
            steps.append(Step(name: "forget password", outcome: .done, detail: ""))
        } catch {
            warnings.append("the Keychain item could not be removed: \(error)")
            steps.append(Step(name: "forget password", outcome: .failed("\(error)"), detail: ""))
        }

        // 4. The registry, *before* the account: if the account deletion fails, an
        //    entry pointing at a missing account is worse than no entry, and the
        //    orphan sweep will find the account anyway.
        do {
            var updated = registry
            updated.remove(id: space.id)
            try updated.save(root: options.root)
            steps.append(Step(name: "remove Space record", outcome: .done, detail: ""))
        } catch {
            return Outcome(space: nil, steps: steps, error: AgentSpaceError(
                code: .internalError, message: "could not update the Space registry: \(error)"))
        }

        // 5. The account. Last, because it is the step that makes the Space stop
        //    existing, and everything above is reversible.
        let deleted = call(transport, HelperRequest(
            operation: .deleteUser, username: space.username, removeHome: removeHome))
        guard deleted.ok else {
            // The account is named in every case, not only the fallback: the
            // registry entry has already been removed, so this message is the only
            // remaining pointer to the leftover account.
            let detail = deleted.error?.message ?? "the helper refused"
            return Outcome(space: nil, steps: steps, error: AgentSpaceError(
                code: deleted.error?.code ?? .helperRejected,
                message: "the account \(space.username) still exists: \(detail). It is no longer in the Space list, so remove it with `agentspace doctor` or System Settings → Users & Groups."))
        }
        steps.append(Step(name: "delete account", outcome: .done,
                          detail: removeHome ? "removed \(space.username) and its home" : "removed \(space.username), home kept"))

        // 6. The runtime directory. Best-effort, and last, because a leftover
        //    directory is harmless and does not block anything.
        let runtimeDirectory = "\(options.root)/Runtime/\(space.id.uuidString)"
        if FileManager.default.fileExists(atPath: runtimeDirectory) {
            do {
                try FileManager.default.removeItem(atPath: runtimeDirectory)
                steps.append(Step(name: "remove runtime directory", outcome: .done, detail: ""))
            } catch {
                warnings.append("the runtime directory \(runtimeDirectory) could not be removed: \(error)")
                steps.append(Step(name: "remove runtime directory",
                                  outcome: .skipped("\(error)"), detail: ""))
            }
        }

        // Warnings do not fail the deletion — the account is gone, which is what
        // was asked for — but they are returned so the UI can say what was left
        // behind rather than claiming a clean removal.
        if !warnings.isEmpty {
            for warning in warnings {
                steps.append(Step(name: "warning", outcome: .skipped(warning), detail: ""))
            }
        }
        return Outcome(space: nil, steps: steps, error: nil)
    }

    // MARK: - Helpers

    /// Put a git worktree inside this Space's own directory.
    ///
    /// Only the worktree layout is changed; a shared folder is a path the user
    /// chose and is used exactly as given.
    static func confined(_ workspace: Workspace, spaceID: UUID, options: Options) -> Workspace {
        switch workspace {
        case .gitWorktree(let repository, let branch, _):
            return .gitWorktree(
                repository: repository, branch: branch,
                path: options.worktreePath(spaceID: spaceID, repository: repository))
        case .none, .sharedFolders:
            return workspace
        }
    }

    /// The account name a previous step actually created, if any.
    ///
    /// Read back out of the step detail so the record and the machine cannot drift:
    /// the step is written from the helper's own reply, so it describes what exists.
    private static func usernameFrom(_ steps: [Step]) -> String? {
        for step in steps where step.name == "create account" {
            // "detail" is "<username>, uid <n>, standard user".
            if let username = step.detail.split(separator: ",").first.map(String.init),
               HelperValidation.isAgentSpaceAccount(username) {
                return username
            }
        }
        return nil
    }

    /// Call the helper and turn a transport failure into a typed refusal.
    ///
    /// A thrown error here means the helper could not be reached at all, which is
    /// `HELPER_UNAVAILABLE` — and is emphatically **not** a reason to attempt the
    /// operation another way. There is no unprivileged path to creating a macOS
    /// account, and the failure has to say so rather than leaving the caller to
    /// wonder whether it half-worked.
    private static func call(_ transport: Transport, _ request: HelperRequest) -> HelperResponse {
        do {
            return try transport(request)
        } catch let error as HelperClientError {
            return HelperResponse(id: request.id, error: error.agentSpaceError)
        } catch {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperUnavailable,
                message: "the privileged helper could not be reached: \(error)"))
        }
    }
}
