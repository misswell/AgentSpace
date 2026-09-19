import XCTest
import Foundation

/// The localization tables stay in lockstep, mechanically.
///
/// The keys are the English source texts. Three failure modes are caught here
/// rather than on a user's screenshot:
///
/// 1. a key present in one language and missing in the other — the UI would
///    show raw English in the middle of Chinese;
/// 2. a translated value whose format specifiers disagree with the English —
///    `String(format:)` would garble or drop an argument;
/// 3. a `NSLocalizedString` call in any source whose key is in no table at
///    all — the string can never be translated.
final class LocalizationTests: XCTestCase {

    private var resourcesRoot: String {
        // tests/Unit/LocalizationTests.swift → repo root is three directories up.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("apps/AgentSpace/Resources").path
    }

    private func table(_ language: String) throws -> [String: String] {
        let url = URL(fileURLWithPath: "\(resourcesRoot)/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: String] else {
            XCTFail("\(url.path) did not parse as [String: String]")
            return [:]
        }
        return dict
    }

    /// Conversion letters of every format specifier, position and width
    /// stripped so positional and plain forms compare equal (`%1$@` ≡ `%@`).
    /// `%ld` counts as its leading letter in both languages, which keeps the
    /// comparison honest about the forms the sources actually use.
    private func specifiers(_ format: String) -> [Character] {
        var out: [Character] = []
        let characters = Array(format)
        var index = 0
        while index < characters.count {
            guard characters[index] == "%" else {
                index += 1
                continue
            }
            var cursor = index + 1
            while cursor < characters.count,
                  characters[cursor].isNumber || characters[cursor] == "$"
                  || characters[cursor] == "-" || characters[cursor] == "." {
                cursor += 1
            }
            if cursor < characters.count, characters[cursor].isLetter {
                out.append(characters[cursor])
            }
            index = cursor + 1
        }
        return out
    }

    func testTablesHaveIdenticalKeySets() throws {
        let english = try table("en")
        let chinese = try table("zh-Hans")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys),
                       "en and zh-Hans disagree; the missing side shows raw English in the UI")
    }

    func testNoEmptyTranslations() throws {
        let chinese = try table("zh-Hans")
        for (key, value) in chinese {
            XCTAssertFalse(value.isEmpty, "zh-Hans entry for “\(key)” is empty")
        }
    }

    func testFormatSpecifiersAgreeBetweenLanguages() throws {
        let english = try table("en")
        let chinese = try table("zh-Hans")
        for (key, englishValue) in english {
            guard let chineseValue = chinese[key] else { continue }
            XCTAssertEqual(
                specifiers(englishValue).sorted(),
                specifiers(chineseValue).sorted(),
                "format specifiers disagree for key “\(key)”")
        }
    }

    /// Every `NSLocalizedString` in the package resolves to a key both tables
    /// carry. Scans the sources rather than trusting a hand-kept list.
    func testEveryUsedKeyExistsInTables() throws {
        let english = try table("en")
        let chinese = try table("zh-Hans")

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoots = [
            repoRoot.appendingPathComponent("shared/Core/Sources/AgentSpaceCore").path,
            repoRoot.appendingPathComponent("apps/AgentSpace").path,
        ]

        var usedKeys = Set<String>()
        for root in sourceRoots {
            let enumerator = FileManager.default.enumerator(atPath: root)
            while let relative = enumerator?.nextObject() as? String {
                guard relative.hasSuffix(".swift") else { continue }
                let contents = try String(
                    contentsOfFile: root + "/" + relative, encoding: .utf8)
                let pattern = "NSLocalizedString\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(contents.startIndex..., in: contents)
                for match in regex.matches(in: contents, range: range) {
                    guard let matchRange = Range(match.range(at: 1), in: contents) else { continue }
                    usedKeys.insert(
                        String(contents[matchRange])
                            .replacingOccurrences(of: "\\\"", with: "\"")
                            .replacingOccurrences(of: "\\n", with: "\n")
                            .replacingOccurrences(of: "\\\\", with: "\\"))
                }
            }
        }

        XCTAssertFalse(usedKeys.isEmpty, "the source scan found nothing — the scan itself is broken")
        for key in usedKeys.sorted() {
            XCTAssertTrue(english[key] != nil, "key missing from en table: \(key)")
            XCTAssertTrue(chinese[key] != nil, "key missing from zh-Hans table: \(key)")
        }
    }

    /// `Text("…")` localizes by itself, but only against a key the table carries
    /// — and a missing key is silent: the label stays English in the middle of a
    /// Chinese window, which is what an owner's screenshot caught. Prose
    /// literals are therefore scanned too. The filters skip what is not prose:
    /// code identifiers, paths, example values, format strings.
    func testEveryProseTextLiteralHasATableEntry() throws {
        let chinese = try table("zh-Hans")
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repoRoot.appendingPathComponent("apps/AgentSpace").path

        let regex = try NSRegularExpression(
            pattern: "Text\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*[,)]")
        var checked = 0
        let enumerator = FileManager.default.enumerator(atPath: sourceRoot)
        while let relative = enumerator?.nextObject() as? String {
            guard relative.hasSuffix(".swift") else { continue }
            let contents = try String(contentsOfFile: sourceRoot + "/" + relative, encoding: .utf8)
            let range = NSRange(contents.startIndex..., in: contents)
            for match in regex.matches(in: contents, range: range) {
                guard let matchRange = Range(match.range(at: 1), in: contents) else { continue }
                let key = String(contents[matchRange])
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\n", with: "\n")
                if key.count < 15 || key.contains(where: { "/%(~$".contains($0) }) { continue }
                checked += 1
                XCTAssertNotNil(chinese[key],
                                "Text(\"\(key)\") in \(relative) has no zh-Hans entry, so it never translates")
            }
        }
        XCTAssertGreaterThan(checked, 10, "the literal scan found almost nothing — the scan is broken")
    }
}
