import Foundation
import XCTest
import AgentSpaceCore

/// The rule behind "an agent desktop stays drivable while its Worker is
/// installed", and the reversibility that keeps it from being a permanent edit
/// of someone's macOS account.
///
/// Two measured failures this exists for, both raised in the AgentUse account.
/// AgentUse's own `loginwindow` took a screensaver wallpaper assertion after ~20
/// minutes of machine-wide input silence and locked the desktop 32 seconds later
/// (`reason: 4` = `kLWLockFromScreenSaverOtherLaunch`) — that is `idleTime`. And on
/// 2026-10-10, with `idleTime=0` already pinned, closing the Screen Sharing window
/// locked it again 40 seconds later, from `SACLockScreenImmediate:` on the host
/// side — that is `askForPasswordDelay`. Both end in the same
/// `CGSSessionScreenIsLocked` bit, which makes the desktop undrivable and is
/// unrecoverable without a password AgentSpace must never hold (AGENTS.md §7).
final class SessionIdleLockTests: XCTestCase {

    // MARK: The decision

    func testNeitherTriggerIsEverRewrittenWhenItAlreadySaysNever() {
        XCTAssertEqual(SessionIdleLock.policy[0].apply(current: nil), .value(SessionIdleLock.never))
        XCTAssertEqual(SessionIdleLock.policy[0].apply(current: 1200), .value(SessionIdleLock.never))
        XCTAssertEqual(SessionIdleLock.policy[0].apply(current: SessionIdleLock.never), .unchanged)
        XCTAssertEqual(SessionIdleLock.policy[1].apply(current: 5), .value(SessionIdleLock.passwordDelayNever))
        XCTAssertEqual(SessionIdleLock.policy[1].apply(current: nil), .value(SessionIdleLock.passwordDelayNever))
        // 0 is what System Settings' "Never" writes; any other number only
        // delays the same lock.
        XCTAssertEqual(SessionIdleLock.never, 0)
    }

    func testRestoringAnAbsentKeyRemovesItInsteadOfInventingAValue() {
        // The common case: a standard account has no screensaver domain at all,
        // so "back the way it was" means the key must not exist afterwards.
        XCTAssertEqual(SessionIdleLock.restore(recorded: nil), .removeKey)
        XCTAssertEqual(SessionIdleLock.restore(recorded: 1200), .value(1200))
    }

    func testTheKeyThatDecidesWhetherALockDemandsAPasswordIsNeverWritten() throws {
        // AGENTS.md §8: whether a lock needs a password at all is the account's own
        // decision; only *when* it stops demanding one is AgentSpace's, and only
        // while its Worker runs. The two keys are one substring apart, so the
        // assertion is on the quoted literal rather than the word.
        XCTAssertEqual(SessionIdleLock.policy.map(\.key), ["idleTime", "askForPasswordDelay"])
        for file in ["shared/Core/Sources/AgentSpaceCore/SessionIdleLockRunner.swift",
                     "shared/Core/Sources/AgentSpaceCore/SessionIdleLock.swift",
                     "native/AgentSpaceWorker/Sources/AgentSpaceWorker/main.swift"] {
            XCTAssertFalse(try source(file).contains(#""askForPassword""#),
                           "\(file) must read askForPassword at most, never name it as a write target")
        }
    }

    // MARK: The runner

    /// A preference store that records instead of writing, so the ordering
    /// questions — record before write, restore once, never touch what was not
    /// ours — are answerable without editing this machine's preferences.
    private final class FakeStore {
        /// The account's starting state, per key. `Screen` is the shorthand this
        /// file uses for the two keys the policy pins.
        var current: [String: Int?]
        private(set) var writes: [(key: String, change: ScreensaverWrite)] = []
        var succeeds = true
        /// Keys this store refuses to write, to exercise a partial failure.
        var failing: Set<String> = []

        init(_ current: [String: Int?] = [:]) {
            var seed: [String: Int?] = [SessionIdleLock.policy[0].key: nil,
                                        SessionIdleLock.policy[1].key: nil]
            for (key, value) in current { seed[key] = value }
            self.current = seed
        }

        var store: SessionIdleLockRunner.Store {
            SessionIdleLockRunner.Store(
                read: { [weak self] key in self?.current[key] ?? nil },
                write: { [weak self] key, change in
                    guard let self else { return false }
                    self.writes.append((key, change))
                    guard self.succeeds, !self.failing.contains(key) else { return false }
                    switch change {
                    case .value(let seconds): self.current[key] = seconds
                    case .removeKey: self.current[key] = nil
                    case .unchanged: break
                    }
                    return true
                })
        }
    }

    private let idleKey = SessionIdleLock.policy[0].key
    private let delayKey = SessionIdleLock.policy[1].key

    private func runner(_ fake: FakeStore) throws -> (SessionIdleLockRunner, String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionIdleLockTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let recordPath = directory.appendingPathComponent("screensaver.json").path
        return (SessionIdleLockRunner(recordPath: recordPath, store: fake.store), recordPath)
    }

    func testTheRunnerRecordsWhatItFoundAndPutsItBack() throws {
        let fake = FakeStore([idleKey: 1200, delayKey: 5])
        let (lock, recordPath) = try runner(fake)

        XCTAssertNotNil(lock.apply())
        XCTAssertEqual(fake.writes.map(\.key), [idleKey, delayKey])
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordPath))

        XCTAssertEqual(lock.restore(),
                       "restored the account's own lock settings: \(delayKey)→5, \(idleKey)→1200")
        XCTAssertEqual(fake.current[idleKey] ?? nil, 1200)
        XCTAssertEqual(fake.current[delayKey] ?? nil, 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath),
                       "a restored account must not keep a record of a change that is gone")
    }

    func testAnAccountWithNoScreensaverKeyComesBackWithNone() throws {
        // Measured: agentuse had no `com.apple.screensaver` ByHost domain at all
        // before AgentSpace, so restoring must delete both keys rather than leave
        // explicit values macOS would now honour differently.
        let fake = FakeStore()
        let (lock, _) = try runner(fake)

        XCTAssertNotNil(lock.apply())
        XCTAssertEqual(fake.current[idleKey] ?? nil, SessionIdleLock.never)
        XCTAssertEqual(fake.current[delayKey] ?? nil, SessionIdleLock.passwordDelayNever)
        XCTAssertEqual(lock.restore(),
                       "restored the account's own lock settings: \(delayKey)→absent, \(idleKey)→absent")
        XCTAssertNil(fake.current[idleKey] ?? nil)
        XCTAssertNil(fake.current[delayKey] ?? nil)
    }

    func testTheDelayIsIntMaxNotJustALargeNumber() throws {
        // `SACScreenLockEnabled:` compares the computed delay against `INT_MAX`
        // rather than against a threshold, so only that exact value answers NO.
        XCTAssertEqual(SessionIdleLock.passwordDelayNever, 2_147_483_647)
        let fake = FakeStore([delayKey: 86_400])
        let (lock, _) = try runner(fake)
        XCTAssertNotNil(lock.apply())
        XCTAssertEqual(fake.current[delayKey] ?? nil, SessionIdleLock.passwordDelayNever)
    }

    func testALegacyRecordFromAOneKeyWorkerStillRestoresTheInterval() throws {
        // 0.1.74–0.1.77 recorded `{"previous": 1200}` and pinned only `idleTime`.
        // A Worker updated over a running one finds the interval already pinned,
        // so the file it restores from *is* that legacy shape, and reading it as
        // "no originals" would strand the account pinned forever.
        let fake = FakeStore([idleKey: SessionIdleLock.never])
        let (lock, recordPath) = try runner(fake)
        try Data(#"{"previous":1200}"#.utf8).write(to: URL(fileURLWithPath: recordPath))

        // Only the new key is written — the interval already says never — and the
        // legacy original is carried into the new record rather than dropped.
        XCTAssertEqual(lock.apply(),
                       "the account will not lock itself: unset→\(SessionIdleLock.passwordDelayNever)")
        XCTAssertEqual(fake.writes.map(\.key), [delayKey])
        let text = try String(contentsOfFile: recordPath, encoding: .utf8)
        XCTAssertTrue(text.contains(idleKey), "the rewritten record must still hold idleTime: \(text)")

        XCTAssertEqual(lock.restore(),
                       "restored the account's own lock settings: \(delayKey)→absent, \(idleKey)→1200")
        XCTAssertEqual(fake.current[idleKey] ?? nil, 1200)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath))
    }

    func testAWorkerThatInheritsARecordStillRestoresTheTrueOriginal() throws {
        // Worker updates and crashes are routine. The second Worker finds both
        // triggers already pinned, so it writes nothing — but the record the first
        // one left still says what the account was, and stopping must put *that*
        // back rather than leave the account pinned forever.
        let fake = FakeStore([idleKey: 1200, delayKey: 30])
        let (first, recordPath) = try runner(fake)
        XCTAssertNotNil(first.apply())

        let second = SessionIdleLockRunner(recordPath: recordPath, store: fake.store)
        XCTAssertNil(second.apply(), "nothing to do, so nothing to report")
        XCTAssertEqual(second.restore(),
                       "restored the account's own lock settings: \(delayKey)→30, \(idleKey)→1200")
        XCTAssertEqual(fake.current[idleKey] ?? nil, 1200)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath))
        XCTAssertNil(first.restore(), "the record is gone, so a second stop changes nothing")
    }

    func testStoppingAWorkerThatNeverWroteLeavesThePreferenceAlone() throws {
        let fake = FakeStore([idleKey: 600, delayKey: 600])
        let (lock, _) = try runner(fake)

        XCTAssertNil(lock.restore())
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertEqual(fake.current[idleKey] ?? nil, 600)
    }

    func testAPersonsOwnNeverSettingIsNotRewrittenOrClaimed() throws {
        let fake = FakeStore([idleKey: SessionIdleLock.never,
                              delayKey: SessionIdleLock.passwordDelayNever])
        let (lock, recordPath) = try runner(fake)

        XCTAssertNil(lock.apply())
        XCTAssertTrue(fake.writes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordPath),
                       "AgentSpace must not claim a change it did not make")
        XCTAssertNil(lock.restore())
    }

    func testAFailedPreferenceWriteIsReportedAndKeepsTheRecordForTheNextStop() throws {
        // The record is written before the preference, so a failure cannot
        // strand the account with a changed value and nothing to restore it
        // from; and the failure is said out loud rather than swallowed.
        let fake = FakeStore([idleKey: 1200])
        fake.succeeds = false
        let (lock, recordPath) = try runner(fake)

        XCTAssertEqual(lock.apply(),
                       "the account can still lock itself: could not write \(SessionIdleLockRunner.domain)/\(idleKey), \(SessionIdleLockRunner.domain)/\(delayKey)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordPath))
    }

    func testOneKeyRestoredAndOneRefusedKeepsOnlyTheRefusedOneOnTheBooks() throws {
        // A partial restore must not delete the record: the key that could not be
        // put back is still AgentSpace's to undo, and the next Worker start has to
        // be able to find its original.
        let fake = FakeStore([idleKey: 1200, delayKey: 30])
        let (lock, recordPath) = try runner(fake)
        XCTAssertNotNil(lock.apply())
        fake.failing = [delayKey]

        XCTAssertEqual(lock.restore(), "still AgentSpace's to undo: could not restore \(SessionIdleLockRunner.domain)/\(delayKey)")
        XCTAssertEqual(fake.current[idleKey] ?? nil, 1200)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordPath))

        let text = try String(contentsOfFile: recordPath, encoding: .utf8)
        XCTAssertTrue(text.contains(delayKey))
        XCTAssertFalse(text.contains(idleKey), "the key already put back must not be claimed twice")
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
