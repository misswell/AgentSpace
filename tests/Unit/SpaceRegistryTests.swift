import Foundation
import XCTest
@testable import AgentSpaceCore

/// The registry is the only place that knows which Spaces exist, so its failure
/// modes deserve their own tests. The rule throughout: a broken registry must
/// degrade *visibly* — nothing is silently discarded, and what broke stays on
/// disk for diagnosis and recovery.
final class SpaceRegistryTests: XCTestCase {

    private var root: String!
    private var spacesDirectory: String { root + "/Spaces" }

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = "/tmp/as-reg-" + String(UUID().uuidString.prefix(8)).lowercased()
        try FileManager.default.createDirectory(atPath: spacesDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: self.root) }
    }

    private func makeSpace(_ name: String) -> AgentAccount {
        AgentAccount(name: name, username: "_agentspace_" + String(UUID().uuidString.prefix(6)).lowercased(), uid: 502)
    }

    // MARK: - The happy path still works

    func testSaveAndLoadRoundTripsSpaces() throws {
        let registry = SpaceRegistry(spaces: [makeSpace("Alpha"), makeSpace("Beta")])
        try registry.save(root: root)
        let loaded = SpaceRegistry.load(root: root)
        XCTAssertEqual(loaded.spaces.map(\.name), ["Alpha", "Beta"])
    }

    // MARK: - Corruption is quarantined, not discarded

    /// A registry that cannot be decoded is returned empty — the app must keep
    /// working — but the original bytes are moved aside under a name that says
    /// what happened. Two things this prevents: the next save overwriting the
    /// only evidence of what existed, and a user (or doctor) never learning the
    /// registry was broken at all.
    func testCorruptRegistryIsQuarantinedWithItsBytesIntact() throws {
        let original = #"{"spaces": [{"id": "not-a-uuid""#
        try original.write(toFile: spacesDirectory + "/index.json", atomically: true, encoding: .utf8)

        let loaded = SpaceRegistry.load(root: root)
        XCTAssertTrue(loaded.spaces.isEmpty, "an undecodable registry must degrade to empty")

        let quarantined = SpaceRegistry.corruptRegistryFiles(root: root)
        XCTAssertEqual(quarantined.count, 1, "exactly one quarantine file: \(quarantined)")
        let bytes = FileManager.default.contents(atPath: quarantined[0])
        XCTAssertEqual(String(decoding: bytes ?? Data(), as: UTF8.self), original,
                       "the original bytes must survive the quarantine untouched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: spacesDirectory + "/index.json"),
                       "the corrupt file is moved, not left where a save would overwrite it")
    }

    /// Two corrupt loads must not clobber each other's evidence.
    func testRepeatedQuarantinesKeepEveryGeneration() throws {
        for (index, junk) in ["{", "not json at all"].enumerated() {
            try junk.write(toFile: spacesDirectory + "/index.json", atomically: true, encoding: .utf8)
            _ = SpaceRegistry.load(root: root)
            XCTAssertEqual(SpaceRegistry.corruptRegistryFiles(root: root).count, index + 1,
                           "generation \(index) of corrupt evidence was lost")
        }
    }

    /// A healthy load produces no quarantine files, so doctor's check is quiet
    /// unless something actually broke.
    func testHealthyRegistryProducesNoQuarantineFiles() throws {
        try SpaceRegistry(spaces: [makeSpace("Fine")]).save(root: root)
        _ = SpaceRegistry.load(root: root)
        XCTAssertTrue(SpaceRegistry.corruptRegistryFiles(root: root).isEmpty)
    }

    /// A missing registry is not corruption: no quarantine file should appear
    /// for the ordinary first-run state.
    func testMissingRegistryIsNotCorruption() throws {
        let loaded = SpaceRegistry.load(root: root)
        XCTAssertTrue(loaded.spaces.isEmpty)
        XCTAssertTrue(SpaceRegistry.corruptRegistryFiles(root: root).isEmpty)
    }

    // MARK: - Partial corruption

    /// The nastiest shape: valid JSON that decodes to the wrong content — one
    /// space with a garbage uid among good ones. The whole file fails to
    /// decode, so the whole file quarantines; the point of the test is that a
    /// *save after quarantine* produces a registry that loads cleanly, which is
    /// the recovery path a user would actually take.
    func testRecoveryAfterQuarantineWorks() throws {
        try #"{"spaces": [{"name": 42}]"#.write(
            toFile: spacesDirectory + "/index.json", atomically: true, encoding: .utf8)
        XCTAssertTrue(SpaceRegistry.load(root: root).spaces.isEmpty)

        let recovered = SpaceRegistry(spaces: [makeSpace("Recovered")])
        try recovered.save(root: root)
        let loaded = SpaceRegistry.load(root: root)
        XCTAssertEqual(loaded.spaces.map(\.name), ["Recovered"])
        XCTAssertFalse(SpaceRegistry.corruptRegistryFiles(root: root).isEmpty,
                       "the quarantine evidence must survive the recovery save")
    }
}
