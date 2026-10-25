import XCTest
@testable import AgentSpaceCore

/// The one write refusal that has a fix: until the helper has handed the
/// shared root's `Network` directory to the main user (§402), every write the
/// app or the CLI makes into it fails — and the surfaces translate that
/// refusal into the sentence that names the fix instead of Cocoa's raw prose.
final class SharedRootWriteTests: XCTestCase {

    func testRecognizesTheTwoSpellingOfTheRefusal() {
        // What Data.write(to:) answers with when the directory is root-owned.
        let cocoa = NSError(
            domain: NSCocoaErrorDomain, code: 513,
            userInfo: [
                NSFilePathErrorKey: "/Library/Application Support/AgentSpace/Network/port-map.json",
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13,
                                              userInfo: [NSLocalizedDescriptionKey: "Permission denied"]),
            ])
        XCTAssertTrue(SharedRootWrite.isPermissionDenied(cocoa))

        // What FileManager.createDirectory answers with.
        let posix = NSError(domain: NSPOSIXErrorDomain, code: 13,
                            userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        XCTAssertTrue(SharedRootWrite.isPermissionDenied(posix))

        // The underlying-only spelling: Cocoa 513 wrapping EACCES.
        let wrapped = NSError(
            domain: NSCocoaErrorDomain, code: 513,
            userInfo: [NSUnderlyingErrorKey: posix])
        XCTAssertTrue(SharedRootWrite.isPermissionDenied(wrapped))
    }

    func testOtherFailuresAreNotTheRefusal() {
        XCTAssertFalse(SharedRootWrite.isPermissionDenied(
            NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [:])), "no such file is a different fact")
        XCTAssertFalse(SharedRootWrite.isPermissionDenied(
            NSError(domain: NSPOSIXErrorDomain, code: 28, userInfo: [:])), "no space is a different fact")
        XCTAssertFalse(SharedRootWrite.isPermissionDenied(
            AgentSpaceError(code: .badRequest, message: "not a file error at all")))
        XCTAssertFalse(SharedRootWrite.isPermissionDenied(
            CocoaError(.fileWriteVolumeReadOnly)))
    }
}
