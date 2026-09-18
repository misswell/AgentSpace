import Foundation
import AgentSpaceCore

/// Runs an argv array and captures its output.
///
/// `posix_spawn`, not `Process` and emphatically not `system()` or `/bin/sh -c`.
/// With `posix_spawn` the executable and every argument are a separate C string:
/// there is no string to parse, so there is nothing to quote, escape, split, glob
/// or expand. That is the entire reason the helper can accept a display name
/// containing a space without it being a vulnerability.
///
/// It is also why `HelperCommand` returns `[[String]]` rather than `[String]`.
/// A security review of this daemon can read one file to see every command it is
/// capable of running.
enum CommandRunner {

    struct Result {
        var exitCode: Int32
        var standardOutput: String
        var standardError: String
        var spawnError: Int32?
        /// What was run, with arguments the daemon considers secret removed.
        var displayCommand: String

        var ok: Bool { spawnError == nil && exitCode == 0 }
    }

    /// Argument values that must never appear in a log line.
    ///
    /// The generated password, mostly. It is written to the Keychain and needs to
    /// stay there; a password in `log show` output is a password on disk in a
    /// world-readable store.
    static func redact(_ arguments: [String]) -> String {
        var out: [String] = []
        var suppressNext = false
        for argument in arguments {
            if suppressNext {
                out.append("<redacted>")
                suppressNext = false
                continue
            }
            out.append(argument)
            if argument == "-password" { suppressNext = true }
        }
        return out.joined(separator: " ")
    }

    static func run(_ arguments: [String], timeout: TimeInterval = 120) -> Result {
        var display = redact(arguments)
        guard let executable = arguments.first else {
            return Result(exitCode: -1, standardOutput: "", standardError: "no executable", spawnError: EINVAL, displayCommand: "")
        }

        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else {
            return Result(exitCode: -1, standardOutput: "", standardError: "pipe() failed", spawnError: errno, displayCommand: display)
        }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0]); close(outPipe[1])
            return Result(exitCode: -1, standardOutput: "", standardError: "pipe() failed", spawnError: errno, displayCommand: display)
        }

        // The child inherits only these two write ends. Anything else would hold
        // the read ends open past the child's exit and make the reads below hang
        // until the timeout — a self-inflicted denial of service.
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, errPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, outPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, errPipe[0])
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        argv.append(nil)
        defer { for pointer in argv where pointer != nil { free(pointer) } }

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, executable, &fileActions, nil, &argv, environ)
        close(outPipe[1])
        close(errPipe[1])

        guard spawnResult == 0 else {
            close(outPipe[0]); close(errPipe[0])
            return Result(exitCode: -1, standardOutput: "", standardError: "posix_spawn failed (\(spawnResult))", spawnError: spawnResult, displayCommand: display)
        }

        // Read both pipes on separate queues. Reading them in sequence deadlocks
        // as soon as the child fills the pipe it is not being read from.
        let group = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()
        let lock = NSLock()

        for (fd, isStdout) in [(outPipe[0], true), (errPipe[0], false)] {
            DispatchQueue.global().async(group: group) {
                var buffer = [UInt8](repeating: 0, count: 8192)
                while true {
                    let count = read(fd, &buffer, buffer.count)
                    if count > 0 {
                        lock.lock()
                        if isStdout { stdoutData.append(contentsOf: buffer[0..<count]) }
                        else { stderrData.append(contentsOf: buffer[0..<count]) }
                        lock.unlock()
                    } else if count == 0 || errno != EINTR {
                        break
                    }
                }
                close(fd)
            }
        }

        // Bounded wait: a helper that blocks forever on a hung `sysadminctl` is a
        // helper that stops answering, and root operations must not be able to
        // wedge the app.
        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        var exitCode: Int32 = -1
        var timedOut = false
        while true {
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid { break }
            if waited < 0 { break }
            if Date() > deadline {
                timedOut = true
                kill(pid, SIGKILL)
                waitpid(pid, &status, 0)
                break
            }
            usleep(20_000)
        }

        group.wait()

        if timedOut {
            display += "   [killed after \(Int(timeout))s]"
            exitCode = -2
        } else if (status & 0x7F) == 0 {
            exitCode = (status >> 8) & 0xFF
        } else {
            exitCode = -1
        }

        return Result(
            exitCode: exitCode,
            standardOutput: String(decoding: stdoutData, as: UTF8.self),
            standardError: String(decoding: stderrData, as: UTF8.self),
            spawnError: nil,
            displayCommand: display)
    }
}

/// Reads the machine's local accounts.
///
/// Used both to validate a request and to answer "does this account exist", so it
/// runs before anything destructive. `dscl . -list /Users` is the supported way
/// and needs no root, but this runs as root anyway.
enum AccountDirectory {
    static func existingAccounts() -> Set<String> {
        let result = CommandRunner.run([HelperCommand.dscl, ".", "-list", "/Users"], timeout: 30)
        guard result.ok else { return [] }
        return Set(
            result.standardOutput
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
    }

    static func homeDirectory(of username: String) -> String? {
        let result = CommandRunner.run([HelperCommand.dscl, ".", "-read", "/Users/\(username)", "NFSHomeDirectory"], timeout: 30)
        guard result.ok else { return nil }
        // Output looks like: `NFSHomeDirectory: /Users/foo`
        return result.standardOutput
            .split(separator: "\n")
            .first { $0.hasPrefix("NFSHomeDirectory:") }?
            .split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespaces)
    }
}
