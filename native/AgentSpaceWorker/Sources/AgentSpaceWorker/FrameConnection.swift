import Darwin
import Foundation
import AgentSpaceCore

final class FrameConnection {
    let fd: Int32
    private let writeLock = NSLock()
    private(set) var closed = false

    init(fd: Int32) { self.fd = fd }
    deinit { closeConnection() }

    func readLine(limit: Int = 16 * 1024) -> Data? {
        var data = Data(); var byte: UInt8 = 0
        while data.count < limit {
            let count = Darwin.read(fd, &byte, 1)
            if count == 1 { if byte == 0x0a { return data }; data.append(byte); continue }
            if count < 0 && errno == EINTR { continue }
            return nil
        }
        return nil
    }

    func sendLine<T: Encodable>(_ value: T) -> Bool {
        guard let data = try? FrameTransportCoding.line(value) else { return false }
        return send(data)
    }

    func sendFrame(header: FrameHeader, payload: Data) -> Bool { send(header.encoded() + payload) }

    func sendFileDescriptor(_ descriptor: Int32) -> Bool {
        writeLock.lock(); defer { writeLock.unlock() }
        var marker: UInt8 = 0x46
        let alignment = MemoryLayout<size_t>.size
        let headerSize = MemoryLayout<cmsghdr>.size
        let dataSize = MemoryLayout<Int32>.size
        let controlSize = ((headerSize + dataSize + alignment - 1) / alignment) * alignment
        var control = [UInt8](repeating: 0, count: controlSize)
        return withUnsafeMutablePointer(to: &marker) { markerPointer in
            var vector = iovec(iov_base: UnsafeMutableRawPointer(markerPointer), iov_len: 1)
            return withUnsafeMutablePointer(to: &vector) { vectorPointer in
                control.withUnsafeMutableBytes { bytes in
                    guard let base = bytes.baseAddress else { return false }
                    let header = base.assumingMemoryBound(to: cmsghdr.self)
                    header.pointee.cmsg_len = socklen_t(headerSize + dataSize)
                    header.pointee.cmsg_level = SOL_SOCKET
                    header.pointee.cmsg_type = SCM_RIGHTS
                    base.advanced(by: headerSize).assumingMemoryBound(to: Int32.self).pointee = descriptor
                    var message = msghdr(msg_name: nil, msg_namelen: 0, msg_iov: vectorPointer, msg_iovlen: 1, msg_control: base, msg_controllen: socklen_t(controlSize), msg_flags: 0)
                    return sendmsg(fd, &message, 0) == 1
                }
            }
        }
    }

    private func send(_ data: Data) -> Bool {
        writeLock.lock(); defer { writeLock.unlock() }
        guard !closed else { return false }
        return data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return true }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if written > 0 { offset += written } else if written < 0 && errno == EINTR { continue } else { closed = true; return false }
            }
            return true
        }
    }

    func closeConnection() { if !closed { closed = true; shutdown(fd, SHUT_RDWR); Darwin.close(fd) } }
}
