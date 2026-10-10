import CoreGraphics

/// The part of a frame stream the interface is allowed to hear about.
///
/// A frame arrives thirty to sixty times a second, and every write to a
/// `@Published` property re-renders the views observing that stream — for a viewer
/// that is a layout pass and a cursor-rect invalidation on the main thread, which is
/// also the thread that has to service the person's hand. Measured with a 4K stream
/// open over a *still* desktop, the app was spending 92.4% of a core on that while
/// its Worker spent 0.5% (§382): the picture was not late, the viewer was re-rendering.
///
/// So this holds the one question the frame loop needs answered — has anything an
/// interface actually reads changed? — and says "no" far more often than frames
/// arrive.
public struct FrameSurfaceStatus: Sendable {
    /// The size last handed to the interface.
    public private(set) var size: CGSize = .zero
    /// True once an error or a notice has been shown, so the first frame that makes
    /// it untrue is still obliged to take it back. Without this field the honest way
    /// to keep retracting a stale message would be to publish the size every frame,
    /// which is the cost this type exists to remove.
    public private(set) var needsRetraction = false

    public init() {}

    /// Called once per delivered frame. Anything `nil` is nothing to say: the
    /// caller must not touch a published property for it.
    public mutating func accept(_ value: CGSize) -> FrameSurfaceChange {
        let sizeChanged = size != value
        let retract = needsRetraction
        if sizeChanged { size = value }
        if retract { needsRetraction = false }
        return FrameSurfaceChange(newSize: sizeChanged ? value : nil, retractStatus: retract)
    }

    /// An error or a notice just reached the interface.
    public mutating func noteStatusShown() { needsRetraction = true }
}

/// What one frame is worth to the interface. `newSize == nil` and
/// `retractStatus == false` together mean the frame is paint only.
public struct FrameSurfaceChange: Equatable, Sendable {
    public var newSize: CGSize?
    public var retractStatus: Bool

    public init(newSize: CGSize?, retractStatus: Bool) {
        self.newSize = newSize
        self.retractStatus = retractStatus
    }

    /// Whether anything published needs to move.
    public var isWorthPublishing: Bool { newSize != nil || retractStatus }
}
