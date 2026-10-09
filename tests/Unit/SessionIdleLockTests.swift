import Foundation
import XCTest
import AgentSpaceCore

/// The rule behind "an agent desktop stays drivable while its Worker is
/// installed", and the reversibility that keeps it from being a permanent edit
/// of someone's macOS account.
///
/// The measured failure this exists for: AgentUse's own `loginwindow` raised a
/// screensaver lock after ~20 minutes of machine-wide input silence
/// (`reason: 4` = `kLWLockFromScreenSaverOtherLaunch`), which set
/// `CGSSessionScreenIsLocked` and made the desktop undrivable — unrecoverable
/// without a password, which AgentSpace must never hold (AGENTS.md §7).
final class SessionIdleLockTests: XCTestCase {

    // MARK: The decision

    func testTheScreensaverIsTurnedOffRatherThanShortened() {
        XCTAssertEqual(SessionIdleLock.apply(current: nil), .value(SessionIdleLock.never))
        XCTAssertEqual(SessionIdleLock.apply(current: 1200), .value(SessionIdleLock.never))
        // 0 is what System Settings' "Never" writes; any other number only
        // delays the same lock.
        XCTAssertEqual(SessionIdleLock.never, 0)
    }

    func testAnAccountThatAlreadyNeverScreensavesIsLeftAlone() {
        XCTAssertEqual(SessionIdleLock.apply(current: SessionIdleLock.never), .unchanged)
    }

    func testRestoringAnAbsentKeyRemovesItInsteadOfInventingAValue() {
        // The common case: a standard account has no screensaver domain at all,
        // so "back the way it was" means the key must not exist afterwards.
        XCTAssertEqual(SessionIdleLock.restore(recorded: nil), .removeKey)
        XCTAssertEqual(SessionIdleLock.restore(recorded: 1200), .value(1200))
    }

    // MARK: The runner

    /// A preference store that records instead of writing, so the ordering
    /// questions — record before write, restore once, never touch what was not
    /// ours — are answerable without editing this machine's preferences.
    private final class FakeStore {
        var current: Int?
        private(set) var writes: [ScreensaverWrite] = []
        var succeeds = true

        init(current: Int?) { self.current = current }

        var store: SessionIdleLockRunner.Store {
            SessionIdleLockRunner.Store(
                read: { [weak self] in self?.current },
                write: { [weak self] change in
                    guard let self, self.succeeds else { return false }
                    self.writes.append(change)
                    switch change {
                    case .value(let seconds): self.current = seconds
                    case .removeKey: self.current = nil
                    case .unchanged: break
                    }
                    return true
                })
        }
    }

    private func runner(_ fake: FakeStore) throws -> (SessionIdleLockRunner, String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionIdleLockTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let recordPath = directory.appendingPathComponent("screensaver.json").path
        return (SessionIdleLockRunner(recordPath: recordPath, store: fake.store), recordPath)
    }

    func testTheRunnerRecordsWhatItFoundAndPutsItBack() throws {
        let fake = FakeStore(current: 1200)
        let (lock, recordPath) = try runner(fake)

        XCTAssertNotNil(lock.apply())
        XCTAssertEqual(fake.writes, [.value(0)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordPath))

        XCTAssertEqual(lock.restore(), "restored the account's screensaver to 1200s")
        XCTAssertEqual(fake.writes, [.value(0), .value(1200)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath),
                       "a restored account must not keep a record of a change that is gone")
    }

    func testAnAccountWithNoScreensaverKeyComesBackWithNone() throws {
        // Measured: agentuse had no `com.apple.screensaver` ByHost domain at all
        // before AgentSpace, so restoring must delete the key rather than leave
        // an explicit value macOS would now honour differently.
        let fake = FakeStore(current: nil)
        let (lock, _) = try runner(fake)

        XCTAssertNotNil(lock.apply())
        XCTAssertEqual(fake.current, 0)
        XCTAssertEqual(lock.restore(), "removed the screensaver interval AgentSpace had set")
        XCTAssertNil(fake.current)
    }

    func testAWorkerThatInheritsARecordStillRestoresTheTrueOriginal() throws {
        // Worker updates and crashes are routine. The second Worker finds a
        // screensaver that is already off, so it writes nothing — but the record
        // the first one left still says what the account was, and stopping must
        // put *that* back rather than leave the account off forever.
        let fake = FakeStore(current: 1200)
        let (first, recordPath) = try runner(fake)
        XCTAssertNotNil(first.apply())

        let second = SessionIdleLockRunner(recordPath: recordPath, store: fake.store)
        XCTAssertNil(second.apply(), "nothing to do, so nothing to report")
        XCTAssertEqual(second.restore(), "restored the account's screensaver to 1200s")
        XCTAssertEqual(fake.current, 1200)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath))
        XCTAssertNil(first.restore(), "the record is gone, so a second stop changes nothing")
    }

    func testStoppingAWorkerThatNeverWroteLeavesThePreferenceAlone() throws {
        let fake = FakeStore(current: 600)
        let (lock, _) = try runner(fake)

        XCTAssertNil(lock.restore())
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertEqual(fake.current, 600)
    }

    func testAPersonsOwnNeverSettingIsNotRewrittenOrClaimed() throws {
        let fake = FakeStore(current: SessionIdleLock.never)
        let (lock, recordPath) = try runner(fake)

        XCTAssertNil(lock.apply())
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath),
                       "AgentSpace must not claim a change it did not make")
        XCTAssertNil(lock.restore())
        XCTAssertEqual(fake.current, 0)
    }

    func testAFailedPreferenceWriteIsReportedAndKeepsTheRecordForTheNextStop() throws {
        // The record is written before the preference, so a failure cannot
        // strand the account with a changed value and nothing to restore it
        // from; and the failure is said out loud rather than swallowed.
        let fake = FakeStore(current: 1200)
        fake.succeeds = false
        let (lock, recordPath) = try runner(fake)

        XCTAssertEqual(lock.apply(), "screensaver is still on: could not write com.apple.screensaver/idleTime")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordPath))
    }

    // MARK: Where it runs

    /// The step must happen in a real installation only, and *must* happen there.
    ///
    /// `WorkerHarness` starts real worker binaries against a temporary runtime
    /// root, so a resolved-root test is the right exemption. The wrong test for
    /// the same idea was in this file first: `AGENTSPACE_ROOT` is not absent in
    /// production — measured 2026-10-09 with `ps eww` against the installed
    /// worker, launchd gives it `AGENTSPACE_ROOT=/Library/Application
    /// Support/AgentSpace`, the production path — so a guard on the variable's
    /// absence read as "only in a real installation" while skipping exactly that
    /// installation. The same shape of bug sat in the worker's TCC-asking block.
    func testTheRealInstallationGuardIsTheResolvedRootNotAnAbsentVariable() throws {
        let worker = try source("native/AgentSpaceWorker/Sources/AgentSpaceWorker/main.swift")
        XCTAssertTrue(
            worker.contains("if paths.root == RuntimePaths.root {"),
            "the idle-lock step must be exempt for a temporary root and run for the production one")
        XCTAssertTrue(
            worker.contains("if paths.root == RuntimePaths.root, desktopReadiness.isReady {"),
            "the permission-asking step must use the same resolved-root test")
        XCTAssertFalse(
            worker.contains("rootOverride == nil"),
            "absence of AGENTSPACE_ROOT does not mean a test harness: launchd sets it on the installed worker")
        XCTAssertTrue(
            worker.contains("idleLock?.restore()"),
            "stopping the Worker must put the account's screensaver back")
    }

    /// The one mistake this code cannot make quietly: `CFPreferences` takes
    /// `(key, applicationID, userName, hostName)`. With the last two swapped
    /// every call still compiles and still "succeeds" — it just reads a domain
    /// nobody uses. Measured 2026-10-09 with a probe run as the agent user: the
    /// swapped order answered `nil` against a ByHost value of 0 that
    /// `defaults -currentHost` read back.
    func testEveryPreferenceCallAsksForTheCurrentUserBeforeTheCurrentHost() throws {
        let lines = try source("shared/Core/Sources/AgentSpaceCore/SessionIdleLockRunner.swift")
            .split(separator: "\n").map(String.init)
        var hostArguments = 0
        for (index, line) in lines.enumerated() where line.contains("kCFPreferencesCurrentHost") {
            hostArguments += 1
            XCTAssertTrue(lines[index - 1].contains("kCFPreferencesCurrentUser"),
                          "line \(index + 1): the host argument must follow the user argument")
        }
        XCTAssertEqual(hostArguments, 4, "one read, two writes and one synchronize")
    }

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // tests/Unit
            .deletingLastPathComponent()   // tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("\(relativePath) is not in this checkout")
        }
        return text
    }
}
