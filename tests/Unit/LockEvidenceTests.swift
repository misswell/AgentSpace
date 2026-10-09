import Foundation
import XCTest
import AgentSpaceCore

/// The line a released build leaves behind when an agent desktop gets locked.
///
/// It exists because the two lock classes measured in AgentUse on 2026-10-09 are
/// indistinguishable in the interface and different in what can be done about
/// them (`SessionIdleLock` prevents the idle one; a Screen Sharing disconnect
/// lock is Apple locking the session directly). The owner of a real Mac cannot
/// run a probe binary in the agent account, so the build has to answer it from
/// its own log — which makes two properties worth pinning: an unreadable field
/// must read as unreadable, and the diagnostic must stay a *read*.
final class LockEvidenceTests: XCTestCase {

    func testNothingIsInventedWhenNothingCouldBeRead() {
        let evidence = LockEvidence(screenIsLocked: true)
        XCTAssertEqual(
            evidence.line,
            "screenIsLocked=yes lockedFor=unset secureInputPID=unset onConsole=unknown "
                + "idleTime=unset askForPassword=unset askForPasswordDelay=unset")
    }

    func testThePreventedIdleClassStillShowsUpAsADisconnectLock() {
        // The shape the log has to distinguish: the account's screensaver is off,
        // yet the desktop locked seconds ago with the unlock UI holding secure
        // input. Nothing here prevented that, and nothing here could have.
        let evidence = LockEvidence(
            screenIsLocked: true,
            lockedForSeconds: 6,
            secureInputPID: 28160,
            onConsole: false,
            screensaverIdleTime: 0,
            askForPassword: 1,
            askForPasswordDelay: nil)
        XCTAssertEqual(
            evidence.line,
            "screenIsLocked=yes lockedFor=6s secureInputPID=28160 onConsole=no "
                + "idleTime=0 askForPassword=1 askForPasswordDelay=unset")
    }

    func testAnUnlockIsLoggedInTheSameShapeWithTheBitCleared() {
        let evidence = LockEvidence(
            screenIsLocked: false, lockedForSeconds: nil, secureInputPID: nil,
            onConsole: false, screensaverIdleTime: 0, askForPassword: nil,
            askForPasswordDelay: nil)
        XCTAssertTrue(evidence.line.hasPrefix("screenIsLocked=no "))
        XCTAssertFalse(evidence.line.contains("\n"), "os_log lines are greppable or they are useless")
    }

    /// The rule this diagnostic must not quietly break: `askForPassword` is read
    /// to explain a lock, and writing it would be AgentSpace deciding that an
    /// account's lock screen no longer needs its password — the one thing
    /// AGENTS.md §7 forbids around explicit login.
    func testAskForPasswordIsOnlyEverRead() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // tests/Unit
            .deletingLastPathComponent()   // tests
            .deletingLastPathComponent()   // repo root
        var offenders: [String] = []
        for directory in ["shared", "native", "apps"] {
            let url = root.appendingPathComponent(directory)
            guard let files = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: nil, errorHandler: { _, _ in true }) else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n").map(String.init)
                where line.contains("askForPassword") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    if line.contains("SetValue") || line.contains("removeValue") || line.contains("Synchronize") {
                        offenders.append("\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "askForPassword must stay read-only: \(offenders)")
    }
}
