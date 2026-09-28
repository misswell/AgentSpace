import Foundation
import Security
import ServiceManagement
import XCTest
@testable import AgentSpaceCore

/// The helper's caller requirement names every Mach-O identity that must be
/// able to call it.
///
/// Measured on this machine, 2026-09-28: the helper ran, launchd held it
/// `state = running`, the app was accepted — and every CLI connection was
/// refused, because the requirement named only the app and the helper. The CLI
/// is a nested Mach-O with its *own* signing identifier
/// (`com.agentspace.AgentSpace.CLI`, `scripts/bundle-app.sh`), so "it ships
/// inside the app bundle" made the doctor report "not answering" against a
/// helper that was answering the app the whole time. These tests fail if an
/// identifier `bundle-app.sh` signs goes missing from the requirement again.
final class HelperCallerVerificationTests: XCTestCase {
    private var requirement: String { CodeSigningRequirement.requirement }
    private var developmentRequirement: String { CodeSigningRequirement.developmentRequirement }

    func testTheRequirementNamesEverySignedCaller() {
        for identifier in [BundleIdentifiers.app, BundleIdentifiers.helper, BundleIdentifiers.cliCode] {
            XCTAssertTrue(requirement.contains("identifier \"\(identifier)\""),
                          "the helper refuses every call from \(identifier) unless the requirement names it")
            XCTAssertTrue(developmentRequirement.contains("identifier \"\(identifier)\""),
                          "a debug helper must accept the same callers a release one does, minus the Apple anchor")
        }
    }

    /// `anchor apple generic` is what separates our Developer ID signature from
    /// a self-signed certificate that copied the team identifier; a regression
    /// here would accept any locally signed code with the right identifier.
    func testTheReleaseRequirementKeepsTheAppleAnchorAndTeam() {
        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains(CodeSigningRequirement.teamIdentifier))
    }

    /// A malformed requirement string would make `SecRequirementCreateWithString`
    /// fail inside the helper, and a helper that cannot parse its own requirement
    /// refuses every caller — the self-check guards this at run time, and this
    /// test guards it at build time.
    func testTheRequirementParses() {
        var requirement_: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(requirement as CFString, [], &requirement_), errSecSuccess)
        XCTAssertNotNil(requirement_)
    }

    // MARK: - The bundle script and the requirement cannot drift apart

    /// The requirement is only as true as the signatures it names. Read the
    /// identifiers `bundle-app.sh` actually signs and require the three that
    /// call the helper to be among the accepted ones.
    func testEveryHelperCallerBundleAppSignsIsAccepted() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // tests/Unit
            .deletingLastPathComponent()   // tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("scripts/bundle-app.sh")
        guard let script = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("bundle-app.sh is not in this checkout")
        }
        let signedIdentifiers = script
            .split(separator: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("sign ") }
            .compactMap { line -> String? in
                // `sign "$APP/Contents/…" "com.agentspace.…"` — the identifier
                // is the last quoted argument on the line.
                let parts = line.split(separator: "\"")
                guard parts.count >= 3 else { return nil }
                return String(parts[parts.count - 1])
            }
        XCTAssertTrue(signedIdentifiers.contains(BundleIdentifiers.app), "bundle-app.sh signs the app")
        XCTAssertTrue(signedIdentifiers.contains(BundleIdentifiers.helper), "bundle-app.sh signs the helper")
        XCTAssertTrue(signedIdentifiers.contains(BundleIdentifiers.cliCode),
                      "bundle-app.sh signs the CLI with \(BundleIdentifiers.cliCode); the requirement must name what the script signs")
    }
}

/// What a refused `register()` says to the person looking at it.
///
/// The raw `localizedDescription` of a pending-approval refusal is "Operation
/// not permitted" — indistinguishable from a bug in the app, and it sends the
/// person back to the very button that can never succeed. The guidance exists
/// so the UI can say "macOS is waiting for you" instead.
final class HelperRegistrationGuidanceTests: XCTestCase {
    func testAPendingApprovalIsNamedAsSuch() {
        let refusal = HelperRegistrationGuidance.refusal(
            for: NSError(domain: NSCocoaErrorDomain, code: 1),
            status: .requiresApproval)
        XCTAssertTrue(refusal.approvalPending)
        XCTAssertTrue(refusal.fix.contains("Login Items"))
    }

    /// The measured case: `register()` answers `SMAppServiceErrorDomain` code 1
    /// while macOS holds the registration for approval — even when the status
    /// read afterwards is stale. The error alone must be enough to name it.
    func testTheMeasuredEPERMIsRecognisedWithoutAStatusRead() {
        let refusal = HelperRegistrationGuidance.refusal(
            for: NSError(domain: HelperRegistrationGuidance.serviceErrorDomain, code: 1),
            status: .notRegistered)
        XCTAssertTrue(refusal.approvalPending)
    }

    func testAPersonSayingNoIsNotAnApprovalHold() {
        let refusal = HelperRegistrationGuidance.refusal(
            for: NSError(domain: HelperRegistrationGuidance.serviceErrorDomain,
                         code: HelperRegistrationRetry.cancelledCode),
            status: .notRegistered)
        XCTAssertFalse(refusal.approvalPending,
                       "a cancelled prompt is the user's answer, not macOS holding a registration")
    }

    func testAnyOtherFailureKeepsTheSystemMessage() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 42)
        let refusal = HelperRegistrationGuidance.refusal(for: error, status: .notFound)
        XCTAssertFalse(refusal.approvalPending)
        XCTAssertEqual(refusal.message, error.localizedDescription)
    }
}
