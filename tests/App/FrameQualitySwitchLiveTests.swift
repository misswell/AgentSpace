import XCTest
import SwiftUI
import AppKit
import AgentSpaceCore
@testable import AgentSpaceApp

final class FrameQualitySwitchLiveTests: XCTestCase {
    @MainActor
    func testQualitySwitchKeepsMainThreadResponsive() async throws {
        guard ProcessInfo.processInfo.environment["AGENTSPACE_LIVE_QUALITY_TEST"] == "1" else {
            throw XCTSkip("Requires an explicitly selected background AgentUse session")
        }
        let account = try XCTUnwrap(SpaceRegistry.load().spaces.first { $0.name == "AgentUse" })
        var previous: FrameClient?
        var host: NSHostingView<RemoteSurfaceView>?
        defer { previous?.stop() }
        for quality in [DisplayQuality.native, .balanced, .native, .performance, .balanced, .performance, .native] {
            let size = quality.captureSize(sourceWidth: 2880, sourceHeight: 1800)
            let next = FrameClient(space: account, target: .retinaDesktop, maxFPS: 30,
                                   targetWidth: size.width, targetHeight: size.height)
            if let host {
                host.rootView = RemoteSurfaceView(client: next)
            } else {
                host = NSHostingView(rootView: RemoteSurfaceView(client: next))
                host?.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
            }
            host?.layoutSubtreeIfNeeded()
            next.start()
            let began = Date()
            previous?.stop()
            let elapsed = Date().timeIntervalSince(began)
            print("quality switch \(quality): main-thread stop \(elapsed)s")
            XCTAssertLessThan(elapsed, 0.1, "Changing quality must not block the UI on stream teardown")
            previous = next
            let deadline = Date().addingTimeInterval(15)
            while (next.state != .streaming || next.surfaceSize == .zero) && Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
                host?.layoutSubtreeIfNeeded()
            }
            XCTAssertEqual(next.state, .streaming)
            XCTAssertGreaterThan(next.surfaceSize.width, 0, "The new quality must deliver an applied picture")
        }
    }
}
