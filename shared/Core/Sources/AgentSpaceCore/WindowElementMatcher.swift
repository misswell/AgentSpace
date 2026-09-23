import CoreGraphics
import Foundation

/// Maps a `RemoteWindow` onto the accessibility element that *is* that window.
///
/// **Why this is not a title comparison.** The previous rule was "same title,
/// frame within five points". It refused the windows a live test offered it
/// (§328 row 901): a window whose title the app had not exposed, a window whose
/// frame had moved by six points since the catalogue read it, a window with no
/// title at all. The refusal was safe but it was not *useful* — Fusion's whole
/// value is driving the window the person is looking at, and a rule that fails
/// closed on ordinary windows makes the feature unusable while claiming to be
/// careful.
///
/// **What replaces it.** Every accessibility window of that pid is scored
/// against the evidence, and the highest score wins if it is *unambiguous*.
/// Unambiguous means two things: the best candidate clears a floor, and it beats
/// the second best by a margin. A tie is a refusal, because a tie is exactly the
/// case where guessing drives the wrong window.
///
/// **Two grades of consequence.** Pointer input and window raising are
/// non-destructive: a click that lands on a sibling of the intended window is a
/// mis-click, which the person sees and can undo. Closing a window is not — there
/// is no undo for a closed document. So the scoring is shared and the *floor* is
/// not: `match` (permissive, for pointer and activate) and `matchStrict` (exact
/// title, frame agreement within a point, for close and minimize).
public enum WindowElementMatcher {
    /// The score below which no candidate is believed, for a non-destructive
    /// action.
    public static let permissiveFloor = 0.55
    /// The score that means "this is exactly the window": a matching title and a
    /// matching frame, with no help from where the window sits in the stack.
    /// Used as the strict rule's floor, so a destructive action needs evidence
    /// about the *window* rather than about its position.
    public static let exactScore = titleWeight + frameWeight
    /// The margin by which the winner must beat the runner-up. A near-tie is a
    /// refusal: two windows that score alike are two windows the evidence cannot
    /// tell apart.
    public static let requiredMargin = 0.15
    /// Weights. Title equality is the strongest single signal because a title is
    /// what a person uses to tell two windows of one app apart; frame agreement
    /// is next because a window that has not moved is almost certainly the one
    /// the catalogue read.
    public static let titleWeight = 0.45
    public static let frameWeight = 0.45
    public static let zOrderWeight = 0.10

    /// One accessibility window's *observable* facts, which is all the scoring
    /// needs: the caller owns the element and Core owns the arithmetic, so the
    /// decision is testable without a WindowServer and the worker keeps every
    /// call that touches Accessibility.
    public struct Observation: Equatable, Sendable {
        public var title: String?
        public var frame: CGRect?
        /// Position in the front-to-back list the accessibility API returns.
        public var zIndex: Int
        public var totalCount: Int

        public init(title: String?, frame: CGRect?, zIndex: Int, totalCount: Int) {
            self.title = title; self.frame = frame
            self.zIndex = zIndex; self.totalCount = totalCount
        }
    }

    public struct Scored: Equatable, Sendable {
        public var index: Int
        public var score: Double
        /// Why this candidate scored what it did, so a refusal can say which
        /// evidence was missing rather than only that it was.
        public var reasons: [String]
    }

    /// The verdict on a set of observations.
    public enum Decision: Equatable, Sendable {
        /// The one window to act on, by its index into the observations.
        case matched(index: Int, score: Double)
        case refused(Reason)

        public enum Reason: Equatable, Sendable {
            /// Nothing belonged to that process at all.
            case noCandidates
            /// Every candidate was too weak to act on.
            case belowFloor(best: Double, floor: Double, reasons: [String])
            /// Two candidates were too close to tell apart.
            case ambiguous(best: Double, runnerUp: Double)
        }
    }

    /// Choose the one window the evidence points at.
    ///
    /// `strict` raises the bar to "exact": used for destructive actions, where a
    /// wrong guess is not a mis-click but a closed document. A non-destructive
    /// action — pointer input, raising a window — accepts a clearly-best
    /// candidate, because refusing to click a window whose title an app never
    /// exposed makes Fusion unusable rather than safe.
    public static func decide(_ observations: [Observation], matches remote: RemoteWindow,
                              strict: Bool = false) -> Decision {
        guard !observations.isEmpty else { return .refused(.noCandidates) }
        // A strict question is asked about the *window*, so it is answered
        // without the z-order term: where a window sits in the stack is useful
        // evidence for "which one is the person looking at", and worthless for
        // "which one is this exactly". Including it would let two identical
        // windows be told apart by the thing that cannot tell them apart.
        let scored = score(observations, matches: remote, includeStackingOrder: !strict)
            .sorted { $0.score > $1.score }
        guard let best = scored.first else { return .refused(.noCandidates) }
        let floor = strict ? exactScore - 1e-9 : permissiveFloor
        guard best.score >= floor else {
            return .refused(.belowFloor(best: best.score, floor: floor, reasons: best.reasons))
        }
        if let runnerUp = scored.dropFirst().first {
            if strict {
                // Any second candidate whose own evidence is just as exact makes
                // the action ambiguous, however the stack is ordered.
                guard runnerUp.score < floor else { return .refused(.ambiguous(best: best.score, runnerUp: runnerUp.score)) }
            } else {
                guard best.score - runnerUp.score >= requiredMargin else {
                    return .refused(.ambiguous(best: best.score, runnerUp: runnerUp.score))
                }
            }
        }
        return .matched(index: best.index, score: best.score)
    }

    /// Score every observation, best first. Pure: no Accessibility call, no
    /// WindowServer, so the rules are testable with three rectangles.
    public static func score(_ observations: [Observation], matches remote: RemoteWindow,
                             includeStackingOrder: Bool = true) -> [Scored] {
        observations.enumerated().map { index, observation in
            var value = 0.0
            var reasons: [String] = []
            if let remoteTitle = remote.title, !remoteTitle.isEmpty {
                if observation.title == remoteTitle {
                    value += titleWeight
                } else if let title = observation.title, !title.isEmpty {
                    // A near-miss on a title both ends do have is still evidence:
                    // an app can retitle itself between the catalogue read and
                    // this call (a document being edited, a download finishing).
                    value += titleWeight * similarity(remoteTitle, title) * 0.5
                } else {
                    reasons.append("no title")
                }
            } else {
                // The catalogue did not know a title, so no window can be
                // rewarded or punished for one.
                value += titleWeight * 0.5
                reasons.append("title unknown at capture time")
            }
            if let frame = observation.frame {
                // Intersection-over-union against the frame the catalogue read:
                // it degrades with movement instead of falling off a cliff at
                // five points, which is what made a window that had been nudged
                // unreachable.
                let iou = intersectionOverUnion(frame, remote.frame.cgRect)
                value += frameWeight * iou
                if iou < 0.5 { reasons.append("frame moved (IoU \(format(iou)))") }
            } else {
                reasons.append("no frame")
            }
            // Front-to-back order is weak but real evidence: the catalogue reads
            // the on-screen list, and the window a person is looking at is
            // usually near the front. A strict question leaves it out entirely —
            // see `decide`.
            if includeStackingOrder {
                let zScore = observation.totalCount > 1
                    ? 1.0 - Double(observation.zIndex) / Double(observation.totalCount - 1)
                    : 1.0
                value += zOrderWeight * zScore
            }
            return Scored(index: index, score: value, reasons: reasons)
        }
    }

    /// A window whose title is compared case-insensitively and ignoring the
    /// trailing document marker macOS adds (`— Edited`, `(2)`): an app that
    /// retitles itself for its own reasons must not make its window unreachable.
    private static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let normalize: (String) -> String = { value in
            value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let left = normalize(a), right = normalize(b)
        if left == right { return 1 }
        if left.hasPrefix(right) || right.hasPrefix(left) {
            let shorter = Double(min(left.count, right.count))
            let longer = Double(max(left.count, right.count))
            return longer > 0 ? shorter / longer : 0
        }
        return 0
    }

    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return Double(intersectionArea / unionArea)
    }

    private static func format(_ value: Double) -> String { String(format: "%.2f", value) }

}

extension CGRectValue {
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
