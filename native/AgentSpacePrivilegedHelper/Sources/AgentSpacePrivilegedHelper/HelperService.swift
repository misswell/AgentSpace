import Foundation
import AgentSpaceCore

/// The privileged helper's typed operations, implemented. V3 actively uses
/// worker/runtime management; legacy account and session verbs remain decoded
/// only so an older client receives a typed refusal.
///
/// Everything here is (1) re-validated, then (2) performed with argv arrays. The
/// re-validation is not redundant with the client's: the client is the process
/// that might be compromised, so the check that matters is the one on this side
/// of the boundary.
final class HelperService: NSObject, HelperXPCProtocol {

    private struct AttachmentRecord: Codable {
        let spaceID: UUID
        let username: String
        let uid: uid_t
        let homeDirectory: String
    }

    private let log = HelperLog()

    /// Pids that passed the code-signature check when they connected.
    ///
    /// Recorded, but never *trusted*: `handle` re-verifies the pid before doing
    /// anything privileged. The set only exists so a pid that was already refused
    /// at connection time is not silently served if something reuses it.
    let verifiedPeerPIDs = NSMutableSet()

    // MARK: - XPC surface

    func perform(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        let request: HelperRequest
        do {
            request = try JSONDecoder().decode(HelperRequest.self, from: requestData)
        } catch {
            // An undecodable request is a bug or an attack; either way it is not
            // something to guess at. Refused with a typed error, never retried.
            let response = HelperResponse(
                id: "unknown",
                error: AgentSpaceError(code: .badRequest, message: "the helper could not decode the request: \(error)"))
            reply((try? JSONEncoder().encode(response)) ?? Data())
            return
        }

        // `NSXPCConnection.current()` is the supported way to identify which
        // connection a message arrived on, and therefore which pid to verify.
        let pid = NSXPCConnection.current()?.processIdentifier ?? 0
        let response = handle(request, from: pid)
        reply((try? JSONEncoder().encode(response)) ?? Data())
    }

    func ping(withReply reply: @escaping (Data) -> Void) {
        var result: [String: JSONValue] = [
            "helperVersion": .string(helperVersion),
            "protocolVersion": .int(agentSpaceProtocolVersion),
            "isRoot": .bool(geteuid() == 0),
            "pid": .int(Int(getpid())),
            "requirement": .string(CodeSigningRequirement.enforcedRequirement),
        ]
        // The CDHash of the *running image*, so the caller can tell whether
        // launchd is serving it the current binary or one kept alive across an
        // app update. Omitted only when the Security framework could not read
        // itself, which the caller treats as "old helper" — the honest default.
        if let cdHash = HelperInstallation.currentProcessCDHash() {
            result["selfCDHash"] = .string(cdHash)
        }
        let response = HelperResponse(id: "ping", result: .obj(result))
        reply((try? JSONEncoder().encode(response)) ?? Data())
    }

    // MARK: - Dispatch

    private func handle(_ request: HelperRequest, from pid: pid_t) -> HelperResponse {
        // Step 0: re-verify the caller, on every operation rather than only at
        // connection time. This is what makes the pid-based check in
        // `CodeSigningRequirement` cost an attacker more than one lucky moment:
        // they must present the same signed code again, immediately before the
        // privileged work, not merely have been checked once.
        guard verifiedPeerPIDs.contains(pid), CodeSigningRequirement.verifiedPeer(pid: pid) != nil else {
            log.error("refusing \(request.operation.rawValue): pid \(pid) no longer satisfies the caller requirement")
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .unauthorized,
                message: "the caller did not satisfy the helper's code signing requirement"))
        }

        // Step 1: refuse to run at all if we are not root. A helper that is
        // somehow launched without privileges must not half-perform an operation
        // and report success.
        guard geteuid() == 0 else {
            log.error("refusing \(request.operation.rawValue): the helper is not running as root (euid \(geteuid()))")
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperRejected,
                message: "the helper is not running as root, so it cannot perform privileged operations"))
        }

        // Step 2: validation, against the machine's real account list.
        let accounts = AccountDirectory.existingAccounts()
        if let problem = HelperValidation.validate(request, existingAccounts: accounts) {
            log.error("refusing \(request.operation.rawValue): \(problem.message)")
            return HelperResponse(id: request.id, error: problem)
        }
        let teardown = request.operation == .stopWorker
            || request.operation == .removeWorker
            || request.operation == .removeRuntimeDirectory
        if let username = request.username,
           !HelperValidation.isAgentSpaceAccount(username),
           request.operation != .createUser,
           request.operation != .deleteUser {
            let liveAccountIsAttachable = uid(of: username).map { $0 >= 500 } == true
                && AccountDirectory.homeDirectory(of: username)?.hasPrefix("/Users/") == true
                && AccountDirectory.isAdministrator(username) == false
            let recordMatches = teardown && attachmentRecord(for: request).map {
                $0.username == username && $0.uid == request.uid
            } == true
            guard liveAccountIsAttachable || recordMatches else {
                return HelperResponse(id: request.id, error: AgentSpaceError(
                    code: .helperRejected,
                    message: "\(username) is not a verified standard local user"))
            }
        }

        log.info("performing \(request.operation.rawValue) for \(request.username ?? request.spaceID?.uuidString ?? "-")")

        switch request.operation {
        case .helperStatus:           return status(request)
        case .createUser, .deleteUser: return legacyAccountMutation(request)
        case .installWorker:          return installWorker(request, accounts: accounts)
        case .removeWorker:           return removeWorker(request, accounts: accounts)
        case .prepareRuntimeDirectory: return prepareRuntimeDirectory(request)
        case .removeRuntimeDirectory: return removeRuntimeDirectory(request)
        case .startWorker:            return workerControl(request, start: true)
        case .stopWorker:             return workerControl(request, start: false)
        case .logoutSession:          return legacySessionMutation(request)
        case .sessionInfo:            return sessionInfo(request)
        }
    }

    // MARK: - Operations

    private func status(_ request: HelperRequest) -> HelperResponse {
        let accounts = AccountDirectory.existingAccounts()
            .filter { HelperValidation.isAgentSpaceAccount($0) }
            .sorted()
        return HelperResponse(id: request.id, result: .obj([
            "helperVersion": .string(helperVersion),
            "protocolVersion": .int(agentSpaceProtocolVersion),
            "isRoot": .bool(geteuid() == 0),
            "spaceAccounts": .array(accounts.map { .string($0) }),
            "requirement": .string(CodeSigningRequirement.enforcedRequirement),
        ]))
    }

    private func legacyAccountMutation(_ request: HelperRequest) -> HelperResponse {
        HelperResponse(id: request.id, error: AgentSpaceError(
            code: .helperRejected,
            message: "\(request.operation.rawValue) is unavailable: AgentSpace connects existing macOS accounts and never creates or deletes users"))
    }

    private func legacySessionMutation(_ request: HelperRequest) -> HelperResponse {
        HelperResponse(id: request.id, error: AgentSpaceError(
            code: .helperRejected,
            message: "logoutSession is unavailable in V3: AgentSpace does not manage macOS login sessions"))
    }

    private func installWorker(_ request: HelperRequest, accounts: Set<String>) -> HelperResponse {
        guard let username = request.username, let spaceID = request.spaceID,
              let runtimeRoot = request.runtimeRoot, let mainUser = request.mainUser else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "installWorker needs a username, a space ID, the main user and a runtime root"))
        }
        _ = accounts

        guard let uid = uid(of: username) else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "there is no account named \(username)"))
        }

        // Where the worker binary comes from: this helper's own bundle. Taking it
        // from the request would let a compromised app install an arbitrary binary
        // as a launchd job inside a Space.
        let workerSource = helperBundleWorkerPath()
        guard FileManager.default.isExecutableFile(atPath: workerSource) else {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperRejected,
                message: "the helper bundle has no agentspace-worker at \(workerSource)"))
        }

        let fileManager = FileManager.default
        let home = AccountDirectory.homeDirectory(of: username) ?? "/Users/\(username)"
        let launchAgents = "\(home)/Library/LaunchAgents"
        let installedWorker = HelperCommand.workerInstallPath(version: helperVersion)
        let workerVersionDirectory = (installedWorker as NSString).deletingLastPathComponent

        do {
            let runtimeDirectory = "\(runtimeRoot)/Runtime/\(spaceID.uuidString)"
            // Installation is allowed only after the helper completed runtime
            // preparation. Never recreate the directory here without its ACL.
            if let problem = RuntimePermissionVerifier.verifyDirectory(
                runtimeDirectory,
                expectedOwner: uid,
                mainUser: mainUser,
                agentUser: username) {
                return HelperResponse(id: request.id, error: problem)
            }

            // macOS does not create an account's home directory until that
            // account completes its first GUI login. Attaching an existing
            // account before that login is supported, so this is a successful
            // deferred install rather than a malformed-path failure. The
            // caller records `needsLogin`; after the user signs in once, it
            // retries this same typed operation and the LaunchAgent is written
            // into the now-real home directory. Never create `/Users/<name>`
            // here: doing so would bypass macOS's home-directory lifecycle.
            var homeInfo = stat()
            if lstat(home, &homeInfo) != 0, errno == ENOENT {
                return HelperResponse(id: request.id, result: .obj([
                    "username": .string(username),
                    "homeDirectory": .string(home),
                    "deferred": .bool(true),
                    "reason": .string("homeDirectoryMissing"),
                ]))
            }

            try prepareLaunchAgentsDirectory(home: home, uid: uid, gid: gid(of: username) ?? 20)

            // The executable is shared and root-owned. Only the small plist lives
            // in the agent's home, so the agent cannot replace the code launchd
            // executes on its next login.
            for directory in [HelperCommand.workerInstallRoot, workerVersionDirectory] {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: directory, isDirectory: &isDirectory) {
                    let attributes = try fileManager.attributesOfItem(atPath: directory)
                    guard isDirectory.boolValue, attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                        throw NSError(domain: "AgentSpace.Helper", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "refusing a non-directory or symlinked worker path at \(directory)",
                        ])
                    }
                } else {
                    try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
                }
                try fileManager.setAttributes(
                    [.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0],
                    ofItemAtPath: directory)
            }

            if fileManager.fileExists(atPath: installedWorker) {
                try fileManager.removeItem(atPath: installedWorker)
            }
            try fileManager.copyItem(atPath: workerSource, toPath: installedWorker)
            try fileManager.setAttributes([.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0],
                                          ofItemAtPath: installedWorker)

            let plistURL = URL(fileURLWithPath: "\(launchAgents)/\(HelperCommand.workerLabel(spaceID: spaceID)).plist")
            try refuseSymbolicLink(at: plistURL.path)
            let plist = HelperCommand.workerLaunchAgent(
                spaceID: spaceID, username: username, workerPath: installedWorker, runtimeRoot: runtimeRoot)
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o644, .ownerAccountID: uid, .groupOwnerAccountID: gid(of: username) ?? 20],
                                          ofItemAtPath: plistURL.path)

            log.info("installed worker for \(username) at \(installedWorker)")
            return HelperResponse(id: request.id, result: .obj([
                "username": .string(username),
                "workerPath": .string(installedWorker),
                "launchAgentPath": .string(plistURL.path),
                "label": .string(HelperCommand.workerLabel(spaceID: spaceID)),
                "runtimeDirectory": .string(runtimeDirectory),
            ]))
        } catch {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .internalError,
                message: "could not install the worker for \(username): \(error.localizedDescription)"))
        }
    }

    private func removeWorker(_ request: HelperRequest, accounts: Set<String>) -> HelperResponse {
        guard let username = request.username, let spaceID = request.spaceID else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "removeWorker needs a username and a space ID"))
        }
        _ = accounts

        let record = attachmentRecord(for: request)
        guard let uidValue = uid(of: username) ?? record?.uid ?? request.uid else {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperRejected, message: "there is no account named \(username)"))
        }
        let home = AccountDirectory.homeDirectory(of: username)
            ?? record?.homeDirectory
            ?? "/Users/\(username)"
        let launchAgents = "\(home)/Library/LaunchAgents"
        let label = HelperCommand.workerLabel(spaceID: spaceID)

        do {
            let stopped = CommandRunner.run(
                [HelperCommand.launchctl, "bootout", "gui/\(uidValue)/\(label)"], timeout: 30)
            let absent = stopped.standardError.localizedCaseInsensitiveContains("not found")
                || stopped.standardError.localizedCaseInsensitiveContains("no such process")
                || stopped.standardError.localizedCaseInsensitiveContains("could not find specified service")
                || stopped.standardError.localizedCaseInsensitiveContains("could not find domain for user")
            guard stopped.ok || absent else {
                throw NSError(domain: "AgentSpace.Helper", code: Int(stopped.exitCode), userInfo: [
                    NSLocalizedDescriptionKey: "could not stop \(label): \(stopped.standardError)",
                ])
            }
            guard FileManager.default.fileExists(atPath: home) else {
                return HelperResponse(id: request.id, result: .obj([
                    "username": .string(username),
                    "removed": .array([]),
                ]))
            }
            try prepareLaunchAgentsDirectory(home: home, uid: uidValue,
                                             gid: gid(of: username) ?? 20, create: false)
            var removed: [String] = []
            for path in ["\(launchAgents)/\(label).plist", "\(launchAgents)/agentspace-worker"] {
                try refuseSymbolicLink(at: path)
                if FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.removeItem(atPath: path)
                    removed.append(path)
                }
            }
            log.info("removed worker artifacts for \(username): \(removed.joined(separator: ", "))")
            return HelperResponse(id: request.id, result: .obj([
                "username": .string(username),
                "removed": .array(removed.map { .string($0) }),
            ]))
        } catch {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .internalError,
                message: "could not remove the worker for \(username): \(error.localizedDescription)"))
        }
    }

    private func prepareLaunchAgentsDirectory(
        home: String,
        uid: uid_t,
        gid: gid_t,
        create: Bool = true
    ) throws {
        let fileManager = FileManager.default
        try requireRealDirectory(home, owner: uid)
        for path in ["\(home)/Library", "\(home)/Library/LaunchAgents"] {
            if !fileManager.fileExists(atPath: path) {
                guard create else { return }
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o755,
                                                             .ownerAccountID: uid,
                                                             .groupOwnerAccountID: gid])
            }
            try requireRealDirectory(path, owner: uid)
        }
    }

    private func requireRealDirectory(_ path: String, owner uid: uid_t) throws {
        var info = stat()
        guard lstat(path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == uid else {
            throw NSError(domain: "AgentSpace.Helper", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "refusing a missing, symlinked, non-directory or wrongly owned path at \(path)",
            ])
        }
    }

    private func refuseSymbolicLink(at path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT != S_IFLNK else {
            throw NSError(domain: "AgentSpace.Helper", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "refusing a symbolic link at \(path)",
            ])
        }
    }

    private func prepareRuntimeDirectory(_ request: HelperRequest) -> HelperResponse {
        guard let spaceID = request.spaceID, let root = request.runtimeRoot,
              let mainUser = request.mainUser, let username = request.username else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "prepareRuntimeDirectory needs a space ID, a runtime root, a main user and a username"))
        }

        guard let mainUID = uid(of: mainUser), let spaceUID = uid(of: username) else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "could not resolve the uid of \(mainUser) or \(username)"))
        }

        let fileManager = FileManager.default
        let paths = [
            "\(root)",
            "\(root)/Runtime",
            "\(root)/Runtime/\(spaceID.uuidString)",
            "\(root)/Runtime/\(spaceID.uuidString)/screenshots",
            "\(root)/Spaces",
            "\(root)/Logs",
            "\(root)/Worktrees",
            "\(root)/Attachments",
        ]

        do {
            func runRequired(_ arguments: [String]) throws {
                let result = CommandRunner.run(arguments, timeout: 30)
                guard result.ok else {
                    throw NSError(domain: "AgentSpace.Helper", code: Int(result.exitCode), userInfo: [
                        NSLocalizedDescriptionKey: "\(result.displayCommand) failed: \(result.standardError.isEmpty ? "exit \(result.exitCode)" : result.standardError)",
                    ])
                }
            }

            for path in paths {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0])
            }
            // Shared parents are traversable but root-owned. Actual runtime data
            // stays in a 0700 account directory widened only by its two-user ACL.
            try runRequired([HelperCommand.chmod, "755", root])
            try runRequired([HelperCommand.chmod, "755", "\(root)/Runtime"])
            let runtimeDirectory = "\(root)/Runtime/\(spaceID.uuidString)"
            try runRequired([HelperCommand.chmod, "700", runtimeDirectory])
            try runRequired([HelperCommand.chown, "\(spaceUID):\(gid(of: username) ?? 20)", runtimeDirectory])
            try runRequired([HelperCommand.chmod, "-N", runtimeDirectory])
            if let problem = RuntimePaths(spaceID: spaceID, root: root)
                .applyACL(mainUser: mainUser, agentUser: username) {
                throw NSError(domain: "AgentSpace.Helper", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: problem.message,
                ])
            }
            // The screenshots subdirectory is the one thing the main user needs to
            // read, because the app shows the preview in the main user's session.
            let screenshots = "\(runtimeDirectory)/screenshots"
            try runRequired([HelperCommand.chmod, "750", screenshots])
            try runRequired([HelperCommand.chown, "\(spaceUID):\(gid(of: username) ?? 20)", screenshots])
            // Registry, logs and worktrees are maintained by the controller.
            for path in ["\(root)/Spaces", "\(root)/Logs", "\(root)/Worktrees"] {
                try runRequired([HelperCommand.chown, "\(mainUID):20", path])
                try runRequired([HelperCommand.chmod, "700", path])
            }
            try runRequired([HelperCommand.chown, "0:0", "\(root)/Attachments"])
            try runRequired([HelperCommand.chmod, "700", "\(root)/Attachments"])
            let attachment = AttachmentRecord(
                spaceID: spaceID,
                username: username,
                uid: spaceUID,
                homeDirectory: AccountDirectory.homeDirectory(of: username) ?? "/Users/\(username)")
            let attachmentURL = URL(fileURLWithPath: attachmentPath(root: root, spaceID: spaceID))
            try JSONEncoder().encode(attachment).write(to: attachmentURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600, .ownerAccountID: 0, .groupOwnerAccountID: 0],
                ofItemAtPath: attachmentURL.path)

            log.info("prepared runtime directory for \(spaceID.uuidString)")
            return HelperResponse(id: request.id, result: .obj([
                "runtimeDirectory": .string(runtimeDirectory),
                "mainUser": .string(mainUser),
                "mainUID": .int(Int(mainUID)),
                "spaceUID": .int(Int(spaceUID)),
            ]))
        } catch {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .internalError,
                message: "could not prepare the runtime directory: \(error.localizedDescription)"))
        }
    }

    private func removeRuntimeDirectory(_ request: HelperRequest) -> HelperResponse {
        guard let spaceID = request.spaceID, let root = request.runtimeRoot,
              let username = request.username,
              let expectedUID = uid(of: username) ?? attachmentRecord(for: request)?.uid ?? request.uid else {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperRejected,
                message: "removeRuntimeDirectory needs a space ID, attached account and runtime root"))
        }
        let directory = RuntimePaths(spaceID: spaceID, root: root).directory
        guard FileManager.default.fileExists(atPath: directory) else {
            let marker = attachmentPath(root: root, spaceID: spaceID)
            if FileManager.default.fileExists(atPath: marker) {
                do { try FileManager.default.removeItem(atPath: marker) }
                catch {
                    return HelperResponse(id: request.id, error: AgentSpaceError(
                        code: .internalError,
                        message: "could not remove the attachment record: \(error.localizedDescription)"))
                }
            }
            return HelperResponse(id: request.id, result: .obj([
                "runtimeDirectory": .string(directory),
                "removed": .bool(false),
            ]))
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == expectedUID else {
                return HelperResponse(id: request.id, error: AgentSpaceError(
                    code: .helperRejected,
                    message: "refusing to remove a runtime not owned by \(username)"))
            }
            try FileManager.default.removeItem(atPath: directory)
            let marker = attachmentPath(root: root, spaceID: spaceID)
            if FileManager.default.fileExists(atPath: marker) {
                try FileManager.default.removeItem(atPath: marker)
            }
            return HelperResponse(id: request.id, result: .obj([
                "runtimeDirectory": .string(directory),
                "removed": .bool(true),
            ]))
        } catch {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .internalError,
                message: "could not remove the runtime directory: \(error.localizedDescription)"))
        }
    }

    private func workerControl(_ request: HelperRequest, start: Bool) -> HelperResponse {
        guard let username = request.username, let spaceID = request.spaceID else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "this operation needs a username and a space ID"))
        }
        guard let uidValue = uid(of: username) ?? attachmentRecord(for: request)?.uid ?? request.uid else {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperRejected, message: "could not resolve the attached account uid"))
        }
        let label = HelperCommand.workerLabel(spaceID: spaceID)
        let domain = "gui/\(uidValue)/\(label)"

        let result: CommandRunner.Result
        if start {
            let home = AccountDirectory.homeDirectory(of: username) ?? "/Users/\(username)"
            let plist = "\(home)/Library/LaunchAgents/\(label).plist"
            do {
                try prepareLaunchAgentsDirectory(
                    home: home, uid: uidValue, gid: gid(of: username) ?? 20, create: false)
                try refuseSymbolicLink(at: plist)
                guard FileManager.default.fileExists(atPath: plist) else {
                    throw NSError(domain: "AgentSpace.Helper", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "the worker LaunchAgent is not installed at \(plist)",
                    ])
                }

                let commands = HelperCommand.workerReloadCommands(
                    uid: uidValue, spaceID: spaceID, plistPath: plist)
                let bootedOut = CommandRunner.run(commands[0], timeout: 60)
                log.info("\(bootedOut.displayCommand) → exit \(bootedOut.exitCode)")
                let oldJobWasAbsent = bootedOut.standardError.localizedCaseInsensitiveContains("not found")
                    || bootedOut.standardError.localizedCaseInsensitiveContains("no such process")
                    || bootedOut.standardError.localizedCaseInsensitiveContains("could not find specified service")
                    || bootedOut.standardError.localizedCaseInsensitiveContains("could not find domain for user")
                guard bootedOut.ok || oldJobWasAbsent else {
                    throw NSError(domain: "AgentSpace.Helper", code: Int(bootedOut.exitCode), userInfo: [
                        NSLocalizedDescriptionKey: bootedOut.standardError.isEmpty
                            ? "could not unload the existing worker job"
                            : bootedOut.standardError,
                    ])
                }

                let bootstrapped = CommandRunner.run(commands[1], timeout: 60)
                log.info("\(bootstrapped.displayCommand) → exit \(bootstrapped.exitCode)")
                guard bootstrapped.ok else {
                    throw NSError(domain: "AgentSpace.Helper", code: Int(bootstrapped.exitCode), userInfo: [
                        NSLocalizedDescriptionKey: bootstrapped.standardError.isEmpty
                            ? "could not load the updated worker LaunchAgent"
                            : bootstrapped.standardError,
                    ])
                }

                result = CommandRunner.run(commands[2], timeout: 60)
                log.info("\(result.displayCommand) → exit \(result.exitCode)")
            } catch {
                return HelperResponse(id: request.id, error: AgentSpaceError(
                    code: .helperRejected,
                    message: "start failed: \(error.localizedDescription)"))
            }
        } else {
            result = CommandRunner.run(
                [HelperCommand.launchctl, "bootout", domain], timeout: 60)
            log.info("\(result.displayCommand) → exit \(result.exitCode)")
        }

        guard result.ok else {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperRejected,
                message: "\(start ? "start" : "stop") failed: \(result.standardError.isEmpty ? "exit \(result.exitCode)" : result.standardError)"))
        }
        return HelperResponse(id: request.id, result: .obj([
            "label": .string(label),
            "domain": .string(domain),
            "started": .bool(start),
        ]))
    }

    private func sessionInfo(_ request: HelperRequest) -> HelperResponse {
        guard let username = request.username else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "sessionInfo needs a username"))
        }
        guard let uid = uid(of: username) else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "there is no account named \(username)"))
        }

        // Is there a GUI login for this account? `launchctl print gui/<uid>` is
        // the supported question, and it answers exactly what matters: whether
        // there is an Aqua session whose WindowServer the agent could drive.
        let result = CommandRunner.run([HelperCommand.launchctl, "print", "gui/\(uid)"], timeout: 30)
        let hasGraphicalSession = result.ok && result.standardOutput.contains("com.apple.uisecd")
            || (result.ok && result.standardOutput.contains("ATTRS"))

        return HelperResponse(id: request.id, result: .obj([
            "username": .string(username),
            "uid": .int(Int(uid)),
            "hasGraphicalSession": .bool(hasGraphicalSession),
            "detail": .string(result.ok ? "gui/\(uid) exists" : "no gui/\(uid) domain"),
        ]))
    }

    private func attachmentPath(root: String, spaceID: UUID) -> String {
        "\(root)/Attachments/\(spaceID.uuidString).json"
    }

    private func attachmentRecord(for request: HelperRequest) -> AttachmentRecord? {
        guard let root = request.runtimeRoot, let spaceID = request.spaceID,
              HelperValidation.validateRuntimeRoot(root) == nil else { return nil }
        let path = attachmentPath(root: root, spaceID: spaceID)
        var info = stat()
        guard lstat(path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == 0,
              info.st_mode & 0o077 == 0,
              let data = FileManager.default.contents(atPath: path),
              let record = try? JSONDecoder().decode(AttachmentRecord.self, from: data),
              record.spaceID == spaceID else { return nil }
        return record
    }

    // MARK: - Helpers

    private func uid(of username: String) -> uid_t? {
        var buffer = [CChar](repeating: 0, count: 4096)
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>?
        guard getpwnam_r(username, &pwd, &buffer, buffer.count, &result) == 0, result != nil else { return nil }
        return pwd.pw_uid
    }

    private func gid(of username: String) -> gid_t? {
        var buffer = [CChar](repeating: 0, count: 4096)
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>?
        guard getpwnam_r(username, &pwd, &buffer, buffer.count, &result) == 0, result != nil else { return nil }
        return pwd.pw_gid
    }

    /// Where the worker binary lives inside the app bundle, relative to this
    /// helper's own location. `Helper.app/Contents/Library/LaunchDaemons/…` is the
    /// helper, so `../../MacOS/agentspace-worker` is the worker.
    private func helperBundleWorkerPath() -> String {
        let helperPath = Bundle.main.bundlePath
        // Inside the daemon's own bundle: Contents/MacOS/<binary>
        let inBundle = URL(fileURLWithPath: helperPath)
            .deletingLastPathComponent()   // Contents
            .appendingPathComponent("MacOS/agentspace-worker").path
        if FileManager.default.isExecutableFile(atPath: inBundle) { return inBundle }

        // The daemon is registered from the app, where it sits in
        // Contents/Library/LaunchDaemons and the worker is in Contents/MacOS.
        let appRelative = URL(fileURLWithPath: helperPath)
            .deletingLastPathComponent()   // Library
            .deletingLastPathComponent()   // Contents
            .appendingPathComponent("MacOS/agentspace-worker").path
        if FileManager.default.isExecutableFile(atPath: appRelative) { return appRelative }

        // Last resort that is still not attacker-controlled: the installed path.
        return "/Library/PrivilegedHelperTools/agentspace-worker"
    }
}
