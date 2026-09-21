import Foundation

/// A dotted version as the release channel spells it (`v0.1.18`, `0.1.18`).
///
/// Comparison pads missing components with zero so `0.1.18` and `0.1.18.0` are
/// the same release, which is what the release notes and the plist say
/// respectively.
public struct SoftwareVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    private let components: [Int]

    public init?(_ value: String) {
        let normalized = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let pieces = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty,
              pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              pieces.compactMap({ Int($0) }).count == pieces.count else { return nil }
        components = pieces.compactMap { Int($0) }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func == (lhs: SoftwareVersion, rhs: SoftwareVersion) -> Bool {
        normalized(lhs.components) == normalized(rhs.components)
    }

    public static func < (lhs: SoftwareVersion, rhs: SoftwareVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Self.normalized(components))
    }

    private static func normalized(_ components: [Int]) -> [Int] {
        var result = components
        while result.count > 1 && result.last == 0 { result.removeLast() }
        return result
    }
}
