import AppKit
import AgentSpaceCore

/// Compile with the App coordinator and the built AgentSpaceCore objects.
@main
struct PointerCaptureProbe {
    @MainActor static func main() {
        let coordinator = PointerCaptureCoordinator()
        coordinator.imageRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        var acceptsInput = true
        coordinator.canSettlePointer = { acceptsInput }
        var settled: [CGPoint] = []
        var began = 0
        var ended = 0
        coordinator.onPointerSettled = { settled.append($0) }
        coordinator.onCaptureBegan = { began += 1 }
        coordinator.onCaptureEnded = { ended += 1 }
        func wait(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        let first = CGPoint(x: 10, y: 10)
        let last = CGPoint(x: 40, y: 50)
        coordinator.configure(.automatic)
        coordinator.pointer(movedTo: first)
        wait(0.12)
        coordinator.pointer(movedTo: last)
        wait(0.12)
        precondition(settled.isEmpty, "movement must restart the idle deadline")
        wait(0.12)
        precondition(settled == [last] && coordinator.isControlling)
        precondition(began == 1)
        coordinator.pointer(movedTo: first)
        precondition(!coordinator.isControlling && ended == 1)
        coordinator.pointerLeftView()
        wait(0.24)
        precondition(settled.count == 1 && coordinator.state == .outside)

        coordinator.pointer(movedTo: first)
        coordinator.escape()
        wait(0.24)
        precondition(settled.count == 1 && !coordinator.isControlling)
        coordinator.pointer(movedTo: first)
        coordinator.release()
        wait(0.24)
        precondition(settled.count == 1 && coordinator.state == .outside)
        coordinator.pointer(movedTo: first)
        coordinator.configure(.fusionProxy)
        wait(0.24)
        precondition(settled.count == 1 && coordinator.state == .outside)

        coordinator.configure(.automatic)
        coordinator.pointer(movedTo: first)
        acceptsInput = false
        wait(0.24)
        precondition(settled.count == 1 && !coordinator.isControlling)
        acceptsInput = true
        coordinator.pointer(movedTo: first)
        coordinator.pressStarted()
        wait(0.24)
        precondition(settled.count == 1 && coordinator.isControlling)
        coordinator.pointer(movedTo: CGPoint(x: 120, y: 120))
        precondition(coordinator.isControlling, "a drag must keep its button")
        coordinator.pressEnded(pointerInside: false)
        precondition(coordinator.state == .outside)

        coordinator.configure(.desktop)
        coordinator.pointer(movedTo: first)
        precondition(coordinator.isControlling)
        coordinator.configure(.automatic)
        precondition(!coordinator.isControlling, "mode changes must return control")
        coordinator.pointer(movedTo: first)
        coordinator.configure(.automatic)
        wait(0.24)
        precondition(settled.count == 2, "identical policy updates must preserve idle deadline")
        print("PASS: idle debounce, final position, exit, escape, release, policy change, input revocation and drag")
    }
}
