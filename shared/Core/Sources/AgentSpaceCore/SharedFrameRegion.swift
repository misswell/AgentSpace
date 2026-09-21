import Darwin
import Foundation

@_silgen_name("shm_open")
private func agentSpaceShmOpen(_ name: UnsafePointer<CChar>, _ flags: Int32, _ mode: mode_t) -> Int32

/// A shared frame buffer the kernel refused.
///
/// The typed form of the failure; `failure` is what the worker keeps and
/// answers `frame.stats` with, and `agentSpaceError` is what leaves over the
/// socket — an ordinary `INTERNAL_ERROR` envelope carrying the same facts as
/// text. A dedicated wire code would be tidier to switch on and would make every
/// older viewer fail to decode the error at all, which is a worse failure than
/// the one being reported.
public struct SharedFrameAllocationError: Error, Equatable, Sendable {
    public let operation: SharedFrameAllocationOperation
    /// Captured on the line after the syscall, while it still describes that
    /// syscall — see `SharedFrameAllocation`.
    public let systemErrorCode: Int32
    public var requestedBytes: Int
    /// Length, never content: the name is random, so a record carrying it
    /// identifies nothing, while a record carrying its length names the bug.
    public var attemptedNameBytes: Int?

    public init(operation: SharedFrameAllocationOperation, systemErrorCode: Int32,
                requestedBytes: Int = 0, attemptedNameBytes: Int? = nil) {
        self.operation = operation
        self.systemErrorCode = systemErrorCode
        self.requestedBytes = requestedBytes
        self.attemptedNameBytes = attemptedNameBytes
    }

    public var failure: SharedFrameAllocationFailure {
        SharedFrameAllocationFailure(operation: operation, systemErrorCode: systemErrorCode,
                                     requestedBytes: requestedBytes, attemptedNameBytes: attemptedNameBytes)
    }

    public var message: String { failure.message }

    public var agentSpaceError: AgentSpaceError { AgentSpaceError(code: .internalError, message: message) }
}

/// Anonymous POSIX shared memory holding two frame slots. The name is unlinked
/// as soon as the mapping exists, so the region is reachable only through its
/// descriptor, and a controller can obtain that only through SCM_RIGHTS on the
/// authenticated frame socket.
public final class SharedFrameRegion {
    /// A 96-bit token does not collide, so this is not a probability budget. It
    /// is the promise that a name already in use is retried instead of either
    /// failing the stream or — with `O_EXCL` dropped — writing into a buffer
    /// somebody else holds.
    public static let maximumCreationAttempts = 8

    public let fd: Int32
    public let pointer: UnsafeMutableRawPointer
    public let size: Int
    public let payloadCapacity: Int
    public let surfaceGeneration: UInt64

    public convenience init(width: Int, height: Int, surfaceGeneration: UInt64) throws {
        try self.init(width: width, height: height, surfaceGeneration: surfaceGeneration, makeName: SharedMemoryName.make)
    }

    /// `makeName` is a seam, not a knob: production always passes
    /// `SharedMemoryName.make`, a test passes a name the kernel will refuse or
    /// one already taken. Those are the branches that decide whether a failed
    /// stream leaks an object into the global namespace, and nothing short of
    /// handing the allocator a name reaches them.
    init(width: Int, height: Int, surfaceGeneration: UInt64, makeName: () -> String) throws {
        let pixels = width.multipliedReportingOverflow(by: height)
        let bytes = pixels.partialValue.multipliedReportingOverflow(by: 4)
        guard width > 0, height > 0, !pixels.overflow, !bytes.overflow else {
            throw AgentSpaceError(code: .badRequest, message: "invalid shared surface dimensions")
        }
        let regionSize = SharedFrameLayout.regionSize(payloadCapacity: bytes.partialValue)
        let allocation = try Self.allocate(regionSize: regionSize, makeName: makeName)
        self.fd = allocation.fd
        self.size = regionSize
        self.payloadCapacity = bytes.partialValue
        self.surfaceGeneration = surfaceGeneration
        let mapped = mmap(nil, regionSize, PROT_READ | PROT_WRITE, MAP_SHARED, allocation.fd, 0)
        guard mapped != MAP_FAILED else {
            let code = errno
            Darwin.close(allocation.fd)
            shm_unlink(allocation.name)
            throw Self.rejection(operation: .map, code: code, regionSize: regionSize)
        }
        pointer = mapped!
        memset(pointer, 0, regionSize)
        // The name is gone; `fd` is the only handle to it.
        shm_unlink(allocation.name)
    }

    deinit { munmap(pointer, size); Darwin.close(fd) }

    public func slotPointer(_ slot: Int) -> UnsafeMutableRawPointer {
        pointer.advanced(by: SharedFrameLayout.slotOffset(slot, payloadCapacity: payloadCapacity))
    }

    // MARK: Allocation

    /// Create and size the object, returning both the descriptor and the name
    /// still pointing at it — unlinking is the caller's, because only the caller
    /// knows whether the mapping that follows succeeded.
    ///
    /// Every path out of here that throws has already released the descriptor and
    /// removed the name: a failure that left a named object behind would be a
    /// leak no later stream could clean up.
    static func allocate(regionSize: Int, makeName: () -> String = SharedMemoryName.make,
                         attempts: Int = maximumCreationAttempts) throws -> (fd: Int32, name: String) {
        var lastAttemptedNameBytes = 0
        for _ in 0..<max(1, attempts) {
            let name = makeName()
            lastAttemptedNameBytes = name.utf8.count
            // The name-length rule is decided here, in the open, rather than
            // discovered by the kernel: `shm_open` would answer `ENAMETOOLONG`,
            // and a stream that dies at the first syscall looks like a machine
            // problem rather than a name that could never have fitted.
            if let refusal = rejection(name: name, regionSize: regionSize) { throw refusal }
            let opened = openDescriptor(as: name)
            guard opened.fd >= 0 else {
                if opened.code == EEXIST { continue }
                throw rejection(operation: .create, code: opened.code, nameBytes: name.utf8.count)
            }
            if ftruncate(opened.fd, off_t(regionSize)) != 0 {
                let code = errno
                Darwin.close(opened.fd)
                shm_unlink(name)
                throw rejection(operation: .resize, code: code, regionSize: regionSize)
            }
            return (opened.fd, name)
        }
        // Every attempt collided, which is not the same as the single collision
        // the retry exists to absorb — so it reports the exhaustion rather than
        // pretending one more name would have worked.
        throw rejection(operation: .create, code: EEXIST, nameBytes: lastAttemptedNameBytes)
    }

    /// The pure half: the two design mistakes this allocator can be written
    /// into — a name too long for Darwin, and a region size the layout cannot
    /// represent — decided without a syscall, so they are assertable anywhere a
    /// test runs rather than only where a kernel disagrees.
    static func rejection(name: String, regionSize: Int) -> SharedFrameAllocationError? {
        if name.utf8.count > SharedMemoryName.darwinMaximumBytes {
            return SharedFrameAllocationError(operation: .create, systemErrorCode: ENAMETOOLONG,
                                              attemptedNameBytes: name.utf8.count)
        }
        guard regionSize > 0, off_t(regionSize) > 0 else {
            return SharedFrameAllocationError(operation: .resize, systemErrorCode: EINVAL, requestedBytes: regionSize)
        }
        return nil
    }

    private static func rejection(operation: SharedFrameAllocationOperation, code: Int32,
                                  regionSize: Int = 0, nameBytes: Int = 0) -> SharedFrameAllocationError {
        SharedFrameAllocationError(operation: operation, systemErrorCode: code,
                                   requestedBytes: regionSize,
                                   attemptedNameBytes: nameBytes > 0 ? nameBytes : nil)
    }

    /// `errno` is read inside this closure, on the line after the syscall
    /// returns, before anything else — including the string building at the call
    /// site — can run over it.
    private static func openDescriptor(as name: String) -> (fd: Int32, code: Int32) {
        var code: Int32 = 0
        let descriptor = name.withCString { address in
            let result = agentSpaceShmOpen(address, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR)
            code = errno
            return result
        }
        return (descriptor, code)
    }
}
