import XCTest
@testable import AgentSpaceCore

final class AccountDiscoveryTests: XCTestCase {
    func testCandidatesExcludeCurrentSystemAndAdministratorAccounts() {
        let accounts = [
            LocalAccount(username: "root", uid: 0, displayName: "System Administrator", homeDirectory: "/var/root", isAdministrator: true),
            LocalAccount(username: "guofeng", uid: 501, displayName: "Guofeng", homeDirectory: "/Users/guofeng", isAdministrator: true),
            LocalAccount(username: "agentdev", uid: 502, displayName: "Agent Dev", homeDirectory: "/Users/agentdev", isAdministrator: false),
            LocalAccount(username: "qauser", uid: 503, displayName: "QA", homeDirectory: "/Users/qauser", isAdministrator: false),
            LocalAccount(username: "_hidden", uid: 504, displayName: "Hidden", homeDirectory: "/Users/_hidden", isAdministrator: false, isHidden: true),
        ]

        let candidates = AccountDiscovery.candidates(from: accounts, currentUsername: "guofeng")

        XCTAssertEqual(candidates.map(\.username), ["agentdev", "qauser"])
    }

    func testAStandardUserWithAnUnderscoreUsernameIsStillAttachable() {
        let legacyNamedUser = LocalAccount(
            username: "_agentspace_a5b707",
            uid: 503,
            displayName: "AgentUse",
            homeDirectory: "/Users/_agentspace_a5b707",
            isAdministrator: false)

        let candidates = AccountDiscovery.candidates(
            from: [legacyNamedUser],
            currentUsername: "guofeng")

        XCTAssertEqual(candidates.map(\.username), ["_agentspace_a5b707"])
    }

    /// The passwd file lists hundreds of system records, and answering "is this
    /// account an administrator?" costs a process spawn each. Discovery has to
    /// spend those spawns only on records the free filters already accepted.
    func testThePrivilegeProbeIsAskedOnlyAboutRecordsThatPassTheCheapFilters() {
        var records: [(username: String, uid: uid_t, home: String)] = []
        var probed: [String] = []
        setpwent()
        while let entry = getpwent() {
            let value = entry.pointee
            guard let namePointer = value.pw_name, let homePointer = value.pw_dir else { continue }
            records.append((String(cString: namePointer), value.pw_uid, String(cString: homePointer)))
        }
        endpwent()

        let discovered = AccountDiscovery.discover { username in
            probed.append(username)
            return false
        }

        XCTAssertLessThan(probed.count, records.count, "every passwd record was probed: \(probed.count)/\(records.count)")
        let byName = Dictionary(records.map { ($0.username, $0) }, uniquingKeysWith: { first, _ in first })
        for username in probed {
            XCTAssertNotEqual(username, NSUserName())
            guard let record = byName[username] else {
                XCTFail("\(username) was probed but is not a local record")
                continue
            }
            XCTAssertGreaterThanOrEqual(record.uid, 500)
            XCTAssertTrue(record.home.hasPrefix("/Users/"), "\(username) probed with home \(record.home)")
        }
        XCTAssertEqual(Set(probed).count, probed.count, "a record was probed more than once")
        XCTAssertFalse(discovered.contains { $0.isAdministrator })
    }

    func testProbedAdministratorsAreStillExcluded() {
        let discovered = AccountDiscovery.discover { _ in true }
        XCTAssertTrue(discovered.isEmpty)
    }
}
