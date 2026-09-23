import XCTest
import CoreGraphics
@testable import AgentSpaceCore

/// The window matcher: which accessibility window a remote window is.
///
/// §328 row 901 left this open. The old rule demanded an exact title *and* a frame
/// within five points, which refused the windows a live test offered it — an app
/// that had not exposed a title, a window nudged six points, a window with no
/// title at all. The replacement scores the evidence instead, and these tests are
/// about the two properties that make scoring safe: a clearly-best candidate is
/// accepted, and an ambiguous one is refused rather than guessed.
final class WindowElementMatcherTests: XCTestCase {
    private let window = RemoteWindow(
        id: 42, pid: 900, appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit",
        title: "notes.txt",
        frame: CGRectValue(x: 100, y: 100, width: 400, height: 300),
        layer: 0, visible: true, minimized: false, generation: 3)

    private func observation(title: String?, frame: CGRect?, index: Int = 0, count: Int = 1) -> WindowElementMatcher.Observation {
        WindowElementMatcher.Observation(title: title, frame: frame, zIndex: index, totalCount: count)
    }

    private var matchingFrame: CGRect { CGRect(x: 100, y: 100, width: 400, height: 300) }

    // MARK: - The cases the old rule refused

    /// A window with no exposed title still matches on its frame. This is the
    /// first refusal the live test hit, and a rule that cannot address a window
    /// because its app did not name it makes Fusion useless.
    func testAWindowWithNoTitleStillMatchesOnItsFrame() {
        let decision = WindowElementMatcher.decide([observation(title: nil, frame: matchingFrame)], matches: window)
        guard case .matched(let index, _) = decision else {
            return XCTFail("an untitled window must still be addressable, got \(decision)")
        }
        XCTAssertEqual(index, 0)
    }

    /// A window nudged past the old five-point tolerance still matches. A person
    /// who moved the window by a hair between the catalogue read and the click
    /// must not make their own window unreachable.
    func testAWindowNudgedOffTheExactFrameStillMatches() {
        let nudged = CGRect(x: 108, y: 100, width: 400, height: 300)
        let decision = WindowElementMatcher.decide([observation(title: "notes.txt", frame: nudged)], matches: window)
        guard case .matched = decision else {
            return XCTFail("a small move is not a different window, got \(decision)")
        }
    }

    /// The catalogue may not know a title at all, so no candidate can be punished
    /// for having one or rewarded for lacking it.
    func testAWindowTheCatalogueCouldNotTitleIsMatchedOnGeometry() {
        let untitled = RemoteWindow(id: 7, pid: 900, appName: "Preview", bundleIdentifier: nil,
                                    title: nil, frame: window.frame, layer: 0, visible: true,
                                    minimized: false, generation: 1)
        let decision = WindowElementMatcher.decide([observation(title: "Something Else", frame: matchingFrame)],
                                                   matches: untitled)
        guard case .matched = decision else {
            return XCTFail("geometry alone has to be enough when no title exists, got \(decision)")
        }
    }

    // MARK: - Ambiguity

    /// Two windows that both look like the target are a refusal. This is the case
    /// the scoring exists for: driving a sibling window is exactly the failure the
    /// match is supposed to prevent.
    func testTwoIdenticalWindowsAreRefusedRatherThanGuessed() {
        let observations = [
            observation(title: "notes.txt", frame: matchingFrame, index: 0, count: 2),
            observation(title: "notes.txt", frame: matchingFrame, index: 1, count: 2),
        ]
        let decision = WindowElementMatcher.decide(observations, matches: window)
        guard case .refused(.ambiguous(let best, let runnerUp)) = decision else {
            return XCTFail("two windows the evidence cannot tell apart must be refused, got \(decision)")
        }
        XCTAssertGreaterThan(best, runnerUp - 0.0001)
    }

    /// A clear winner is not treated as a tie. Front-to-back order is enough to
    /// separate two otherwise identical windows, because a person looking at a
    /// proxy is looking at the front one.
    func testATieBrokenByAFrontWindowIsNotAmbiguous() {
        let front = observation(title: "notes.txt", frame: matchingFrame, index: 0, count: 2)
        // The runner-up is a genuinely different window behind it.
        let behind = observation(title: "Untitled", frame: CGRect(x: 900, y: 900, width: 200, height: 200),
                                 index: 1, count: 2)
        let decision = WindowElementMatcher.decide([front, behind], matches: window)
        guard case .matched(let index, _) = decision else {
            return XCTFail("a clear winner must be usable, got \(decision)")
        }
        XCTAssertEqual(index, 0)
    }

    /// Nothing of that process at all is a named refusal rather than a crash or a
    /// silent no-op.
    func testNoCandidatesIsANamedRefusal() {
        XCTAssertEqual(WindowElementMatcher.decide([], matches: window), .refused(.noCandidates))
    }

    // MARK: - Strictness

    /// A destructive action demands an exact match: same title, same frame. A
    /// mis-click can be undone; a closed document cannot.
    func testAStrictMatchRefusesANudgedWindowThatAPermissiveOneAccepts() {
        let nudged = CGRect(x: 108, y: 100, width: 400, height: 300)
        let observations = [observation(title: "notes.txt", frame: nudged)]
        guard case .matched = WindowElementMatcher.decide(observations, matches: window, strict: false) else {
            return XCTFail("permissive matching accepts a small move")
        }
        guard case .refused = WindowElementMatcher.decide(observations, matches: window, strict: true) else {
            return XCTFail("closing a window on a moved-frame guess is not safe")
        }
    }

    func testAStrictMatchAcceptsAnExactWindow() {
        let decision = WindowElementMatcher.decide([observation(title: "notes.txt", frame: matchingFrame)],
                                                   matches: window, strict: true)
        guard case .matched = decision else { return XCTFail("an exact match must pass the strict rule") }
    }

    /// A strict match with a plausible runner-up is refused even when the best
    /// candidate is exact, because "the other one could be it too" is precisely
    /// what a destructive action cannot afford.
    func testAStrictMatchRefusesWhenASecondWindowIsAlsoExact() {
        let observations = [
            observation(title: "notes.txt", frame: matchingFrame, index: 0, count: 2),
            observation(title: "notes.txt", frame: matchingFrame, index: 1, count: 2),
        ]
        guard case .refused = WindowElementMatcher.decide(observations, matches: window, strict: true) else {
            return XCTFail("two exact candidates must not be closed at random")
        }
    }

    // MARK: - Scoring

    /// An exact title and frame beat a weak title and a distant frame, whatever
    /// order they arrive in.
    func testScoringPrefersTheBetterEvidenceRegardlessOfOrder() {
        let good = observation(title: "notes.txt", frame: matchingFrame, index: 1, count: 2)
        let weak = observation(title: "something else", frame: CGRect(x: 900, y: 900, width: 100, height: 100),
                               index: 0, count: 2)
        let decision = WindowElementMatcher.decide([weak, good], matches: window)
        guard case .matched(let index, _) = decision else { return XCTFail("one candidate is clearly better") }
        XCTAssertEqual(index, 1, "the better candidate is index 1 in this ordering")
    }

    /// The IoU is what replaced the five-point cliff: two rectangles that mostly
    /// overlap score highly, and two that barely touch score near zero.
    func testIntersectionOverUnionDegradesWithMovement() {
        let base = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(WindowElementMatcher.intersectionOverUnion(base, base), 1.0, accuracy: 1e-9)
        let shifted = CGRect(x: 50, y: 0, width: 100, height: 100)
        let shiftedIoU = WindowElementMatcher.intersectionOverUnion(base, shifted)
        XCTAssertGreaterThan(shiftedIoU, 0.3)
        XCTAssertLessThan(shiftedIoU, 0.4)
        XCTAssertEqual(WindowElementMatcher.intersectionOverUnion(base, CGRect(x: 500, y: 500, width: 10, height: 10)), 0)
    }

    /// A window that has been retitled by its own app — "notes.txt — Edited" —
    /// is still recognisably the same window.
    func testARetitledWindowStillScoresAboveTheFloor() {
        let retitled = observation(title: "notes.txt — Edited", frame: matchingFrame)
        let decision = WindowElementMatcher.decide([retitled], matches: window)
        guard case .matched = decision else {
            return XCTFail("an app that retitles its own window must not make it unreachable, got \(decision)")
        }
    }
}
