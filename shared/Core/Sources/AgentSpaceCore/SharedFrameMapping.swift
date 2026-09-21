import Darwin
import Foundation

/// A viewer's read-only map of a worker's shared frame region.
///
/// This is the half of the protocol that cannot be checked by asking the object
/// how big it is. The descriptor arrives over SCM_RIGHTS with no name attached,
/// and `fstat` on it reports what the kernel *rounded up to*, not what the writer
/// laid out — so every offset here comes from `SharedFrameGeometry` for the
/// dimensions the transport header names, and the kernel's larger number is used
/// for one purpose only: proving a read cannot run past the mapping.
public final class SharedFrameMapping {
    public let fd: Int32
    public let pointer: UnsafeRawPointer
    /// Bytes the kernel actually backs. A bound on what may be read, never an
    /// input to the layout — see `SharedFrameGeometry`.
    public let mappedCapacity: Int

    public init(fd: Int32) throws {
        var status = stat()
        guard fstat(fd, &status) == 0, status.st_size > 0, status.st_size <= off_t(Int.max) else { Darwin.close(fd); throw AgentSpaceError(code: .badRequest, message: "invalid shared frame descriptor") }
        self.fd = fd; self.mappedCapacity = Int(status.st_size)
        let mapped = mmap(nil, mappedCapacity, PROT_READ, MAP_SHARED, fd, 0)
        guard mapped != MAP_FAILED else { Darwin.close(fd); throw AgentSpaceError(code: .internalError, message: "could not map shared frame memory") }
        pointer = UnsafeRawPointer(mapped!)
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: pointer), mappedCapacity); Darwin.close(fd) }

    public func frame(notice: SharedFrameNotice, header transport: FrameHeader) throws -> (SharedFrameSlotHeader, [SharedPatchDescriptor]) {
        let width = Int(transport.width), height = Int(transport.height)
        func fault(_ kind: SharedFrameMappingFault.Kind, logical: Int? = nil) -> SharedFrameMappingFault {
            SharedFrameMappingFault(kind: kind, width: width, height: height, logicalRegionSize: logical,
                                    noticeMappingSize: Int(notice.mappingSize), mappedCapacity: mappedCapacity,
                                    slot: Int(notice.slotIndex), generation: notice.surfaceGeneration, sequence: transport.sequence)
        }
        guard width > 0, height > 0 else { throw fault(.invalidDimensions) }
        let geometry = try SharedFrameGeometry.make(width: width, height: height)
        guard notice.slotIndex < UInt16(SharedFrameLayout.slotCount) else { throw fault(.invalidSlot, logical: geometry.regionSize) }
        // Logical against logical: the notice carries the writer's layout size, so
        // this comparison is the one that catches two ends disagreeing about where
        // slot 1 begins. It must never be made against `mappedCapacity`, which
        // Darwin is free to have rounded above the requested size.
        guard notice.mappingSize == UInt32(geometry.regionSize) else { throw fault(.logicalSizeMismatch, logical: geometry.regionSize) }
        guard geometry.regionSize <= mappedCapacity else { throw fault(.capacityTooSmall, logical: geometry.regionSize) }

        let slotOffset = geometry.slotOffset(Int(notice.slotIndex))
        guard slotOffset + SharedFrameSlotHeader.byteCount <= geometry.regionSize else { throw fault(.descriptorOutOfBounds, logical: geometry.regionSize) }
        let slotHeader = try SharedFrameSlotHeader(decoding: Data(bytes: pointer.advanced(by: slotOffset), count: SharedFrameSlotHeader.byteCount))
        // The dimensions belong here as much as the sequence does: a slot written
        // for another surface size is pixels at the wrong stride, and the geometry
        // above — which every offset below is derived from — is only the frame
        // header's opinion unless the buffer itself agrees.
        guard slotHeader.sequence == transport.sequence, slotHeader.surfaceGeneration == notice.surfaceGeneration,
              slotHeader.frameKind == notice.frameKind, slotHeader.width == transport.width, slotHeader.height == transport.height
        else { throw fault(.metadataMismatch, logical: geometry.regionSize) }
        guard slotHeader.patchCount <= UInt16(SharedFrameLayout.maximumPatchCount) else { throw fault(.patchCountInvalid, logical: geometry.regionSize) }

        var patches: [SharedPatchDescriptor] = []
        for index in 0..<Int(slotHeader.patchCount) {
            let offset = slotOffset + SharedFrameSlotHeader.byteCount + index * SharedPatchDescriptor.byteCount
            guard offset + SharedPatchDescriptor.byteCount <= geometry.regionSize else { throw fault(.descriptorOutOfBounds, logical: geometry.regionSize) }
            patches.append(try SharedPatchDescriptor(decoding: Data(bytes: pointer.advanced(by: offset), count: SharedPatchDescriptor.byteCount)))
        }
        try SharedFrameLayout.validate(header: slotHeader, patches: patches, regionSize: geometry.regionSize)
        return (slotHeader, patches)
    }
}
