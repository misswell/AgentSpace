import Darwin
import Foundation
import AgentSpaceCore

final class FrameSocketConnection {
    let fd: Int32

    init(path: String) throws {
        guard RuntimePaths.socketPathFits(path) else { throw AgentSpaceError(code: .internalError, message: "frame socket path is too long") }
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw AgentSpaceError(code: .workerOffline, message: "could not create frame socket") }
        var address = sockaddr_un(); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutablePointer(to: &address.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { chars in for (index, byte) in bytes.enumerated() { chars[index] = CChar(bitPattern: byte) }; chars[bytes.count] = 0 } }
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0 else { let message = String(cString: strerror(errno)); Darwin.close(socketFD); throw AgentSpaceError(code: .workerOffline, message: "could not connect to frame socket: \(message)") }
        fd = socketFD
    }

    deinit { shutdown(fd, SHUT_RDWR); Darwin.close(fd) }

    func sendLine<T: Encodable>(_ value: T) throws { try writeAll(FrameTransportCoding.line(value)) }
    func readLine(limit: Int = 16 * 1024) throws -> Data {
        var result = Data(), byte: UInt8 = 0
        while result.count < limit {
            let count = Darwin.read(fd, &byte, 1)
            if count == 1 { if byte == 0x0a { return result }; result.append(byte); continue }
            if count < 0 && errno == EINTR { continue }
            throw AgentSpaceError(code: .workerOffline, message: "frame socket disconnected")
        }
        throw AgentSpaceError(code: .badRequest, message: "frame handshake exceeded its limit")
    }

    func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count), offset = 0
        try data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            while offset < count {
                let readCount = Darwin.read(fd, base.advanced(by: offset), count - offset)
                if readCount > 0 { offset += readCount } else if readCount < 0 && errno == EINTR { continue } else { throw AgentSpaceError(code: .workerOffline, message: "frame socket disconnected") }
            }
        }
        return data
    }

    func receiveFileDescriptor() throws -> Int32 {
        var marker: UInt8 = 0
        let headerSize = MemoryLayout<cmsghdr>.size, dataSize = MemoryLayout<Int32>.size
        let alignment = MemoryLayout<size_t>.size
        var control = [UInt8](repeating: 0, count: ((headerSize + dataSize + alignment - 1) / alignment) * alignment)
        let received: Int = try withUnsafeMutablePointer(to: &marker) { markerPointer in
            var vector = iovec(iov_base: UnsafeMutableRawPointer(markerPointer), iov_len: 1)
            return try withUnsafeMutablePointer(to: &vector) { vectorPointer in
                control.withUnsafeMutableBytes { bytes in
                    var message = msghdr(msg_name: nil, msg_namelen: 0, msg_iov: vectorPointer, msg_iovlen: 1, msg_control: bytes.baseAddress, msg_controllen: socklen_t(bytes.count), msg_flags: 0)
                    return recvmsg(fd, &message, 0)
                }
            }
        }
        guard received == 1, marker == 0x46 else { throw AgentSpaceError(code: .workerOffline, message: "frame server did not pass shared memory") }
        return control.withUnsafeBytes { bytes in bytes.baseAddress!.advanced(by: headerSize).assumingMemoryBound(to: Int32.self).pointee }
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if count > 0 { offset += count } else if count < 0 && errno == EINTR { continue } else { throw AgentSpaceError(code: .workerOffline, message: "frame socket disconnected") }
            }
        }
    }
}
