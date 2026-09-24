import Darwin
import Foundation
import AgentSpaceUpdaterSupport

/// Replaces the running app with a verified copy and relaunches it.
///
/// This process is deliberately dumb. Everything with a security decision in it
/// — which release, which digest, does the signature hold, is this AgentSpace —
/// is answered by the app before it launches this, and re-checked by nothing
/// here. What is left is the one operation that cannot happen while the old
/// binary is mapped: swapping the bundle and starting the new one.
///
/// It only ever touches the two paths it was given, plus the scratch names
/// derived from them, and it writes its reasoning to a log because a failed
/// update that says nothing is indistinguishable from one that never ran.
private enum UpdaterError: Error {
    case invalidArguments
    case sourceMissing(URL)
    case parentDidNotExit
    case wrongDestination(URL)
    case executableMissing(URL)
    case launchFailed(String)
}

private func appendLog(_ message: String, to url: URL) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let handle = try? FileHandle(forWritingTo: url) else {
        try? Data(line.utf8).write(to: url, options: .atomic)
        return
    }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: Data(line.utf8))
}

/// The app must be gone before its bundle is swapped: a running main executable
/// is still mapped from those bytes, and an app that is still alive would write
/// its own state over the copy that just landed.
private func waitForParent(_ pid: pid_t, logURL: URL) throws {
    for _ in 0..<600 {
        if kill(pid, 0) != 0 { return }
        usleep(100_000)
    }
    appendLog("parent \(pid) was still running after 60s; leaving \(AgentSpaceIdentity.appBundleName) alone", to: logURL)
    throw UpdaterError.parentDidNotExit
}

private func launch(_ application: URL, logURL: URL) throws {
    let name = Bundle(url: application)?
        .object(forInfoDictionaryKey: "CFBundleExecutable") as? String
    let executableURL = UpdaterLaunchPlan.directExecutableURL(
        for: application,
        executableName: name ?? AgentSpaceIdentity.executableName
    )
    guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
        throw UpdaterError.executableMissing(executableURL)
    }
    let process = Process()
    process.executableURL = executableURL
    process.currentDirectoryURL = application.deletingLastPathComponent()
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        throw UpdaterError.launchFailed(error.localizedDescription)
    }
    appendLog("relaunched \(executableURL.path)", to: logURL)
}

private func install(_ arguments: UpdaterLaunchPlan.Arguments) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: arguments.sourceApplication.path) else {
        throw UpdaterError.sourceMissing(arguments.sourceApplication)
    }
    let token = UUID().uuidString
    let incoming = UpdaterLaunchPlan.incomingApplicationURL(
        replacing: arguments.destinationApplication, token: token)
    let backup = UpdaterLaunchPlan.backupApplicationURL(
        replacing: arguments.destinationApplication, token: token)
    var swapped = false

    do {
        try fileManager.copyItem(at: arguments.sourceApplication, to: incoming)
        _ = try fileManager.replaceItemAt(
            arguments.destinationApplication,
            withItemAt: incoming,
            backupItemName: backup.lastPathComponent,
            options: .withoutDeletingBackupItem
        )
        swapped = true
        guard Bundle(url: arguments.destinationApplication)?
            .bundleIdentifier == AgentSpaceIdentity.bundleIdentifier else {
            // Something AgentSpace-shaped is now where the app was, and it is not
            // AgentSpace. That is exactly what the backup is for.
            throw UpdaterError.wrongDestination(arguments.destinationApplication)
        }
        do {
            try launch(arguments.destinationApplication, logURL: arguments.logURL)
        } catch {
            appendLog("launch failed (\(error)), restoring the previous copy", to: arguments.logURL)
            restoreBackup(backup, arguments: arguments)
            throw error
        }
        try? fileManager.removeItem(at: backup)
        appendLog(
            "update installed at \(arguments.destinationApplication.path). The installed "
            + "privileged helper and the worker it installed are outside this bundle: "
            + "the relaunched app checks their versions and updates mismatches through the helper.",
            to: arguments.logURL
        )
    } catch {
        try? fileManager.removeItem(at: incoming)
        // Past the swap, an unverified bundle sitting at the app's path is worse
        // than the old one: it is what the user finds when they click the Dock
        // icon. Below the swap nothing was disturbed, except that a bundle that
        // vanished mid-move has to be put back by hand.
        if swapped, fileManager.fileExists(atPath: backup.path) {
            appendLog("restoring the previous copy after a failed install", to: arguments.logURL)
            restoreBackup(backup, arguments: arguments)
        } else if !fileManager.fileExists(atPath: arguments.destinationApplication.path),
                  fileManager.fileExists(atPath: backup.path) {
            appendLog("restoring the previous copy after a failed install", to: arguments.logURL)
            try? fileManager.moveItem(at: backup, to: arguments.destinationApplication)
        }
        throw error
    }
}

/// Puts the pre-update bundle back and brings the old app on screen, so a failed
/// update ends with a working AgentSpace rather than a path with nothing on it.
private func restoreBackup(
    _ backup: URL,
    arguments: UpdaterLaunchPlan.Arguments
) {
    let fileManager = FileManager.default
    _ = try? fileManager.replaceItemAt(
        arguments.destinationApplication, withItemAt: backup)
    try? launch(arguments.destinationApplication, logURL: arguments.logURL)
}

guard let plan = UpdaterLaunchPlan.parse(CommandLine.arguments) else {
    appendLog(
        "updater called with \(CommandLine.arguments.count) values; expected 7",
        to: UpdaterLaunchPlan.logURL(homeDirectory: FileManager.default.homeDirectoryForCurrentUser))
    exit(2)
}

var failure: Error?
do {
    appendLog("waiting for parent \(plan.parentPID)", to: plan.logURL)
    try waitForParent(plan.parentPID, logURL: plan.logURL)
    try install(plan)
} catch {
    appendLog("update failed: \(error)", to: plan.logURL)
    failure = error
}

// Both scratch directories hold the downloaded archive and a copy of this
// executable. Neither survives the run, including the failed one.
try? FileManager.default.removeItem(at: plan.stagingDirectory)
try? FileManager.default.removeItem(at: plan.helperDirectory)

if failure != nil { exit(1) }
