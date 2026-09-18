import Foundation
import AgentSpaceCore

/// Shell execution as the AgentSpace user. Plan §23.
///
/// The command runs with the worker's own uid — the standard, non-admin
/// AgentSpace user — and the worker never elevates. There is no `sudo`, no
/// helper round-trip and no root path into this function.
///
/// Output is returned buffered (`stdout`, `stderr`, `exitCode`, `duration`)
/// rather than streamed. That matches the shape the plan specifies and keeps
/// the transport to one request per connection; a streaming variant can be
/// added later without changing this contract.
enum ShellExec {

    struct Result {
        var exitCode: Int32?
        var signal: String?
        var timedOut: Bool
        var stdout: String
        var stderr: String
        var durationMs: Int
        var truncated: Bool

        var json: JSONValue {
            .obj([
                "exitCode": exitCode.map { JSONValue.int(Int($0)) } ?? .null,
                "signal": signal.map { JSONValue.string($0) } ?? .null,
                "timedOut": .bool(timedOut),
                "stdout": .string(stdout),
                "stderr": .string(stderr),
                "duration": .int(durationMs),
                "truncated": .bool(truncated),
            ])
        }
    }

    /// Output cap. A runaway command must not be able to make the worker
    /// allocate without bound; the tail is what matters for diagnosis.
    static let maxOutputBytes = 4 << 20

    /// Default search path when the caller supplies none. launchd's own `PATH`
    /// is too minimal to find `npx`, so this is written out explicitly.
    static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func run(
        command: String,
        cwd: String?,
        environment: [String: String],
        timeoutMs: Int,
        stdin: String? = nil
    ) throws -> Result {
        if let refusal = ExecGuard.refusal(for: command) { throw refusal }

        let started = Date()

        // `argv[0]` is resolved against the *effective* PATH explicitly:
        // `posix_spawnp` searches the parent's PATH, not the child
        // environment's, so leaving it implicit would run a different binary
        // than the environment describes.
        let effectivePath = environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? defaultPath
        var childEnvironment = environment
        childEnvironment["PATH"] = effectivePath

        let argv = ["/bin/sh", "-c", command]
        var cArguments = argv.map { strdup($0) }
        cArguments.append(nil)
        defer { for pointer in cArguments where pointer != nil { free(pointer) } }

        var cEnvironment = childEnvironment.map { strdup("\($0.key)=\($0.value)") }
        cEnvironment.append(nil)
        defer { for pointer in cEnvironment where pointer != nil { free(pointer) } }

        var stdoutPipe: [Int32] = [0, 0]
        var stderrPipe: [Int32] = [0, 0]
        var stdinPipe: [Int32] = [0, 0]
        guard pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0, pipe(&stdinPipe) == 0 else {
            throw AgentSpaceError(code: .internalError, message: "could not create pipes: \(String(cString: strerror(errno)))")
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, stdinPipe[0], STDIN_FILENO)
        for fd in [stdoutPipe[0], stdoutPipe[1], stderrPipe[0], stderrPipe[1], stdinPipe[0], stdinPipe[1]] {
            posix_spawn_file_actions_addclose(&fileActions, fd)
        }
        if let cwd {
            // The undecorated `posix_spawn_file_actions_addchdir` is not
            // available on every SDK this source may be built against; the
            // `_np` spelling is the one that exists.
            posix_spawn_file_actions_addchdir_np(&fileActions, cwd)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Own process group, so a timeout can signal the whole tree rather than
        // just `sh`.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        // Connections are served on libdispatch worker threads, which run with
        // almost every signal blocked, and both the mask and ignored
        // dispositions survive `exec`. Without these the child would inherit
        // SIGTERM as *ignored* and a timeout would hang until SIGKILL.
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setsigmask(&attributes, &emptyMask)
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        sigaddset(&defaultSignals, SIGTERM)
        sigaddset(&defaultSignals, SIGINT)
        sigaddset(&defaultSignals, SIGPIPE)
        sigaddset(&defaultSignals, SIGHUP)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, "/bin/sh", &fileActions, &attributes, cArguments, cEnvironment)
        guard spawnResult == 0 else {
            for fd in [stdoutPipe[0], stdoutPipe[1], stderrPipe[0], stderrPipe[1], stdinPipe[0], stdinPipe[1]] {
                close(fd)
            }
            throw AgentSpaceError(
                code: .internalError,
                message: "could not spawn /bin/sh: \(String(cString: strerror(spawnResult)))")
        }

        close(stdoutPipe[1]); close(stderrPipe[1]); close(stdinPipe[0])

        if let stdin {
            _ = stdin.withCString { pointer in
                write(stdinPipe[1], pointer, strlen(pointer))
            }
        }
        close(stdinPipe[1])

        // Drain both pipes concurrently: reading one to completion first
        // deadlocks as soon as the child fills the other one's buffer.
        let outBuffer = LockedBuffer(limit: maxOutputBytes)
        let errBuffer = LockedBuffer(limit: maxOutputBytes)
        let group = DispatchGroup()
        for (fd, buffer) in [(stdoutPipe[0], outBuffer), (stderrPipe[0], errBuffer)] {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                buffer.drain(fd: fd)
                close(fd)
            }
        }

        // Wait with a deadline.
        var status: Int32 = 0
        var timedOut = false
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while true {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { break }
            if result < 0 && errno == ECHILD { break }
            if Date() >= deadline {
                timedOut = true
                killProcessGroup(pid)
                // Grace, then escalate.
                usleep(2_000_000)
                if waitpid(pid, &status, WNOHANG) != pid {
                    kill(-pid, SIGKILL)
                    _ = waitpid(pid, &status, 0)
                }
                break
            }
            usleep(20_000)
        }

        // The reader threads finish when the write ends close.
        _ = group.wait(timeout: .now() + 5)

        let durationMs = Int(Date().timeIntervalSince(started) * 1000)
        let (exitCode, signalName) = decode(status: status, timedOut: timedOut)

        return Result(
            exitCode: exitCode,
            signal: signalName,
            timedOut: timedOut,
            stdout: outBuffer.string,
            stderr: errBuffer.string,
            durationMs: durationMs,
            truncated: outBuffer.truncated || errBuffer.truncated)
    }

    private static func killProcessGroup(_ pid: pid_t) {
        // The child called setsid, so it leads its own group; signalling the
        // negative pid reaches everything it started.
        kill(-pid, SIGTERM)
        kill(pid, SIGTERM)
    }

    // The `WIFEXITED` family are function-like C macros, which Swift's Clang
    // importer does not surface. These are the definitions from `<sys/wait.h>`
    // transcribed, so the decode is explicit rather than guessed.
    private static let waitStopped: Int32 = 0o177

    private static func waitStatus(_ status: Int32) -> Int32 { status & 0o177 }
    private static func waitExited(_ status: Int32) -> Bool { waitStatus(status) == 0 }
    private static func waitExitStatus(_ status: Int32) -> Int32 { (status >> 8) & 0x000000ff }
    private static func waitSignaled(_ status: Int32) -> Bool {
        let s = waitStatus(status)
        return s != waitStopped && s != 0
    }
    private static func waitTermSig(_ status: Int32) -> Int32 { waitStatus(status) }

    private static func decode(status: Int32, timedOut: Bool) -> (Int32?, String?) {
        // A timeout is never mistakable for a normal exit, even if the child
        // happened to exit cleanly inside the grace period.
        if timedOut { return (nil, "SIGTERM") }
        if waitExited(status) { return (waitExitStatus(status), nil) }
        if waitSignaled(status) {
            return (nil, signalName(waitTermSig(status)))
        }
        return (nil, nil)
    }

    static func signalName(_ signal: Int32) -> String {
        switch signal {
        case SIGTERM: return "SIGTERM"
        case SIGKILL: return "SIGKILL"
        case SIGINT: return "SIGINT"
        case SIGSEGV: return "SIGSEGV"
        case SIGABRT: return "SIGABRT"
        case SIGPIPE: return "SIGPIPE"
        case SIGHUP: return "SIGHUP"
        default: return "SIG\(signal)"
        }
    }
}

/// A byte buffer two threads can touch: one drains a pipe into it, the caller
/// reads the string after joining.
final class LockedBuffer {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int
    private(set) var truncated = false

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        let remaining = limit - data.count
        if remaining <= 0 { truncated = true; return }
        if chunk.count > remaining {
            data.append(chunk.prefix(remaining))
            truncated = true
        } else {
            data.append(chunk)
        }
    }

    /// Read until EOF. Runs on its own thread.
    func drain(fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                append(Data(chunk[0..<n]))
                continue
            }
            if n < 0 && errno == EINTR { continue }
            return
        }
    }

    var string: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
    }

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return data.isEmpty
    }
}
