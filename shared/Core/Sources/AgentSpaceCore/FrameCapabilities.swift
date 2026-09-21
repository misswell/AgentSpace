import Foundation

public enum FrameCapability: String, Codable, CaseIterable, Sendable {
    case sharedBGRA
    case h264
    case persistentJPEG
}

public enum FramePreference: String, Codable, Sendable { case auto, delta, video }

public struct FrameOpenConfiguration: Equatable, Sendable {
    public var target: CaptureTarget
    public var maxFPS: Int
    public var targetPixelWidth: Int
    public var targetPixelHeight: Int
    public var preferredMode: FramePreference

    public init(target: CaptureTarget, maxFPS: Int = 15, targetPixelWidth: Int = 0, targetPixelHeight: Int = 0, preferredMode: FramePreference = .auto) {
        self.target = target; self.maxFPS = maxFPS
        self.targetPixelWidth = targetPixelWidth; self.targetPixelHeight = targetPixelHeight
        self.preferredMode = preferredMode
    }
}

public struct FrameHello: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var spaceID: UUID
    public var streamID: UUID
    public var token: String
    public var clientPID: Int32
    public var capabilities: [FrameCapability]

    public init(protocolVersion: Int, spaceID: UUID, streamID: UUID, token: String, clientPID: Int32, capabilities: [FrameCapability]) {
        self.protocolVersion = protocolVersion; self.spaceID = spaceID; self.streamID = streamID
        self.token = token; self.clientPID = clientPID; self.capabilities = capabilities
    }
}

public struct FrameHelloAck: Codable, Equatable, Sendable {
    public var workerInstanceID: UUID
    public var sessionGeneration: UInt64
    public var supportedFrameModes: [FrameCapability]

    public init(workerInstanceID: UUID, sessionGeneration: UInt64, supportedFrameModes: [FrameCapability]) {
        self.workerInstanceID = workerInstanceID; self.sessionGeneration = sessionGeneration
        self.supportedFrameModes = supportedFrameModes
    }
}

public struct FrameHandshakeExpectation: Sendable {
    public var spaceID: UUID
    public var streamID: UUID
    public var token: String
    public var protocolVersion: Int
    public var peerUID: uid_t
    public var workerInstanceID: UUID
    public var sessionGeneration: UInt64

    public init(spaceID: UUID, streamID: UUID, token: String, protocolVersion: Int, peerUID: uid_t, workerInstanceID: UUID, sessionGeneration: UInt64) {
        self.spaceID = spaceID; self.streamID = streamID; self.token = token
        self.protocolVersion = protocolVersion; self.peerUID = peerUID
        self.workerInstanceID = workerInstanceID; self.sessionGeneration = sessionGeneration
    }

    public func validate(_ hello: FrameHello, actualPeerUID: uid_t) throws {
        guard hello.protocolVersion == protocolVersion else { throw AgentSpaceError(code: .protocolMismatch, message: "frame protocol mismatch") }
        guard hello.spaceID == spaceID, hello.streamID == streamID else { throw AgentSpaceError(code: .unauthorized, message: "frame stream identity mismatch") }
        guard SessionToken(hex: token).matches(hello.token) else { throw AgentSpaceError(code: .unauthorized, message: "incorrect frame token") }
        guard actualPeerUID == peerUID else { throw AgentSpaceError(code: .unauthorized, message: "frame socket peer uid mismatch") }
    }
}

public struct FrameReconnectState: Sendable {
    public private(set) var workerInstanceID: UUID?
    public private(set) var sessionGeneration: UInt64?
    public private(set) var surfaceGeneration: UInt64?
    public private(set) var requiresFullFrame = true

    public init() {}

    /// True means prior mappings must be discarded.
    public mutating func acceptHandshake(workerInstanceID: UUID, sessionGeneration: UInt64) -> Bool {
        let changed = self.workerInstanceID != nil && (self.workerInstanceID != workerInstanceID || self.sessionGeneration != sessionGeneration)
        if self.workerInstanceID == nil || changed {
            self.workerInstanceID = workerInstanceID; self.sessionGeneration = sessionGeneration
            surfaceGeneration = nil; requiresFullFrame = true
            return true
        }
        return false
    }

    public mutating func didMapSurface(generation: UInt64) { surfaceGeneration = generation }
    public mutating func didAcceptFullFrame() { requiresFullFrame = false }
    public mutating func disconnected() { surfaceGeneration = nil; requiresFullFrame = true }
}
