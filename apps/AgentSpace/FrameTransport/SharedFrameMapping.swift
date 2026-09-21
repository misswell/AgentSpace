import Darwin
import Foundation
import AgentSpaceCore

final class SharedFrameMapping {
    let fd: Int32
    let pointer: UnsafeRawPointer
    /// What the kernel actually gave the object. This is the size the worker
    /// asked for *rounded up* — measured here: `ftruncate(4096)` leaves an
    /// `st_size` of 16384 — so it is a bound on what may be read and never the
    /// number the layout is computed from. That number travels in every notice.
    let mappedSize: Int

    init(fd: Int32) throws {
        var status = stat()
        guard fstat(fd, &status) == 0, status.st_size > 0, status.st_size <= off_t(Int.max) else { Darwin.close(fd); throw AgentSpaceError(code: .badRequest, message: "invalid shared frame descriptor") }
        self.fd = fd; self.mappedSize = Int(status.st_size)
        let mapped = mmap(nil, mappedSize, PROT_READ, MAP_SHARED, fd, 0)
        guard mapped != MAP_FAILED else { Darwin.close(fd); throw AgentSpaceError(code: .internalError, message: "could not map shared frame memory") }
        pointer = UnsafeRawPointer(mapped!)
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: pointer), mappedSize); Darwin.close(fd) }

    func frame(notice: SharedFrameNotice, header transport: FrameHeader) throws -> (SharedFrameSlotHeader, [SharedPatchDescriptor]) {
        // The writer's own layout size, not `st_size`: two ends that each derived
        // the slot offsets from a number the kernel had already rounded would
        // disagree about where slot 1 begins, which is a corrupted picture rather
        // than an error. What this mapping owes the notice is enough bytes.
        guard notice.slotIndex < UInt16(SharedFrameLayout.slotCount) else { throw AgentSpaceError(code: .badRequest, message: "shared frame notice has no such slot") }
        guard let payloadCapacity = SharedFrameLayout.payloadCapacity(forRegionSize: Int(notice.mappingSize)), Int(notice.mappingSize) <= mappedSize else {
            throw AgentSpaceError(code: .badRequest, message: "shared frame notice does not fit its mapping (\(notice.mappingSize) bytes in \(mappedSize))")
        }
        let slotOffset = SharedFrameLayout.slotOffset(Int(notice.slotIndex), payloadCapacity: payloadCapacity)
        guard slotOffset + SharedFrameSlotHeader.byteCount <= mappedSize else { throw AgentSpaceError(code: .badRequest, message: "shared frame slot is outside mapping") }
        let slotHeader = try SharedFrameSlotHeader(decoding: Data(bytes: pointer.advanced(by: slotOffset), count: SharedFrameSlotHeader.byteCount))
        guard slotHeader.sequence == transport.sequence, slotHeader.surfaceGeneration == notice.surfaceGeneration, slotHeader.frameKind == notice.frameKind else { throw AgentSpaceError(code: .badRequest, message: "shared frame metadata changed while reading") }
        var patches: [SharedPatchDescriptor] = []
        for index in 0..<Int(slotHeader.patchCount) {
            let offset = slotOffset + SharedFrameSlotHeader.byteCount + index * SharedPatchDescriptor.byteCount
            patches.append(try SharedPatchDescriptor(decoding: Data(bytes: pointer.advanced(by: offset), count: SharedPatchDescriptor.byteCount)))
        }
        try SharedFrameLayout.validate(header: slotHeader, patches: patches, regionSize: Int(notice.mappingSize))
        return (slotHeader, patches)
    }
}
