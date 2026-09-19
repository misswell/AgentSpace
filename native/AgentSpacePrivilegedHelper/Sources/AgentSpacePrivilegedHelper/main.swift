import Foundation
import AgentSpaceCore

/// The AgentSpace privileged helper — plan §6, §7.
///
/// Runs as root, launched by `launchd` from a `SMAppService` LaunchDaemon inside
/// the app bundle. It owns exactly the operations that genuinely need root:
/// creating and deleting a Space's macOS account, installing and removing its
/// worker LaunchAgent, preparing its runtime directory, and starting and stopping
/// that worker. There is no generic shell, no file-write primitive and no
/// arbitrary-path operation.
///
/// ## What this process is allowed to be wrong about
///
/// Nothing. Every design decision here assumes the caller may be hostile, because
/// the agent is a useful adversary model: it is code we wrote, running in a
/// context we deliberately gave the ability to drive a computer, and it may be
/// running someone else's instructions. So the caller is verified by code
/// signature, every request is re-validated here, and every command is an argv
/// array spawned without a shell.

// MARK: - Entry

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    agentspace-helper — the AgentSpace privileged helper

    Normally launched by launchd as \(helperMachServiceName); it is not
    meant to be run by hand. These modes exist for diagnosis:

      agentspace-helper --self-check     Report what this binary would do, and
                                         whether the environment is right. Makes
                                         no changes and needs no root.
      agentspace-helper --version        Print the version and exit.
      agentspace-helper --help           This text.

    The helper answers these operations over XPC, and nothing else:

      createUser                create a standard (never admin) agent account
      deleteUser                delete an agent account the helper itself created
      installWorker             install the worker LaunchAgent into a Space
      removeWorker              remove it again
      prepareRuntimeDirectory   create and permission the Space's runtime dir
      startWorker / stopWorker  start or stop the Space's worker
      sessionInfo               is there a GUI session for a Space?
      helperStatus              version, whether it is root, which accounts exist
    """)
    exit(0)
}

if arguments.contains("--version") {
    print("agentspace-helper \(helperVersion) (protocol \(agentSpaceProtocolVersion))")
    exit(0)
}

if arguments.contains("--self-check") {
    let report = HelperSelfCheck.run()
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report.json), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    } else {
        print(report.render())
    }
    // Refusing to claim health when something is wrong is the whole point. It
    // exits non-zero, so a packaging script can gate on it.
    exit(report.ok ? 0 : 1)
}

// MARK: - XPC service

/// The connection delegate — where the caller is checked.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let log = HelperLog()
    let service = HelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        guard let peer = CodeSigningRequirement.verifiedPeer(pid: pid) else {
            // Logged, not silently dropped: at 3am the question is "why did the app
            // not create a Space", and the answer needs to be in the log. The
            // refusal is the security event, so it is logged at error level.
            log.error("refused a connection from pid \(pid): \(CodeSigningRequirement.describe())")
            return false
        }
        log.info("accepted \(peer.summary)")
        // Re-checked per operation as well as here, so occupying the pid once is
        // not enough to get a privileged operation performed.
        service.verifiedPeerPIDs.add(pid)
        connection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

guard geteuid() == 0 else {
    // Running as the wrong user is a configuration mistake, and proceeding would
    // produce confusing partial failures later. Exit 77 matches the worker's
    // "wrong privilege" code so there is one number to remember.
    FileHandle.standardError.write(Data("""
    agentspace-helper must run as root (currently euid \(geteuid())).

    It is launched by launchd from the AgentSpace app bundle. If you are seeing
    this, the LaunchDaemon is misconfigured — install it from the app, or
    `launchctl print system/\(helperMachServiceName)` to see what launchd thinks.

    """.utf8))
    exit(77)
}

let log = HelperLog()
log.info("helper \(helperVersion) starting as uid \(geteuid())")

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: helperMachServiceName)
listener.delegate = delegate
listener.resume()

log.info("listening on \(helperMachServiceName) with requirement: \(CodeSigningRequirement.enforcedRequirement)")

// `listener.resume()` returns immediately and the run loop drives the callbacks.
// A helper that exited here would accept no connections at all, so this is load
// bearing rather than ceremonial.
RunLoop.current.run()
