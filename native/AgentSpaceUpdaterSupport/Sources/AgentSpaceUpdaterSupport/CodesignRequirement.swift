import Foundation

/// Reading the designated requirement out of `codesign --display -r-`.
///
/// The designated requirement is the identity a privacy grant is recorded
/// against, so "does this update keep the grants this app already has" is the
/// same question as "does this candidate satisfy the running app's
/// requirement". Parsing is separated from the `codesign` call because the
/// output shape — `designated => <expression>` among a page of fields, and a
/// trailing comment full of parentheses — is the part that can silently return
/// the wrong string.
public enum CodesignRequirement {
    public static func parse(from codesignOutput: String) -> String {
        for line in codesignOutput.split(separator: "\n") where line.contains("designated") {
            guard let range = line.range(of: "=> ") else { continue }
            // Whitespace collapses to one space: the expression is handed back to
            // `codesign -R=`, where an embedded newline would not survive.
            return line[range.upperBound...]
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .joined(separator: " ")
        }
        return ""
    }
}
