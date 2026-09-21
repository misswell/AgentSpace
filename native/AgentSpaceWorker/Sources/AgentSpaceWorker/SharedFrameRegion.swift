import Darwin
import Foundation
import AgentSpaceCore

@_silgen_name("shm_open")
private func agentSpaceShmOpen(_ name: UnsafePointer<CChar>, _ flags: Int32, _ mode: mode_t) -> Int32

/// Anonymous POSIX shared memory. The name is unlinked immediately after mmap;
/// the controller can obtain it only through SCM_RIGHTS on the authenticated
/// frame socket.
final class SharedFrameRegion {
    let fd: Int32
    let pointer: UnsafeMutableRawPointer
    let size: Int
    let payloadCapacity: Int
    let surfaceGeneration: UInt64

    init(width: Int, height: Int, surfaceGeneration: UInt64) throws {
        let pixelResult = width.multipliedReportingOverflow(by: height)
        let byteResult = pixelResult.partialValue.multipliedReportingOverflow(by: 4)
        guard width > 0, height > 0, !pixelResult.overflow, !byteResult.overflow else {
            throw AgentSpaceError(code: .badRequest, message: "invalid shared surface dimensions")
        }
        payloadCapacity = byteResult.partialValue
        size = SharedFrameLayout.regionSize(payloadCapacity: payloadCapacity)
        self.surfaceGeneration = surfaceGeneration
        let name = "/agentspace-\(UUID().uuidString)"
        let created = name.withCString { agentSpaceShmOpen($0, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR) }
        guard created >= 0 else { throw AgentSpaceError(code: .internalError, message: "shm_open failed: \(String(cString: strerror(errno)))") }
        fd = created
        guard ftruncate(fd, off_t(size)) == 0 else { Darwin.close(fd); shm_unlink(name); throw AgentSpaceError(code: .internalError, message: "ftruncate shared frame failed") }
        let mapped = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard mapped != MAP_FAILED else { Darwin.close(fd); shm_unlink(name); throw AgentSpaceError(code: .internalError, message: "mmap shared frame failed") }
        pointer = mapped!
        memset(pointer, 0, size)
        shm_unlink(name)
    }

    deinit { munmap(pointer, size); Darwin.close(fd) }

    func slotPointer(_ slot: Int) -> UnsafeMutableRawPointer {
        pointer.advanced(by: SharedFrameLayout.slotOffset(slot, payloadCapacity: payloadCapacity))
    }
}
