import Darwin
import Foundation
import AgentSpaceCore

final class SharedFrameMapping {
    let fd: Int32
    let pointer: UnsafeRawPointer
    let size: Int

    init(fd: Int32) throws {
        var status = stat()
        guard fstat(fd, &status) == 0, status.st_size > 0, status.st_size <= off_t(Int.max) else { Darwin.close(fd); throw AgentSpaceError(code: .badRequest, message: "invalid shared frame descriptor") }
        self.fd = fd; self.size = Int(status.st_size)
        let mapped = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0)
        guard mapped != MAP_FAILED else { Darwin.close(fd); throw AgentSpaceError(code: .internalError, message: "could not map shared frame memory") }
        pointer = UnsafeRawPointer(mapped!)
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: pointer), size); Darwin.close(fd) }

    func frame(notice: SharedFrameNotice, header transport: FrameHeader) throws -> (SharedFrameSlotHeader, [SharedPatchDescriptor]) {
        guard notice.slotIndex < UInt16(SharedFrameLayout.slotCount), notice.mappingSize == UInt32(size) else { throw AgentSpaceError(code: .badRequest, message: "shared frame notice does not match its mapping") }
        let payloadCapacity = (size / SharedFrameLayout.slotCount) - SharedFrameLayout.slotMetadataSize
        let slotOffset = SharedFrameLayout.slotOffset(Int(notice.slotIndex), payloadCapacity: payloadCapacity)
        guard slotOffset + SharedFrameSlotHeader.byteCount <= size else { throw AgentSpaceError(code: .badRequest, message: "shared frame slot is outside mapping") }
        let slotHeader = try SharedFrameSlotHeader(decoding: Data(bytes: pointer.advanced(by: slotOffset), count: SharedFrameSlotHeader.byteCount))
        guard slotHeader.sequence == transport.sequence, slotHeader.surfaceGeneration == notice.surfaceGeneration, slotHeader.frameKind == notice.frameKind else { throw AgentSpaceError(code: .badRequest, message: "shared frame metadata changed while reading") }
        var patches: [SharedPatchDescriptor] = []
        for index in 0..<Int(slotHeader.patchCount) {
            let offset = slotOffset + SharedFrameSlotHeader.byteCount + index * SharedPatchDescriptor.byteCount
            patches.append(try SharedPatchDescriptor(decoding: Data(bytes: pointer.advanced(by: offset), count: SharedPatchDescriptor.byteCount)))
        }
        try SharedFrameLayout.validate(header: slotHeader, patches: patches, regionSize: size)
        return (slotHeader, patches)
    }
}
