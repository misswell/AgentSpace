import AppKit
import AgentSpaceCore

/// Turns the desktop viewer's pointer gestures into `input` calls.
///
/// The viewer is a person driving the agent's own desktop, so it goes through the
/// same `input` operation an agent goes through. That is what keeps the two honest
/// with each other: a gesture here is refused by the very human lease a Fusion
/// proxy claims, and a coordinate that would be invalid for an agent is invalid
/// here rather than silently landing somewhere else.
///
/// Travel is the one gesture that is *state* rather than an event, so it goes
/// through the same coalescer a proxy uses — one hover in flight, the newest
/// position behind it, and never a queue for the click that ended the wave to wait
/// behind. A deliberate gesture bypasses it and keeps its own order.
@MainActor
final class DesktopViewerInput: ObservableObject {
    /// A refusal worth interrupting the desktop for. A skipped hover is not one:
    /// pointer travel is refused by design while someone else holds the lease, and
    /// replacing a working desktop with a message about a hover would be the viewer
    /// manufacturing its own problem.
    @Published private(set) var refusal: AppModel.PresentedError?

    private var space: AgentAccount?
    private var display: DisplayGeometry?
    private lazy var travel = PointerTravelCoalescer<InputAction> { [weak self] action in
        Task { @MainActor in await self?.deliverTravel(action) }
    }

    /// Where the next gesture goes, and how big that surface is in the points the
    /// input protocol means. Refreshed while the viewer renders, because the
    /// snapshot is the only thing that knows either.
    func configure(space: AgentAccount, display: DisplayGeometry) {
        self.space = space
        self.display = display
    }

    func send(_ gesture: RemotePointerGesture) {
        guard let space, let display else { return }
        switch gesture {
        case .hover(let u, let v):
            let point = Self.point(u, v, display)
            travel.offer(.move(x: point.x, y: point.y), now: Date())
            travel.pump()

        case .click(let u, let v, let button, let count, let modifiers):
            let point = Self.point(u, v, display)
            send(.click(x: point.x, y: point.y, button: button, count: count, modifiers: modifiers),
                 to: space)

        case .drag(let fromU, let fromV, let toU, let toV, let button, let modifiers):
            let press = Self.point(fromU, fromV, display)
            let release = Self.point(toU, toV, display)
            send(.drag(fromX: press.x, fromY: press.y, toX: release.x, toY: release.y,
                       button: button, modifiers: modifiers), to: space)

        case .scroll(let u, let v, let linesX, let linesY):
            let point = Self.point(u, v, display)
            send(.scroll(x: point.x, y: point.y, dx: linesX, dy: linesY), to: space)
        }
    }

    /// Positions collected for a desktop nobody is watching any more must not be
    /// posted after it.
    func reset() {
        travel.reset()
    }

    /// The gesture's fraction of the captured display, as the point on it that
    /// `input` accepts. `PreviewMapping` owns the rounding because the viewer's
    /// letterbox and a screenshot's downscale both resolve through it.
    private static func point(_ u: Double, _ v: Double, _ display: DisplayGeometry) -> (x: Double, y: Double) {
        PreviewMapping.displayPoint(u: u, v: v, displayWidth: display.width, displayHeight: display.height)
    }

    private func send(_ action: InputAction, to space: AgentAccount) {
        Task { @MainActor in
            let error = await Task.detached(priority: .userInitiated) {
                SpaceService().input(for: space, actions: [action])
            }.value
            guard let error else {
                refusal = nil
                return
            }
            refusal = AppModel.PresentedError(code: error.code.rawValue, message: error.message,
                                              fix: error.code.remediation, spaceName: space.name)
        }
    }

    private func deliverTravel(_ action: InputAction) async {
        guard let space else { return }
        _ = await Task.detached(priority: .userInitiated) {
            SpaceService().input(for: space, actions: [action])
        }.value
        // Whether or not the worker answered, the travel slot has to be released,
        // or one skipped hover silences the pointer for good.
        travel.finished()
    }
}
