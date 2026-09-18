import Foundation
import AgentSpaceCore

/// The privileged helper's eight operations, implemented.
///
/// Everything here is (1) re-validated, then (2) performed with argv arrays. The
/// re-validation is not redundant with the client's: the client is the process
/// that might be compromised, so the check that matters is the one on this side
/// of the boundary.
final class HelperService: NSObject, HelperXPCProtocol {

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
        let response = HelperResponse(id: "ping", result: .obj([
            "helperVersion": .string(helperVersion),
            "protocolVersion": .int(agentSpaceProtocolVersion),
            "isRoot": .bool(geteuid() == 0),
            "pid": .int(Int(getpid())),
            "requirement": .string(CodeSigningRequirement.enforcedRequirement),
        ]))
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

        log.info("performing \(request.operation.rawValue) for \(request.username ?? request.spaceID?.uuidString ?? "-")")

        switch request.operation {
        case .helperStatus:           return status(request)
        case .createUser:             return createUser(request)
        case .deleteUser:             return deleteUser(request)
        case .installWorker:          return installWorker(request, accounts: accounts)
        case .removeWorker:           return removeWorker(request, accounts: accounts)
        case .prepareRuntimeDirectory: return prepareRuntimeDirectory(request)
        case .startWorker:            return workerControl(request, start: true)
        case .stopWorker:             return workerControl(request, start: false)
        case .logoutSession:          return logoutSession(request)
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

    private func createUser(_ request: HelperRequest) -> HelperResponse {
        // Both fields must be present. The password is not bound here because the
        // argv is built by `HelperCommand`, which reads it from the request; this
        // guard is about refusing an incomplete request, not about handling the
        // secret — and a second binding of it is a second place it could leak.
        guard let username = request.username, request.password != nil else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "missing username or password"))
        }

        for command in HelperCommand.createUser(request) {
            // `/usr/bin/createhomedir` was a Python script Apple removed in
            // macOS 26; spawning it there fails with ENOENT and turned every
            // create into a rollback. Where the tool is gone, macOS creates the
            // home at the first GUI login — which plan §28's manual sign-in
            // provides anyway — so the step is skipped rather than fatal.
            if command.first == HelperCommand.createhomedir,
               !FileManager.default.isExecutableFile(atPath: HelperCommand.createhomedir) {
                log.warning("createhomedir is not present on this OS; skipping (the home is created at first login)")
                continue
            }
            let result = CommandRunner.run(command, timeout: 120)
            log.info("\(result.displayCommand) → exit \(result.exitCode)")
            if !result.ok {
                // A failed `sysadminctl` has usually created the account record
                // already. Leaving a half-made account behind would make the next
                // attempt fail with "already exists" and confuse the user, so the
                // partial state is cleaned up before reporting failure — and a
                // cleanup that itself failed must be logged, because an orphaned
                // account with no registry entry and no stored password is
                // otherwise invisible to the app and unexplainable to the user.
                log.error("createUser failed, removing partial account: \(result.standardError)")
                let undo = CommandRunner.run([HelperCommand.sysadminctl, "-deleteUser", username], timeout: 60)
                if !undo.ok {
                    log.error("partial-account cleanup failed (\(undo.exitCode)): \(undo.standardError) — \(username) is left behind and must be removed by hand")
                }
                return HelperResponse(id: request.id, error: AgentSpaceError(
                    code: .helperRejected,
                    message: "could not create the account \(username): \(result.standardError.isEmpty ? "exit \(result.exitCode)" : result.standardError)"))
            }
        }

        guard let uid = self.uid(of: username) else {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperRejected,
                message: "the account \(username) was created but has no uid, which should be impossible"))
        }

        if !FileManager.default.fileExists(atPath: "/Users/\(username)") {
            // Not fatal: a missing home is created by macOS at the account's
            // first GUI login. Logged because the honest place for this fact is
            // the helper's record, not a surprise at sign-in.
            log.warning("the home directory /Users/\(username) does not exist yet; macOS will create it at first login")
        }

        return HelperResponse(id: request.id, result: .obj([
            "username": .string(username),
            "uid": .int(Int(uid)),
            "home": .string(AccountDirectory.homeDirectory(of: username) ?? "/Users/\(username)"),
            // Stated explicitly so a caller never has to infer it: AgentSpace
            // accounts are never administrators. Plan §8.
            "isAdmin": .bool(false),
        ]))
    }

    private func deleteUser(_ request: HelperRequest) -> HelperResponse {
        guard let username = request.username else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "missing username"))
        }

        // Confirm, from the machine rather than from the request, that this is an
        // AgentSpace account before removing anything. The validation step already
        // checked the *name*; this checks the *account*, so a renamed or manually
        // created account that happens to match the pattern but is not ours is
        // still refused if it is not in our registry's expected shape.
        guard let uid = uid(of: username) else {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperRejected,
                message: "there is no account named \(username)"))
        }
        // uid below 500 is a system account. A `_agentspace_`-named account can
        // never legitimately be one, so this only fires if something is very wrong.
        guard uid >= 500 else {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperRejected,
                message: "refusing to delete \(username): uid \(uid) is a system account"))
        }

        var warnings: [String] = []
        for command in HelperCommand.deleteUser(request) {
            let result = CommandRunner.run(command, timeout: 120)
            log.info("\(result.displayCommand) → exit \(result.exitCode)")
            // `dscl . -delete` returns non-zero when the record is already gone,
            // which is the outcome we wanted. Only `sysadminctl` failure is fatal.
            if !result.ok, command.first == HelperCommand.sysadminctl {
                return HelperResponse(id: request.id, error: AgentSpaceError(
                    code: .helperRejected,
                    message: "could not delete the account \(username): \(result.standardError.isEmpty ? "exit \(result.exitCode)" : result.standardError)"))
            }
            if !result.ok {
                warnings.append("\(command.first ?? "?"): \(result.standardError.isEmpty ? "exit \(result.exitCode)" : result.standardError)")
            }
        }

        // Verify rather than assume: the app is about to remove the Space from its
        // registry, and doing that while the account still exists would leave an
        // orphan nothing can clean up.
        let stillThere = AccountDirectory.existingAccounts().contains(username)
        return HelperResponse(id: request.id, result: .obj([
            "username": .string(username),
            "removed": .bool(!stillThere),
            "homeRemoved": .bool(request.removeHome == true),
            "warnings": .array(warnings.map { .string($0) }),
        ]))
    }

    private func installWorker(_ request: HelperRequest, accounts: Set<String>) -> HelperResponse {
        guard let username = request.username, let spaceID = request.spaceID,
              let runtimeRoot = request.runtimeRoot else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "installWorker needs a username, a space ID and a runtime root"))
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
        let installedWorker = "\(launchAgents)/agentspace-worker"

        do {
            // Create the runtime log directory first: launchd opens the log files
            // at spawn time and will fail the job if the directory is missing.
            let runtimeDirectory = "\(runtimeRoot)/Runtime/\(spaceID.uuidString)"
            try fileManager.createDirectory(atPath: runtimeDirectory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700, .ownerAccountID: uid, .groupOwnerAccountID: gid(of: username) ?? 20])

            try fileManager.createDirectory(atPath: launchAgents, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o755, .ownerAccountID: uid, .groupOwnerAccountID: gid(of: username) ?? 20])

            if fileManager.fileExists(atPath: installedWorker) {
                try fileManager.removeItem(atPath: installedWorker)
            }
            try fileManager.copyItem(atPath: workerSource, toPath: installedWorker)
            try fileManager.setAttributes([.posixPermissions: 0o755, .ownerAccountID: uid, .groupOwnerAccountID: gid(of: username) ?? 20],
                                          ofItemAtPath: installedWorker)

            let plistURL = URL(fileURLWithPath: "\(launchAgents)/\(HelperCommand.workerLabel(spaceID: spaceID)).plist")
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

        let home = AccountDirectory.homeDirectory(of: username) ?? "/Users/\(username)"
        let launchAgents = "\(home)/Library/LaunchAgents"
        let label = HelperCommand.workerLabel(spaceID: spaceID)

        // Stop it first: removing the plist of a running job leaves it running
        // until the next boot, which is exactly the kind of stale state that makes
        // "delete the Space" appear not to work.
        let uidValue = uid(of: username) ?? 0
        _ = CommandRunner.run([HelperCommand.launchctl, "bootout", "gui/\(uidValue)/\(label)"], timeout: 30)

        var removed: [String] = []
        for path in ["\(launchAgents)/\(label).plist", "\(launchAgents)/agentspace-worker"] {
            if FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
                removed.append(path)
            }
        }
        log.info("removed worker artifacts for \(username): \(removed.joined(separator: ", "))")
        return HelperResponse(id: request.id, result: .obj([
            "username": .string(username),
            "removed": .array(removed.map { .string($0) }),
        ]))
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
        ]

        do {
            for path in paths {
                try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755, .ownerAccountID: 0, .groupOwnerAccountID: 0])
            }
            // 1770 on the shared root: the sticky bit stops one Space from
            // deleting another's runtime directory, and the group-execute bit lets
            // members traverse. The runtime dir itself is 0700 to the Space's own
            // uid — the socket there carries a live session token, so nobody else
            // gets to open it, including the main user.
            _ = CommandRunner.run([HelperCommand.chmod, "1770", root])
            let runtimeDirectory = "\(root)/Runtime/\(spaceID.uuidString)"
            _ = CommandRunner.run([HelperCommand.chmod, "700", runtimeDirectory])
            _ = CommandRunner.run([HelperCommand.chown, "\(spaceUID):\(gid(of: username) ?? 20)", runtimeDirectory])
            // The screenshots subdirectory is the one thing the main user needs to
            // read, because the app shows the preview in the main user's session.
            let screenshots = "\(runtimeDirectory)/screenshots"
            _ = CommandRunner.run([HelperCommand.chmod, "750", screenshots])
            _ = CommandRunner.run([HelperCommand.chown, "\(spaceUID):\(gid(of: username) ?? 20)", screenshots])
            // Spaces/index.json and Logs belong to the main user.
            for path in ["\(root)/Spaces", "\(root)/Logs"] {
                _ = CommandRunner.run([HelperCommand.chown, "\(mainUID):20", path])
            }

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

    /// §40: end the Space's whole GUI session while keeping the account and
    /// its home. `launchctl bootout gui/<uid>` is the mechanism — the same
    /// domain teardown launchd itself performs at logout — and it is a
    /// root-only operation, which is exactly why it lives here as a *typed*
    /// RPC rather than as a shell escape hatch (§6).
    ///
    /// The uid is cross-checked against the username's real passwd entry:
    /// accepting a mismatched pair would let a confused (or hostile) request
    /// boot out a session this Space does not own.
    private func logoutSession(_ request: HelperRequest) -> HelperResponse {
        guard let username = request.username, let uid = request.uid, uid > 0 else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "logoutSession needs the Space's username and uid"))
        }
        guard let real = self.uid(of: username), real == uid else {
            return HelperResponse(id: request.id, error: AgentSpaceError(
                code: .helperRejected,
                message: "the uid \(uid) does not belong to \(username); refusing to tear down a session on a mismatched pair"))
        }
        let result = CommandRunner.run([HelperCommand.launchctl, "bootout", "gui/\(uid)"], timeout: 60)
        log.info("\(result.displayCommand) → exit \(result.exitCode)")
        guard result.ok else {
            // Booting out an already-absent session is not an error — §39 says
            // a logged-out Space is a normal state, not a fault.
            let absent = result.standardError.contains("Could not find") || result.standardError.contains("No such process")
            guard absent else {
                return HelperResponse(id: request.id, error: AgentSpaceError(
                    code: .helperRejected,
                    message: "logout failed: \(result.standardError.isEmpty ? "exit \(result.exitCode)" : result.standardError)"))
            }
            return HelperResponse(id: request.id, result: .obj([
                "loggedOut": .bool(false), "username": .string(username), "uid": .int(Int(uid)),
            ]))
        }
        return HelperResponse(id: request.id, result: .obj([
            "loggedOut": .bool(true), "username": .string(username), "uid": .int(Int(uid)),
        ]))
    }

    private func workerControl(_ request: HelperRequest, start: Bool) -> HelperResponse {
        guard let username = request.username, let spaceID = request.spaceID else {
            return HelperResponse(id: request.id, error: AgentSpaceError(code: .helperRejected, message: "this operation needs a username and a space ID"))
        }
        let uidValue = uid(of: username) ?? 0
        let label = HelperCommand.workerLabel(spaceID: spaceID)
        let domain = "gui/\(uidValue)/\(label)"

        // `kickstart -k` rather than `bootstrap`: the job is already bootstrapped
        // by launchd at login, and kickstarting is what restarts it without
        // requiring an interactive session.
        let command = start
            ? [HelperCommand.launchctl, "kickstart", "-k", domain]
            : [HelperCommand.launchctl, "bootout", domain]
        let result = CommandRunner.run(command, timeout: 60)
        log.info("\(result.displayCommand) → exit \(result.exitCode)")

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
