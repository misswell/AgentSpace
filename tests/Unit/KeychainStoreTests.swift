import XCTest
@testable import AgentSpaceCore

/// The Keychain store, tested against the real Keychain.
///
/// A mock here would prove nothing: the whole point of this type is that it uses
/// the *system* Keychain correctly — right class, right accessibility, and an
/// update path that replaces rather than silently failing. Those are exactly the
/// things a mock would paper over.
///
/// Every test uses its own service name, so a test can never read or delete a real
/// Space's password, and a leftover item from a previous run can never make a real
/// one look like it exists.
final class KeychainStoreTests: XCTestCase {

    private var keychain: KeychainStore!

    override func setUp() {
        keychain = KeychainStore(service: "com.agentspace.AgentSpace.tests.\(UUID().uuidString.prefix(12))")
    }

    override func tearDown() {
        guard let keychain else { return }
        for id in keychain.storedSpaceIDs() { try? keychain.delete(for: id) }
    }

    func testAPasswordRoundTrips() throws {
        let id = UUID()
        try keychain.store(password: "correct horse battery staple", for: id)
        XCTAssertEqual(try keychain.password(for: id), "correct horse battery staple")
    }

    func testAnUnknownSpaceHasNoPassword() throws {
        XCTAssertNil(try keychain.password(for: UUID()))
        XCTAssertFalse(keychain.exists(for: UUID()))
    }

    func testStoringTwiceReplacesRatherThanFailing() throws {
        // Re-creating a Space must not fail on a stale item — and must not leave
        // two items where one is expected, or the reveal would show the old one.
        let id = UUID()
        try keychain.store(password: "first", for: id)
        try keychain.store(password: "second", for: id)
        XCTAssertEqual(try keychain.password(for: id), "second")
        XCTAssertEqual(keychain.storedSpaceIDs().filter { $0 == id }.count, 1)
    }

    func testDeletingIsIdempotent() throws {
        // "Delete an already-deleted Space" must not fail: the desired end state is
        // the same, and an error there would make the delete flow look broken.
        let id = UUID()
        try keychain.store(password: "x", for: id)
        try keychain.delete(for: id)
        XCTAssertNil(try keychain.password(for: id))
        XCTAssertNoThrow(try keychain.delete(for: id))
    }

    func testStoredSpaceIDsFindsOnlyThisService() throws {
        // The orphan sweep depends on this list being accurate; a bug here would
        // either miss a leftover account or, worse, point the sweep at a Space
        // belonging to a different service.
        let mine = UUID()
        let other = KeychainStore(service: "com.agentspace.AgentSpace.tests.other.\(UUID().uuidString.prefix(8))")
        let theirs = UUID()
        defer { try? other.delete(for: theirs) }

        try keychain.store(password: "a", for: mine)
        try other.store(password: "b", for: theirs)

        let ids = keychain.storedSpaceIDs()
        XCTAssertTrue(ids.contains(mine))
        XCTAssertFalse(ids.contains(theirs), "leaked an identifier from another service")
    }

    func testSpacePasswordIsAlwaysOneWeGenerated() throws {
        // The app must be able to tell its own generated secret from one a user
        // typed, because holding the latter would be a different kind of problem.
        for _ in 0..<25 {
            let password = SpacePassword()
            XCTAssertTrue(password.isGenerated, password.value)
            XCTAssertEqual(password.value.count, HelperValidation.passwordLength)
        }
        XCTAssertFalse(SpacePassword(value: "hunter2").isGenerated)
    }

    func testGeneratedPasswordsDoNotRepeat() throws {
        // §9 forbids fixed passwords. Two Spaces with the same password would mean
        // one Space's leak is another Space's compromise.
        let passwords = Set((0..<200).map { _ in SpacePassword().value })
        XCTAssertEqual(passwords.count, 200, "generated passwords collided")
    }
}
