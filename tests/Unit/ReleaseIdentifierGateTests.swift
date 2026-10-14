import Foundation
import XCTest

/// Layer 4 finds buttons by accessibility identifier, and `scripts/release.sh`
/// now reads those names out of the bundle it is about to sign — the only build
/// anybody installs. This test keeps that list from rotting, in both directions.
///
/// The byte check is worth having precisely because of what it cannot do: Swift
/// stores an ASCII string literal of 15 bytes or fewer *inside the `String`'s own
/// words* (a small string), so an optimized build materializes it as `mov`/`movk`
/// halfword immediates and never as a contiguous `__cstring` entry. Measured as
/// matched pairs — a tree against the binary built from that tree, both the
/// `accessibilityIdentifier("…")` and the `identifier: "…"` form: 0.1.84's 62
/// identifiers against its shipped binary leave 8 absent, all ≤15 bytes, with the
/// 54 present starting at 17; this tree's 63 against its release binary leave 3
/// absent (the names deliberately left short) with the 60 present starting at 16;
/// a debug build of the old sources carries all 62. So absence of bytes says
/// nothing about a short name, and a grep of the shipped bundle can only speak
/// for names long enough to be pooled. That is what the 16-character rule below
/// defends, and validation §386 is where the boundary was measured.
final class ReleaseIdentifierGateTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func read(_ relative: String) throws -> String {
        let url = repoRoot.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("\(relative) is not in this checkout")
        }
        return text
    }

    /// The list `scripts/release.sh` asserts against the built bundle.
    private func declaredHandles() throws -> [String] {
        let script = try read("scripts/release.sh")
        guard let body = script.components(separatedBy: "LAYER4_HANDLES=(").last?
            .components(separatedBy: ")").first else {
            XCTFail("release.sh no longer declares LAYER4_HANDLES"); return []
        }
        return body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Every identifier the app can put on an element — the direct
    /// `accessibilityIdentifier("…")` form and the `identifier: "…"` parameter
    /// the shared `Field` helper takes.
    private func identifiersInUse() throws -> Set<String> {
        let root = repoRoot.appendingPathComponent("apps/AgentSpace").path
        let patterns = [
            "accessibilityIdentifier\\(\\s*\"([^\"]+)\"",
            "identifier:\\s*\"([^\"]+)\"",
        ]
        let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
        var found = Set<String>()
        let files = try FileManager.default.subpathsOfDirectory(atPath: root)
            .filter { $0.hasSuffix(".swift") }
        for relative in files {
            guard let text = try? String(contentsOfFile: root + "/" + relative, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for regex in regexes {
                for match in regex.matches(in: text, range: range) {
                    guard let at = Range(match.range(at: 1), in: text) else { continue }
                    found.insert(String(text[at]))
                }
            }
        }
        return found
    }

    /// The identifiers the two layer-4 instruments name when they look for a
    /// button: `gui-verify.sh` through AppleScript, `tests/SessionUI` through
    /// `AXUIElement` directly.
    private func pressedHandles() throws -> Set<String> {
        let inUse = try identifiersInUse()
        var pressed = Set<String>()
        for file in ["scripts/gui-verify.sh", "tests/SessionUI/main.swift"] {
            let text = try read(file)
            for candidate in text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            where candidate.count > 6 && candidate.first.map({ $0.isLowercase }) == true
                && candidate.contains(where: { $0.isUppercase }) {
                if inUse.contains(candidate) { pressed.insert(candidate) }
            }
        }
        return pressed
    }

    func testTheGateListCoversWhatLayer4Presses() throws {
        let declared = Set(try declaredHandles())
        let pressed = try pressedHandles()
        XCTAssertGreaterThanOrEqual(pressed.count, 10,
                                    "the instrument scan found \(pressed.count) identifiers — the scan is broken")
        let missing = pressed.subtracting(declared).sorted()
        XCTAssertTrue(missing.isEmpty,
                      "layer 4 presses these but release.sh does not read them out of the shipped bytes: \(missing)")
    }

    func testEveryDeclaredHandleStillExistsInTheApp() throws {
        let inUse = try identifiersInUse()
        XCTAssertGreaterThanOrEqual(inUse.count, 40, "no app identifier was found — the scan is broken")
        for handle in try declaredHandles().sorted() {
            XCTAssertTrue(inUse.contains(handle),
                          "release.sh asserts \(handle), which no app source carries any more")
        }
    }

    /// A name short enough to be a Swift small string has no pooled bytes to
    /// match, so putting it in the gate list would assert nothing at all.
    func testEveryDeclaredHandleIsLongEnoughToBePooled() throws {
        for handle in try declaredHandles().sorted() {
            XCTAssertGreaterThanOrEqual(handle.count, 16,
                                        "\(handle) is \(handle.count) bytes: an optimized build stores it inline, so the byte check cannot see it (§386)")
        }
    }

    /// release.sh matches a whole pooled string, so a handle that is also a
    /// substring of another identifier could be attributed to the wrong view —
    /// one surface's literal answering for another's absence.
    func testNoGateHandleIsHiddenInsideAnotherIdentifier() throws {
        let inUse = try identifiersInUse()
        for handle in try declaredHandles().sorted() {
            let hosts = inUse.filter { $0 != handle && $0.contains(handle) }.sorted()
            XCTAssertTrue(hosts.isEmpty,
                          "\(handle) is a substring of \(hosts): the byte gate could pass on another view's literal")
        }
    }
}
