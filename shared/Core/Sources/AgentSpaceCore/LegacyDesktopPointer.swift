import Foundation

/// Converts viewer gestures to the original input RPC understood by workers
/// that predate input.sock. Raw press phases become one click or drag on release.
public struct LegacyDesktopPointer {
    private var press: (x: Double, y: Double)?
    private var moved = false

    public init() {}
    public var hasPendingPress: Bool { press != nil }

    public mutating func reset() {
        press = nil
        moved = false
    }

    public mutating func action(for gesture: RemotePointerGesture, display: DisplayGeometry) -> InputAction? {
        func point(_ u: Double, _ v: Double) -> (x: Double, y: Double) {
            PreviewMapping.displayPoint(u: u, v: v,
                                        displayWidth: display.width, displayHeight: display.height)
        }
        switch gesture {
        case .hover(let u, let v):
            let p = point(u, v)
            return .move(x: p.x, y: p.y)
        case .click(let u, let v, let button, let count, let modifiers):
            let p = point(u, v)
            return .click(x: p.x, y: p.y, button: button, count: count, modifiers: modifiers)
        case .drag(let fromU, let fromV, let toU, let toV, let button, let modifiers):
            let from = point(fromU, fromV), to = point(toU, toV)
            return .drag(fromX: from.x, fromY: from.y, toX: to.x, toY: to.y,
                         button: button, modifiers: modifiers)
        case .pointerDown(let u, let v, _, _, _):
            press = point(u, v)
            moved = false
            return nil
        case .pointerDrag:
            if press != nil { moved = true }
            return nil
        case .pointerUp(let u, let v, let button, let count, let modifiers):
            guard let from = press else { return nil }
            let to = point(u, v)
            defer { reset() }
            if moved {
                return .drag(fromX: from.x, fromY: from.y, toX: to.x, toY: to.y,
                             button: button, modifiers: modifiers)
            }
            return .click(x: to.x, y: to.y, button: button, count: count, modifiers: modifiers)
        case .scroll(let u, let v, let dx, let dy):
            let p = point(u, v)
            return .scroll(x: p.x, y: p.y, dx: dx, dy: dy)
        }
    }
}
