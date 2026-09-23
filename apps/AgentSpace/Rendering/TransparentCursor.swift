import AppKit
import AgentSpaceCore

/// A 1×1 transparent cursor, and the rules for using it.
///
/// The local pointer over a captured remote surface has to disappear — a person
/// driving the agent's desktop must see one cursor, and it must be the agent's.
/// There are two ways to do that on macOS and only one of them is safe here:
///
/// - `NSCursor.hide()` / `unhide()` maintain a *process-wide* hide count. Any
///   path that hides without a matching unhide — a window closed while the
///   pointer was over the picture, a worker that died mid-gesture, a fast user
///   switch, an exception between the two calls — leaves the person with no
///   pointer anywhere on their Mac, including outside AgentSpace. The count is
///   also shared with AppKit's own uses of it, so even a balanced pair can
///   leave it wrong.
/// - A cursor rect with a transparent cursor is scoped to one rectangle of one
///   view, and AppKit re-evaluates cursor rects whenever the pointer moves. It
///   cannot leak: the worst outcome of a missed `resetCursorRects()` is that the
///   *ordinary* cursor shows, which is the state the person wants anyway.
///
/// So this type is the only cursor the product ever sets, it is never used
/// process-wide, and every path that ends capture goes through
/// `RemoteSurfaceNSView.resetCursorRects()` rather than an unhide.
enum TransparentCursor {
    /// 1×1 fully transparent. Built once: `NSCursor` construction touches AppKit
    /// state, and a cursor rect is re-asked on every pointer move.
    static let cursor: NSCursor = {
        let size = NSSize(width: 1, height: 1)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: .zero)
    }()

    /// Whether the pointer is allowed to be invisible: only over a captured
    /// surface, and only while this app is the active one. A person who switches
    /// to another app must not find their cursor stolen by a background window.
    static func shouldHide(over surface: Bool, appActive: Bool) -> Bool {
        surface && appActive
    }
}
