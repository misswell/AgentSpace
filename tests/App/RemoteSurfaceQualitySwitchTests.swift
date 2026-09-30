import XCTest
import AppKit
import SwiftUI
import AgentSpaceCore
@testable import AgentSpaceApp

final class RemoteSurfaceQualitySwitchTests: XCTestCase {
    @MainActor
    func testEveryQualityReplacementDisplaysTheCurrentFrameClient() async throws {
        let account = AgentAccount(name: "QualityFixture", username: "fixture", uid: getuid())
        let first = FrameClient(space: account, target: .retinaDesktop)
        let host = NSHostingView(rootView: RemoteSurfaceView(client: first))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        host.layoutSubtreeIfNeeded()
        var previous = try XCTUnwrap(surface(in: host))
        XCTAssertTrue(previous.client === first)
        // Every ordered pair, including the reported Balanced -> Native switch.
        for quality in [DisplayQuality.balanced, .native, .performance, .balanced, .performance, .native] {
            let size = quality.captureSize(sourceWidth: 2880, sourceHeight: 1800)
            let next = FrameClient(space: account, target: .retinaDesktop,
                                   targetWidth: size.width, targetHeight: size.height)
            host.rootView = RemoteSurfaceView(client: next)
            host.layoutSubtreeIfNeeded()
            let deadline = Date().addingTimeInterval(2)
            while surface(in: host)?.client !== next && Date() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
                host.layoutSubtreeIfNeeded()
            }
            let current = try XCTUnwrap(surface(in: host))
            XCTAssertTrue(current.client === next,
                          "\(quality): the page must render the replacement stream, not the stopped one")
            XCTAssertFalse(current === previous, "A new stream needs its own renderer and teardown callbacks")
            XCTAssertNotNil(next.handleSharedFrame)
            XCTAssertNotNil(next.handleVideoFrame)
            host.rootView = RemoteSurfaceView(client: next, captureMagnification: 2)
            let updateDeadline = Date().addingTimeInterval(2)
            while surface(in: host)?.captureMagnification != 2 && Date() < updateDeadline {
                try await Task.sleep(nanoseconds: 10_000_000)
                host.layoutSubtreeIfNeeded()
            }
            XCTAssertTrue(surface(in: host) === current, "Ordinary view updates must keep the current surface")
            previous = current
        }
    }

    @MainActor
    private func surface(in view: NSView) -> RemoteSurfaceNSView? {
        if let surface = view as? RemoteSurfaceNSView { return surface }
        for child in view.subviews {
            if let found = surface(in: child) { return found }
        }
        return nil
    }
}
