import Foundation

// The client transport lives in Core, not in the CLI, because the GUI and the
// MCP server speak the identical protocol (plan §49: one core API, not three
// implementations). The CLI is just one caller.

import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// The CLI's transport: one JSON line over the Space's unix socket, one
/// response line back. Plan §20/§21.
///
/// Deliberately the *same* transport the GUI and the MCP server use. The plan's
/// §49 requires GUI, CLI and MCP to sit on one core API rather than three
/// implementations, and this type is that seam: if the CLI can do it, so can
/// they, through the same request.
public struct WorkerClient {
    public let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public enum ClientError: Error, CustomStringConvertible {
        case socketFailed(String)
        case connectFailed(String)
        case socketMissing(String)
        case writeFailed(String)
        case readFailed(String)
        case emptyResponse

        public var description: String {
            switch self {
            case .socketFailed(let m): return "socket() failed: \(m)"
            case .connectFailed(let m): return "could not connect: \(m)"
            case .socketMissing(let path): return "no socket at \(path)"
            case .writeFailed(let m): return "write failed: \(m)"
            case .readFailed(let m): return "read failed: \(m)"
            case .emptyResponse: return "the worker closed the connection without answering"
            }
        }
    }

    /// Send one request and return the decoded response.
    public func call(
        method: String,
        params: JSONValue = .object([:]),
        token: String?,
        timeout: Double = AgentSpaceEnvironment.socketTimeoutSeconds
    ) throws -> RPCResponse {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw ClientError.socketMissing(socketPath)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ClientError.socketFailed(String(cString: strerror(errno)))
        }
        defer { close(fd) }

        // A total deadline rather than a per-call one, so a worker that accepts
        // and then stalls cannot hang the CLI forever.
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < 104 else {
            throw ClientError.connectFailed("socket path too long (\(pathBytes.count) bytes)")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { chars in
                for (i, byte) in pathBytes.enumerated() { chars[i] = CChar(bitPattern: byte) }
                chars[pathBytes.count] = 0
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw ClientError.connectFailed(String(cString: strerror(errno)))
        }

        let request = RPCRequest(requestId: UUID().uuidString, token: token, method: method, params: params)
        let payload = try RPCCodec.encodeLine(request)
        try payload.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n > 0 { sent += n; continue }
                if n < 0 && errno == EINTR { continue }
                throw ClientError.writeFailed(String(cString: strerror(errno)))
            }
        }

        // Read the response line. Screenshots come back base64 inside one line,
        // so the cap is generous.
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw ClientError.readFailed("timed out after \(Int(timeout))s waiting for the worker")
                }
                throw ClientError.readFailed(String(cString: strerror(errno)))
            }
            if n == 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.contains(Framing.newline) || buffer.count > Framing.maxResponseBytes { break }
        }

        if let newline = buffer.firstIndex(of: Framing.newline) {
            buffer = buffer[..<newline]
        }
        guard !buffer.isEmpty else { throw ClientError.emptyResponse }

        switch RPCCodec.decodeResponse(buffer) {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}

/// Resolves a Space reference to everything needed to talk to its worker.
public struct SpaceConnection {
    public let space: AgentSpace
    public let paths: RuntimePaths
    public let token: String?

    public init(space: AgentSpace, socketPath: String? = nil) {
        self.space = space
        self.paths = AgentSpaceEnvironment.paths(spaceID: space.id, socketPath: socketPath)
        self.token = TokenStore.read(from: self.paths.tokenPath)?.hex
    }

    public var client: WorkerClient { WorkerClient(socketPath: paths.socketPath) }
}
