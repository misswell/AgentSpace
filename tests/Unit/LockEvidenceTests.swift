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
/// its own log — which makes three properties worth pinning: an unreadable field
/// must read as unreadable, the diagnostic must stay a *read*, and the line must
/// arrive in the log intact rather than redacted into nothing.
final class LockEvidenceTests: XCTestCase {

    func testNothingIsInventedWhenNothingCouldBeRead() {
        let evidence = LockEvidence(screenIsLocked: true)
        XCTAssertEqual(
            evidence.line,
            "screenIsLocked=yes lockedAt=unset secureInputPID=unset onConsole=unknown "
                + "idleTime=unset unlockNeedsPasscode=unset passcodeDelay=unset")
    }

    func testThePreventedIdleClassStillShowsUpAsADisconnectLock() {
        // The shape the log has to distinguish: the account's screensaver is off,
        // yet the desktop locked seconds ago with the unlock UI holding secure
        // input. Nothing here prevented that, and nothing here could have.
        let evidence = LockEvidence(
            screenIsLocked: true,
            lockedAt: 1_791_510_767,
            secureInputPID: 28160,
            onConsole: false,
            screensaverIdleTime: 0,
            askForPassword: 1,
            askForPasswordDelay: nil)
        XCTAssertTrue(evidence.line.contains("secureInputPID=28160 onConsole=no idleTime=0"),
                      "the three fields that name the class: \(evidence.line)")
        XCTAssertTrue(evidence.line.contains("unlockNeedsPasscode=1"),
                      "a required passcode must be visible: \(evidence.line)")
        // The wall time is rendered in the reader's own zone, so only its shape
        // is pinned here; the value itself is the next test's job.
        XCTAssertTrue(evidence.line.contains("lockedAt=2026-10-0"),
                      "an absolute start time, not a duration: \(evidence.line)")
    }

    /// `CGSSessionScreenLockedTime` is an epoch, and the first released build
    /// printed it as a duration: a lock that began at 09:52:47 read
    /// `lockedFor=1791510767s` — "locked for 57 years" — in the AgentUse log on
    /// 2026-10-09. A number nobody can read is a number nobody checks.
    func testTheLockTimeIsAnAbsoluteClockTime() {
        let evidence = LockEvidence(screenIsLocked: true, lockedAt: 1_791_510_767)
        let pattern = #"lockedAt=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}( |$)"#
        XCTAssertTrue(evidence.line.range(of: pattern, options: .regularExpression) != nil,
                      evidence.line)
        XCTAssertFalse(evidence.line.contains("1791510767"),
                       "the raw epoch must not be the readable field: \(evidence.line)")
    }

    /// The line reaches `os_log` through `Redaction.scrubString`, which rewrites
    /// any `password=<value>` to `password=<redacted>`. That is correct for every
    /// other line in this product and destroyed this one: the released build
    /// logged `askForpassword=<redacted>` and the field it exists to report was
    /// gone. Renaming the *label* is the fix; the value is one bit of a
    /// preference, never a secret.
    func testTheLineSurvivesTheLogRedactor() {
        let evidence = LockEvidence(
            screenIsLocked: true, lockedAt: 1_791_510_767, secureInputPID: 28160,
            onConsole: false, screensaverIdleTime: 0, askForPassword: 1, askForPasswordDelay: 60)
        XCTAssertEqual(Redaction.scrubString(evidence.line), evidence.line,
                       "the diagnostic must arrive intact: \(Redaction.scrubString(evidence.line))")
    }

    func testAnUnlockIsLoggedInTheSameShapeWithTheBitCleared() {
        let evidence = LockEvidence(
            screenIsLocked: false, lockedAt: nil, secureInputPID: nil,
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
