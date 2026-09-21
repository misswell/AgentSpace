import Foundation

/// Where every byte of a shared frame buffer lives, computed once for both ends.
///
/// The worker needs this to write a baseline into a buffer it allocated; the
/// viewer needs the *same* numbers to read a slot out of a descriptor it was
/// handed. Neither may re-derive the layout from what it can measure locally,
/// because the two ends measure different things: the writer knows the size it
/// asked the kernel for, while the reader can only ask `fstat` about the object
/// behind the descriptor — and Darwin rounds a POSIX shm object *up* (measured on
/// this machine: `ftruncate(4096)` leaves an `st_size` of 16384). A layout
/// computed from the rounded number puts slot 1 at an offset the writer never
/// wrote, which reads as a corrupted picture rather than as an error.
///
/// So `regionSize` here is what `SharedFrameNotice.mappingSize` carries, and the
/// kernel's larger number stays what it is: an upper bound on the bytes a reader
/// may touch, never an input to the layout.
public struct SharedFrameGeometry: Equatable, Sendable {
    /// Bytes per pixel on the shared path: BGRA, no planar variant.
    public static let bytesPerPixel = 4

    public let width: Int
    public let height: Int
    /// One slot's pixel room: `width * height * 4`.
    public let payloadCapacity: Int
    /// Metadata plus payload, for one of the two slots.
    public let slotSize: Int
    /// Both slots. The logical size of the region, and the value the wire names.
    public let regionSize: Int

    public init(width: Int, height: Int, payloadCapacity: Int, slotSize: Int, regionSize: Int) {
        self.width = width; self.height = height
        self.payloadCapacity = payloadCapacity; self.slotSize = slotSize; self.regionSize = regionSize
    }

    /// The geometry a surface of these dimensions needs.
    ///
    /// Every step is overflow-checked because the result feeds both an `ftruncate`
    /// and a `UInt32` wire field: a multiplication that wraps would allocate a
    /// buffer smaller than the frames written into it, and a region the notice
    /// cannot name is a region no viewer can lay out.
    public static func make(width: Int, height: Int) throws -> SharedFrameGeometry {
        guard width > 0, height > 0 else { throw AgentSpaceError(code: .badRequest, message: "invalid shared frame dimensions") }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow else { throw AgentSpaceError(code: .badRequest, message: "shared frame pixel count overflow") }
        let payload = pixels.partialValue.multipliedReportingOverflow(by: bytesPerPixel)
        guard !payload.overflow else { throw AgentSpaceError(code: .badRequest, message: "shared frame payload overflow") }
        let slot = SharedFrameLayout.slotMetadataSize.addingReportingOverflow(payload.partialValue)
        guard !slot.overflow else { throw AgentSpaceError(code: .badRequest, message: "shared frame slot size overflow") }
        let region = slot.partialValue.multipliedReportingOverflow(by: SharedFrameLayout.slotCount)
        guard !region.overflow, region.partialValue > 0, region.partialValue <= Int(UInt32.max) else {
            throw AgentSpaceError(code: .badRequest, message: "shared frame mapping is too large")
        }
        return SharedFrameGeometry(width: width, height: height, payloadCapacity: payload.partialValue,
                                   slotSize: slot.partialValue, regionSize: region.partialValue)
    }

    /// Where slot `n` begins, in the writer's buffer and in the reader's — which is
    /// the whole point of the struct.
    public func slotOffset(_ slot: Int) -> Int { slot * slotSize }
}
