import XCTest
import AppKit
import SwiftUI
import Combine
import Darwin
import AgentSpaceCore
@testable import AgentSpaceApp

/// A frame that arrives must not cost a main-thread UI update per frame.
///
/// The measurement that put this here: with a 4K stream open and the agent desktop
/// *still*, the app was burning 92.4% of one core while its Worker sat at 0.5%
/// (`artifacts/frame-benchmark-20261010-172749.json`, §382). Capture and transport
/// were idle. That same window published nothing at all — the stream was stuck — so
/// the number does not say by itself what was burning the core; this test does, with
/// the same probe run against the fixed client and against the client before it.
///
/// Three instruments, all of which exist in both versions, so the comparison is like
/// for like:
///   * frames: the Worker's own `framesPublished` counter over `frame.stats`. The
///     reader's view is deliberately not used — this process never puts the surface
///     in a window, so Metal never presents and a render-rate counter would read 0.
///   * cost to the interface: a probe view that counts its own `body` evaluations
///     (what SwiftUI re-renders) and the client's `objectWillChange` publisher (what
///     tells it to).
///   * cost to the machine: this process's own CPU seconds.
///
/// Two windows, because a stream has two weathers. The first is the fifteen seconds
/// after `start()` — the handshake, the first paints, and the display
/// reconfiguration a retina desktop brings: measured 8.6 frames/s (69 frames) on
/// 2026-10-10. The second is the settled desktop after that, where the product's own
/// design (publish on damage, heartbeats otherwise) means almost nothing is sent:
/// measured 1 frame in 10 s, then 0. A verdict measured only on the second window
/// would be vacuous, and a verdict measured only on the first would be flattering —
/// so both are measured and both are asserted on.
///
/// Asserted as a ratio rather than a wall-clock time because the ratio is what
/// distinguishes "a picture" from "a picture that re-renders the app": it does not
/// move with machine speed, and a slow GPU makes a timing bound meaningless.
///
/// Skipped unless asked for: `AGENTSPACE_LIVE_COST_TEST=1 scripts/test.sh`.
final class FrameStreamCostTests: XCTestCase {
    /// Counts how often SwiftUI evaluates the view that hosts the remote surface.
    /// A counter rather than a log, because the number is the verdict.
    private final class BodyCounter { var evaluations = 0 }

    private struct CountingHost: View {
        let client: FrameClient
        let counter: BodyCounter
        var body: some View {
            counter.evaluations += 1
            return RemoteSurfaceView(client: client)
        }
    }

    private struct StreamStats {
        var object: [String: JSONValue]
        var id: String { object["streamID"]?.stringValue ?? "?" }
        var published: Int { object["framesPublished"]?.intValue ?? -1 }
        var reconnects: Int { object["socketReconnects"]?.intValue ?? -1 }
        var captures: Int { object["captureTerminations"]?.intValue ?? -1 }
    }

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    /// What the Worker says about the one stream this test opened. `nil` while no
    /// stream is open at all, which is the state before `start()` has been answered.
    private func streamState(for account: AgentAccount) throws -> StreamStats? {
        let connection = SpaceConnection(space: account)
        let response = try connection.client.call(method: Method.frameStats, params: .obj([:]), token: connection.token)
        guard let streams = response.result?.objectValue?["streams"]?.arrayValue else { return nil }
        guard let stream = streams.first(where: { $0.objectValue?["target"]?.objectValue?["kind"]?.stringValue == "retinaDesktop" }) else { return nil }
        return StreamStats(object: try XCTUnwrap(stream.objectValue))
    }

    private func publishedFrames(for account: AgentAccount) throws -> Int {
        try XCTUnwrap(try streamState(for: account), "frame.stats answered no streams while one is open").published
    }

    private struct Cost {
        var frames: Int
        var bodies: Int
        var publishes: Int
        var cpu: Double
    }

    @MainActor
    func testAShiftingDesktopDeliversFramesWithoutDeliveringOneUITickPerFrame() async throws {
        guard ProcessInfo.processInfo.environment["AGENTSPACE_LIVE_COST_TEST"] == "1" else {
            throw XCTSkip("Requires an explicitly selected background AgentUse session")
        }
        let account = try XCTUnwrap(SpaceRegistry.load().spaces.first { $0.name == "AgentUse" })
        let size = DisplayQuality.balanced.captureSize(sourceWidth: 2880, sourceHeight: 1800)
        let client = FrameClient(space: account, target: .retinaDesktop, maxFPS: 30,
                                 targetWidth: size.width, targetHeight: size.height)
        let counter = BodyCounter()
        let host = NSHostingView(rootView: CountingHost(client: client, counter: counter))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        host.layoutSubtreeIfNeeded()

        var publishes = 0
        let subscription = client.objectWillChange.sink { _ in publishes += 1 }
        defer { subscription.cancel() }

        var framesBefore = 0
        var bodiesBefore = 0, publishesBefore = 0
        var cpuBefore = 0.0
        func sample() throws -> Cost {
            let frames = try publishedFrames(for: account) - framesBefore
            let cost = Cost(frames: frames,
                            bodies: counter.evaluations - bodiesBefore,
                            publishes: publishes - publishesBefore,
                            cpu: cpuSeconds() - cpuBefore)
            framesBefore += frames
            bodiesBefore = counter.evaluations
            publishesBefore = publishes
            cpuBefore = cpuSeconds()
            return cost
        }
        func report(_ label: String, _ window: Double, _ cost: Cost) -> Cost {
            print("frame cost over \(Int(window))s (\(label)): published=\(cost.frames) (\(String(format: "%.1f", Double(cost.frames) / window))/s) bodyEvaluations=\(cost.bodies) (\(String(format: "%.1f", Double(cost.bodies) / window))/s) objectWillChange=\(cost.publishes) (\(String(format: "%.1f", Double(cost.publishes) / window))/s) processCPUSeconds=\(String(format: "%.2f", cost.cpu))")
            return cost
        }

        // A real viewer shows the remote cursor, and that is the viewer this test is
        // about; without the embedding the picture is not the one a person watches.
        client.setEmbeddedCursor(true)
        client.start()
        defer { client.stop() }

        // The baseline is read from the *stream's* own counters, so the opening
        // window starts with the stream, not with this process's convenience.
        var opening = Date().addingTimeInterval(10)
        while (try streamState(for: account)?.published ?? 0) == 0 && Date() < opening {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        framesBefore = try publishedFrames(for: account)
        bodiesBefore = counter.evaluations; publishesBefore = publishes; cpuBefore = cpuSeconds()

        opening = Date().addingTimeInterval(15)
        while Date() < opening { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(client.state, .streaming, "the stream has to be up before any cost is attributed to a frame")
        XCTAssertGreaterThan(client.surfaceSize.width, 0, "a baseline frame has to land")
        let burst = report("opening the stream", 15, try sample())

        let settledDeadline = Date().addingTimeInterval(10)
        while Date() < settledDeadline { try await Task.sleep(nanoseconds: 100_000_000) }
        let settled = report("a settled still desktop", 10, try sample())

        XCTAssertGreaterThanOrEqual(burst.frames, 8,
            "only \(burst.frames) frames were published in the fifteen seconds after the stream opened: no picture arrived, so a verdict about the cost of one would be vacuous")
        // The assertion is on publishes, not on the probe's own body count: this
        // process never puts the hosting view in a window, so SwiftUI does not re-run
        // `body` and that counter reads 0 in both versions (it is printed because a
        // window in a future harness would make it meaningful). `objectWillChange` is
        // the signal SwiftUI re-renders on, and it is the thing a frame must not
        // raise: measured 48 for 14 frames before the fix, 5 for 14 after.
        XCTAssertLessThanOrEqual(Double(burst.publishes), max(8, Double(burst.frames) / 4),
            "\(burst.publishes) published changes for \(burst.frames) frames: the frame path is talking to the interface once per frame")
        // The settled desktop is the case the owner reported, and the one where a
        // per-frame publisher is pure cost: nothing on screen is moving at all.
        XCTAssertLessThanOrEqual(Double(settled.publishes), max(3, Double(settled.frames)),
            "a settled desktop cost \(settled.publishes) published changes for \(settled.frames) frames")
    }
}
