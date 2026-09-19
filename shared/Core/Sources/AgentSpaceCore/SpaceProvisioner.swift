import Foundation

/// Creating and deleting an agent — plan §28, §41, and the whole of phase 10.
///
/// This is the only place in AgentSpace that changes the machine: it makes a macOS
/// account, installs a launchd job into it, and later removes them. It is therefore
/// written as a **sequence of steps with a recorded outcome for each**, so that a
/// failure half way through can be undone rather than left as a broken Agent that
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
        /// from the agent's *name* collides the moment two Spaces are named `Test`
        /// and `test` — on a case-insensitive filesystem those are one directory,
        /// and two agents would be editing the same working tree, which is the
        /// exact thing the worktree exists to prevent. A name is also not stable:
        /// renaming an agent would move the agent's checkout out from under it.
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
            /// Failed to undo. The agent is in a state the user must be told about.
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
        public var space: AgentAccount?
        public var steps: [Step]
        public var error: AgentSpaceError?
        /// The `_agentspace_…` name a create had committed to before it failed,
        /// or nil when it never got that far. The UI verifies this against the
        /// machine instead of reading a name out of an error string: a name on
        /// screen reads like a thing that exists, and on a machine that blocks
        /// account creation it never does (validation §275).
        public var attemptedUsername: String? = nil

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
    /// 4. **Keychain** before the registry, so a saved Agent always has a password
    ///    to show. The reverse order can produce an agent the user cannot log into.
    public static func create(
        name: String,
        purpose: AgentPurpose? = nil,
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
        var attemptedUsername: String?
        let spaceID = UUID()

        func bail(_ step: String, _ error: AgentSpaceError) -> Outcome {
            // The failed step is recorded, not just returned in `error`: the UI
            // renders the step list, and a run that ends without one — and
            // without the error being shown — reads as success. On this machine
            // a failed create displayed the sign-in instructions for an account
            // that was never made (validation §272).
            steps.append(Step(name: step, outcome: .failed(error.message), detail: ""))
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
                // The Agent record is written even on a failed cleanup, because an
                // account that exists and is not in the registry is invisible to
                // the app — the user would have an `_agentspace_…` user they cannot
                // see or remove. `state: .error` makes it visible and deletable.
                //
                // The username is recovered from the step list rather than tracked
                // separately, because the step is the record of what actually
                // happened on the machine and a second copy could disagree with it.
                let broken = AgentAccount(
                    id: spaceID, name: name, username: usernameFrom(steps) ?? "",
                    uid: 0, state: .error, createdAt: Date(),
                    workspace: workspace, sharedFolders: sharedFolders)
                var updated = registry
                updated.upsert(broken)
                try? updated.save(root: options.root)
            }
            return Outcome(space: nil, steps: steps, error: error,
                           attemptedUsername: attemptedUsername)
        }

        // 0. Validate what can be validated before touching the machine. Doing this
        //    first means a typo in a repository path cannot leave half a Space.
        //
        //    A git worktree's path is rewritten here, where the agent's id exists,
        //    so it is unique by construction rather than by luck. Everything else
        //    the caller asked for is passed through unchanged.
        let workspace = Self.confined(workspace, spaceID: spaceID, options: options)
        switch WorkspacePreparer.plan(
            workspace: workspace, sharedFolders: sharedFolders, spaceID: spaceID,
            workspaceDirectory: options.workspaceDirectory,
            fileExists: fileExists, isGitRepository: isGitRepository) {
        case .failure(let error):
            return bail(NSLocalizedString("plan workspace", comment: ""), error)
        case .success(let plan):
            steps.append(Step(name: NSLocalizedString("plan workspace", comment: ""), outcome: .done, detail: plan.summary))

            // 1. The account.
            let username = HelperValidation.generateAccountName()
            attemptedUsername = username
            let password = SpacePassword()
            let created = call(transport, HelperRequest(
                operation: .createUser, username: username,
                displayName: name, password: password.value))
            guard created.ok else {
                // The helper's own code is preserved: an unreachable helper is
                // HELPER_UNAVAILABLE ("install it"), a refusal is HELPER_REJECTED
                // ("it said no"). Those need different fixes.
                return bail(NSLocalizedString("create account", comment: ""),
                    created.error ?? AgentSpaceError(
                        code: .helperRejected, message: NSLocalizedString("the helper did not create the account", comment: "")))
            }
            let uid = created.result?["uid"]?.intValue ?? 0
            steps.append(Step(name: NSLocalizedString("create account", comment: ""),
                              outcome: .done,
                              detail: String(format: NSLocalizedString("%@, uid %d, standard user", comment: ""), username, uid)))

            cleanup.append {
                let step = NSLocalizedString("undo create account", comment: "")
                let response = call(transport, HelperRequest(
                    operation: .deleteUser, username: username, removeHome: true))
                guard !response.ok else {
                    return Step(name: step,
                        outcome: .rolledBack(String(format: NSLocalizedString("removed %@", comment: ""), username)),
                        detail: "")
                }
                // A refusal is not the same thing as an account left behind, and
                // claiming it would be validation §269's lie in the other
                // direction: the helper refuses a delete for an account that was
                // never made ("there is no account named …"), which is what a
                // blocked create looks like on this machine. So the undo reports
                // what the machine says *now*, not what the delete said.
                let status = call(transport, HelperRequest(operation: .helperStatus))
                if status.ok, let accounts = status.reportedAccounts, !accounts.contains(username) {
                    return Step(name: step,
                        outcome: .rolledBack(String(format: NSLocalizedString("%@ is not on this machine, so there was nothing to undo", comment: ""), username)),
                        detail: "")
                }
                let confirmed = status.ok && status.reportedAccounts?.contains(username) == true
                return Step(name: step,
                    outcome: .rollbackFailed(response.error?.message ?? "unknown"),
                    detail: confirmed
                        ? String(format: NSLocalizedString("the account %@ is still there. Open Diagnostics and use “Delete Orphaned Accounts…” to remove it.", comment: ""), username)
                        : String(format: NSLocalizedString("whether %@ was removed could not be checked, because the helper did not answer again. Open Diagnostics and use “Delete Orphaned Accounts…” to see what is left.", comment: ""), username))
            }

            // 2. The runtime directory, with its ACLs.
            let prepared = call(transport, HelperRequest(
                operation: .prepareRuntimeDirectory, spaceID: spaceID, username: username,
                mainUser: options.mainUser, runtimeRoot: options.root))
            guard prepared.ok, let runtimeDirectory = prepared.result?["runtimeDirectory"]?.stringValue else {
                return bail(NSLocalizedString("prepare runtime directory", comment: ""),
                    prepared.error ?? AgentSpaceError(
                        code: .helperRejected, message: NSLocalizedString("the helper did not prepare the runtime directory", comment: "")))
            }
            steps.append(Step(name: NSLocalizedString("prepare runtime directory", comment: ""), outcome: .done, detail: runtimeDirectory))

            // 2b. The workspace record the worker reads at startup. Written here,
            //     where it can be attributed to this agent's creation, rather than
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
                    steps.append(Step(name: NSLocalizedString("write workspace record", comment: ""),
                                      outcome: .skipped(String(
                                        format: NSLocalizedString("could not write %@; the worker will report confined: false", comment: ""),
                                        recordURL.path)),
                                      detail: ""))
                } else {
                    steps.append(Step(name: NSLocalizedString("write workspace record", comment: ""),
                                      outcome: .done,
                                      detail: String(format: NSLocalizedString("%ld allowed, %ld writable", comment: ""),
                                                     plan.allowedRoots.count, plan.writableRoots.count)))
                }
            }

            // 2c. The workspace itself — the git worktree, if there is one.
            switch WorkspacePreparer.apply(plan) {
            case .failure(let error):
                return bail(NSLocalizedString("apply workspace", comment: ""), error)
            case .success:
                if plan.gitCommand != nil {
                    steps.append(Step(name: NSLocalizedString("create git worktree", comment: ""), outcome: .done, detail: plan.summary))
                } else {
                    steps.append(Step(name: NSLocalizedString("create workspace directories", comment: ""), outcome: .done,
                                      detail: plan.directories.joined(separator: ", ")))
                }
            }

            // 3. The worker.
            let workerRoot = options.root
            let installed = call(transport, HelperRequest(
                operation: .installWorker, spaceID: spaceID, username: username,
                runtimeRoot: workerRoot))
            guard installed.ok else {
                return bail(NSLocalizedString("install worker LaunchAgent", comment: ""),
                    installed.error ?? AgentSpaceError(
                        code: .helperRejected, message: NSLocalizedString("the helper did not install the worker", comment: "")))
            }
            steps.append(Step(name: NSLocalizedString("install worker LaunchAgent", comment: ""), outcome: .done,
                              detail: installed.result?["label"]?.stringValue ?? NSLocalizedString("installed", comment: "")))

            cleanup.append {
                let response = call(transport, HelperRequest(
                    operation: .removeWorker, spaceID: spaceID, username: username))
                return response.ok
                    ? Step(name: NSLocalizedString("undo install worker", comment: ""),
                           outcome: .rolledBack(NSLocalizedString("removed the LaunchAgent", comment: "")), detail: "")
                    : Step(name: NSLocalizedString("undo install worker", comment: ""),
                           outcome: .rollbackFailed(response.error?.message ?? "unknown"), detail: "")
            }

            // 4. The Keychain, and the registry.
            do {
                try keychain.store(password: password.value, for: spaceID)
                steps.append(Step(name: NSLocalizedString("store password in Keychain", comment: ""), outcome: .done,
                                  detail: NSLocalizedString("so you can sign in to this agent once", comment: "")))
            } catch {
                return bail(NSLocalizedString("store password in Keychain", comment: ""),
                    AgentSpaceError(code: .internalError, message: "\(error)"))
            }
            cleanup.append {
                do {
                    try keychain.delete(for: spaceID)
                    return Step(name: NSLocalizedString("undo store password", comment: ""),
                                outcome: .rolledBack(NSLocalizedString("removed the Keychain item", comment: "")), detail: "")
                } catch {
                    return Step(name: NSLocalizedString("undo store password", comment: ""), outcome: .rollbackFailed("\(error)"), detail: "")
                }
            }

            let space = AgentAccount(
                id: spaceID, name: name, username: username, uid: uid_t(uid),
                // Created but not logged in yet: the account exists, the worker
                // cannot start until the user signs in once. Reporting `ready` here
                // would make the UI offer a desktop that does not exist.
                state: .needsLogin, createdAt: Date(), workspace: workspace,
                sharedFolders: sharedFolders, purpose: purpose)

            do {
                var updated = registry
                updated.upsert(space)
                try updated.save(root: options.root)
                steps.append(Step(name: NSLocalizedString("save agent", comment: ""), outcome: .done, detail: name))
            } catch {
                return bail(NSLocalizedString("save agent", comment: ""),
                    AgentSpaceError(code: .internalError, message: String(format: NSLocalizedString("could not save the agent: %@", comment: ""), "\(error)")))
            }

            return Outcome(space: space, steps: steps, error: nil)
        }
    }

    // MARK: - Delete

    /// Delete an agent — plan §41.
    ///
    /// The order is the reverse of creation, and the two steps that need care are
    /// both about *not* destroying the user's work:
    ///
    /// - A **git worktree** is removed with `git worktree remove`, which refuses if
    ///   the worktree is dirty unless forced. The **branch is kept**: it holds the
    ///   agent's commits, and deleting them along with the agent would destroy the
    ///   only copy of work the user might still want. The original repository is
    ///   never touched.
    /// - The **home directory** is only removed when the caller asks, and is a
    ///   separate question in the UI, because it is the one irreversible step.
    public static func delete(
        space: AgentAccount,
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
            name: NSLocalizedString("stop worker", comment: ""),
            outcome: stopped.ok ? .done : .skipped(NSLocalizedString("the worker was not running", comment: "")),
            detail: stopped.ok ? "" : (stopped.error?.message ?? "")))

        // 2. The worktree, if there is one, and only ever the worktree.
        if case .gitWorktree(let repository, let branch, let path) = space.workspace {
            // `--force` because the agent almost certainly left uncommitted
            // changes; `git worktree remove` refuses without it, and the agent is
            // being deleted at the user's explicit request. The branch survives,
            // which is where any work worth keeping actually lives.
            let result = WorkspacePreparer.run([
                "git", "-C", repository, "worktree", "remove", "--force", path,
            ])
            if result.exitCode == 0 {
                steps.append(Step(name: NSLocalizedString("remove git worktree", comment: ""), outcome: .done,
                                  detail: String(format: NSLocalizedString("removed %1$@; the branch %2$@ and your repository are untouched", comment: ""), path, branch)))
            } else {
                // A failure here must not stop the deletion: the account is the
                // important part, and a worktree the user can remove by hand is a
                // far better outcome than an account that cannot be removed.
                steps.append(Step(name: NSLocalizedString("remove git worktree", comment: ""), outcome: .skipped(
                    String(format: NSLocalizedString("could not remove %1$@: %2$@. Your repository and branch are untouched.", comment: ""),
                           path, result.output.trimmingCharacters(in: .whitespacesAndNewlines))),
                    detail: ""))
            }
        }

        // 3. The LaunchAgent and the password.
        let removed = call(transport, HelperRequest(
            operation: .removeWorker, spaceID: space.id, username: space.username))
        steps.append(Step(
            name: NSLocalizedString("remove worker", comment: ""),
            outcome: removed.ok ? .done : .skipped(removed.error?.message ?? NSLocalizedString("already removed", comment: "")),
            detail: ""))

        do {
            try keychain.delete(for: space.id)
            steps.append(Step(name: NSLocalizedString("forget password", comment: ""), outcome: .done, detail: ""))
        } catch {
            warnings.append(String(format: NSLocalizedString("the Keychain item could not be removed: %@", comment: ""), "\(error)"))
            steps.append(Step(name: NSLocalizedString("forget password", comment: ""), outcome: .failed("\(error)"), detail: ""))
        }

        // 4. The registry, *before* the account: if the account deletion fails, an
        //    entry pointing at a missing account is worse than no entry, and the
        //    orphan sweep will find the account anyway.
        do {
            var updated = registry
            updated.remove(id: space.id)
            try updated.save(root: options.root)
            steps.append(Step(name: NSLocalizedString("remove agent record", comment: ""), outcome: .done, detail: ""))
        } catch {
            let error = AgentSpaceError(
                code: .internalError, message: String(format: NSLocalizedString("could not update the agent registry: %@", comment: ""), "\(error)"))
            steps.append(Step(name: NSLocalizedString("remove agent record", comment: ""), outcome: .failed(error.message), detail: ""))
            return Outcome(space: nil, steps: steps, error: error)
        }

        // 5. The account. Last, because it is the step that makes the agent stop
        //    existing, and everything above is reversible.
        let deleted = call(transport, HelperRequest(
            operation: .deleteUser, username: space.username, removeHome: removeHome))
        guard deleted.ok else {
            // The account is named in every case, not only the fallback: the
            // registry entry has already been removed, so this message is the only
            // remaining pointer to the leftover account.
            let detail = deleted.error?.message ?? NSLocalizedString("the helper refused", comment: "")
            let error = AgentSpaceError(
                code: deleted.error?.code ?? .helperRejected,
                message: String(format: NSLocalizedString("the account %1$@ still exists: %2$@. It is no longer in the agent list, so remove it with `agentspace doctor` or System Settings → Users & Groups.", comment: ""), space.username, detail))
            steps.append(Step(name: NSLocalizedString("delete account", comment: ""), outcome: .failed(error.message), detail: ""))
            return Outcome(space: nil, steps: steps, error: error)
        }
        steps.append(Step(name: NSLocalizedString("delete account", comment: ""), outcome: .done,
                          detail: removeHome
                              ? String(format: NSLocalizedString("removed %@ and its home", comment: ""), space.username)
                              : String(format: NSLocalizedString("removed %@, home kept", comment: ""), space.username)))

        // 6. The runtime directory. Best-effort, and last, because a leftover
        //    directory is harmless and does not block anything.
        let runtimeDirectory = "\(options.root)/Runtime/\(space.id.uuidString)"
        if FileManager.default.fileExists(atPath: runtimeDirectory) {
            do {
                try FileManager.default.removeItem(atPath: runtimeDirectory)
                steps.append(Step(name: NSLocalizedString("remove runtime directory", comment: ""), outcome: .done, detail: ""))
            } catch {
                warnings.append(String(format: NSLocalizedString("the runtime directory %1$@ could not be removed: %2$@", comment: ""), runtimeDirectory, "\(error)"))
                steps.append(Step(name: NSLocalizedString("remove runtime directory", comment: ""),
                                  outcome: .skipped("\(error)"), detail: ""))
            }
        }

        // Warnings do not fail the deletion — the account is gone, which is what
        // was asked for — but they are returned so the UI can say what was left
        // behind rather than claiming a clean removal.
        if !warnings.isEmpty {
            for warning in warnings {
                steps.append(Step(name: NSLocalizedString("warning", comment: ""), outcome: .skipped(warning), detail: ""))
            }
        }
        return Outcome(space: nil, steps: steps, error: nil)
    }

    // MARK: - Helpers

    /// Put a git worktree inside this agent's own directory.
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
