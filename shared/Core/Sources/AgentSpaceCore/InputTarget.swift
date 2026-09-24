import Foundation

/// What a fast-channel packet is aimed at: the whole display, or one window.
///
/// The two hosts of a remote surface mean different things by "here": the
/// desktop viewer knows the agent's display geometry and sends points of it,
/// while a Fusion proxy looks at one window whose position it deliberately does
/// not track — it sends fractions of that window and lets the worker resolve
/// them against the frame the window has *now*. Carrying the target in every
/// packet is what lets one persistent connection serve both, and what keeps a
/// drag bound to the window it started in even if the pointer leaves it.
public enum InputTarget: Equatable, Hashable, Sendable {
    case desktop
    case display(UInt32)
    /// The session's current Retina display, resolved by the worker per packet.
    ///
    /// A `CGDirectDisplayID` is not durable: it changes across display sleep,
    /// mode changes and re-enumeration (measured 22 → 58 on one Mac in one
    /// afternoon), and a viewer that pinned the id it saw when the desktop
    /// opened had every later click refused — the report behind this target.
    /// The role is what the viewer means; the worker owns the id.
    case retinaDisplay
    case window(WindowIdentity)

    /// Whether coordinates in a packet with this target are display points
    /// (`false`) or 0…1 fractions of the window's frame (`true`).
    public var isWindowRelative: Bool {
        if case .window = self { return true }
        return false
    }

    /// A human-readable form for the log. Never a wire field.
    public var logDescription: String {
        switch self {
        case .desktop: return "desktop"
        case .display(let id): return "display \(id)"
        case .retinaDisplay: return "retina display"
        case .window(let identity): return "window \(identity.windowID) pid \(identity.pid) gen \(identity.generation)"
        }
    }

    public init(decoding reader: inout BinaryReader) throws {
        let kind = try reader.byte()
        switch kind {
        case 0:
            self = .desktop
        case 1:
            let pid = try reader.int32()
            let windowID = try reader.integer(UInt32.self)
            let generation = try reader.integer(UInt64.self)
            self = .window(WindowIdentity(pid: pid, windowID: windowID, generation: generation))
        case 2:
            self = .display(try reader.integer(UInt32.self))
        case 3:
            self = .retinaDisplay
        default:
            throw AgentSpaceError(code: .badRequest, message: "unknown input target kind \(kind)")
        }
    }

    public func encode(into writer: inout BinaryWriter) {
        switch self {
        case .desktop:
            writer.append(UInt8(0))
        case .display(let id):
            writer.append(UInt8(2))
            writer.append(id)
        case .retinaDisplay:
            writer.append(UInt8(3))
        case .window(let identity):
            writer.append(UInt8(1))
            writer.append(identity.pid)
            writer.append(identity.windowID)
            writer.append(identity.generation)
        }
    }

    /// Resolve a packet's coordinates into display points.
    ///
    /// A window target re-reads the window's current frame, which is the whole
    /// point: the proxy sent a fraction of the window as it stands now, not of
    /// where it stood when the proxy last looked. `InputTargetResolution` owns
    /// the arithmetic so the worker's live path and the tests use one copy.
    public func resolve(x: Double, y: Double, canvas: InputCanvas?) throws -> (x: Double, y: Double) {
        switch self {
        case .desktop, .retinaDisplay:
            guard x.isFinite, y.isFinite else {
                throw AgentSpaceError(code: .invalidCoordinate, message: "pointer coordinates must be finite")
            }
            return (x, y)
        case .display:
            throw AgentSpaceError(code: .invalidTarget,
                message: "a display-target packet must be resolved against its live display origin")
        case .window:
            guard let canvas else {
                throw AgentSpaceError(
                    code: .invalidTarget,
                    message: "a window-target packet arrived without a window frame to resolve against")
            }
            guard canvas.frame.width > 0, canvas.frame.height > 0 else {
                throw AgentSpaceError(
                    code: .invalidCoordinate,
                    message: "the remote window has no area to resolve a fraction against")
            }
            return InputTargetResolution.point(xFraction: x, yFraction: y, in: canvas.frame)
        }
    }
}

/// The frame a window-target packet resolves against.
public struct InputCanvas: Equatable, Sendable {
    public var frame: CGRectValue
    public init(frame: CGRectValue) { self.frame = frame }
}

/// The fraction → point mapping a window target needs, kept in Core so the
/// worker and the tests cannot disagree about it.
public enum InputTargetResolution {
    /// Clamped rather than refused: a drag that leaves the window still has to
    /// land somewhere, and the window server's own behaviour is to keep sending
    /// positions past the edge. Refusing would end the gesture mid-stroke.
    public static func point(xFraction: Double, yFraction: Double, in frame: CGRectValue) -> (x: Double, y: Double) {
        let u = min(1, max(0, xFraction.isFinite ? xFraction : 0))
        let v = min(1, max(0, yFraction.isFinite ? yFraction : 0))
        return (frame.x + frame.width * u, frame.y + frame.height * v)
    }
}

/// A drag's coordinate basis, held for the life of the gesture.
///
/// A pointerDown names a window and a frame; every later phase of the same
/// gesture must resolve against *that* frame, because the gesture itself is
/// usually what moves the window. Re-deriving it per packet would make a
/// title-bar drag chase its own tail — the window moves, the fraction is
/// multiplied by the new frame, and the pointer accelerates away from the hand.
///
/// A class rather than a struct so the worker can hold one across connections
/// without a value-type copy handing each of them its own empty map.
public final class GestureFrameStore<Key: Hashable & Sendable>: @unchecked Sendable {
    private var frames: [Key: CGRectValue] = [:]
    private let lock = NSLock()

    public init() {}

    public func begin(_ key: Key, frame: CGRectValue) {
        lock.lock(); defer { lock.unlock() }
        frames[key] = frame
    }

    public func frame(for key: Key) -> CGRectValue? {
        lock.lock(); defer { lock.unlock() }
        return frames[key]
    }

    public func end(_ key: Key) {
        lock.lock(); defer { lock.unlock() }
        frames[key] = nil
    }

    /// Every key currently holding a frame. Used when a connection ends and the
    /// basis it established must not survive it.
    public func allKeys() -> [Key] {
        lock.lock(); defer { lock.unlock() }
        return Array(frames.keys)
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return frames.count }
}
