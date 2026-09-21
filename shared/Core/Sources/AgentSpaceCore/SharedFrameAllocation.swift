import Foundation

/// Which call refused the shared memory a frame stream is drawn into.
public enum SharedFrameAllocationOperation: String, Codable, Sendable, CaseIterable {
    case create = "shm_open"
    case resize = "ftruncate"
    case map = "mmap"
}

/// A shared frame buffer the kernel refused, as its readers know it: which call,
/// which errno, and what was asked for.
///
/// This is the typed half of the failure. The worker keeps the most recent one
/// and answers `frame.stats` with it, so a viewer asking "why is there no
/// picture" gets a value rather than a sentence to interpret — and the sentence
/// below stays what it is for: a log line and a Diagnostics attachment.
public struct SharedFrameAllocationFailure: Codable, Equatable, Sendable {
    public let operation: SharedFrameAllocationOperation
    public let systemErrorCode: Int32
    /// Bytes the refusing call asked for — the region size for resize and map.
    public let requestedBytes: Int
    /// Length of the name handed to `shm_open`. A name over
    /// `SharedMemoryName.darwinMaximumBytes` is a bug readable straight off this
    /// number; the token itself never travels, because it is random and a record
    /// carrying it would name nothing.
    public let attemptedNameBytes: Int?

    public init(operation: SharedFrameAllocationOperation, systemErrorCode: Int32,
                requestedBytes: Int = 0, attemptedNameBytes: Int? = nil) {
        self.operation = operation
        self.systemErrorCode = systemErrorCode
        self.requestedBytes = requestedBytes
        self.attemptedNameBytes = attemptedNameBytes
    }

    /// The errno as the man pages spell it.
    public var systemErrorName: String { SharedFrameAllocation.systemErrorName(systemErrorCode) }

    public var message: String {
        SharedFrameAllocation.message(operation: operation, systemErrorCode: systemErrorCode,
                                      requestedBytes: requestedBytes, attemptedNameBytes: attemptedNameBytes)
    }
}

/// The one message shape both ends of the frame stream agree on for a shared
/// buffer the kernel refused.
///
/// Three audiences read this failure and none of them wants the same sentence:
/// the log wants the call, the errno and the size; Diagnostics wants the text;
/// the GUI wants to know that *this* is the failure it can describe usefully to
/// someone holding a mouse. The worker therefore keeps the typed
/// `SharedFrameAllocationFailure` and only *words* it into the message below —
/// a viewer reads the value, and what crosses the socket as an error stays an
/// ordinary code plus a message, which older peers can still decode.
///
/// The errno is always carried as a value captured at the syscall. Reading
/// `errno` after a message has been assembled reports whatever that assembly
/// left behind, which is how a name-length bug gets logged as a permissions one.
public enum SharedFrameAllocation {
    /// Every message of this shape starts with it.
    public static let messagePrefix = "shared frame allocation failed"

    /// `errno` spelled the way the man pages spell it, for the values these
    /// three calls can return. A bare number sends the reader to a table;
    /// `ENAMETOOLONG` in a message is the difference between knowing the shared
    /// memory name was too long and looking up why it was refused.
    public static func systemErrorName(_ code: Int32) -> String {
        switch code {
        case EPERM: return "EPERM"
        case ENOENT: return "ENOENT"
        case EINTR: return "EINTR"
        case EINVAL: return "EINVAL"
        case E2BIG: return "E2BIG"
        case ENOMEM: return "ENOMEM"
        case EACCES: return "EACCES"
        case EEXIST: return "EEXIST"
        case ENFILE: return "ENFILE"
        case EMFILE: return "EMFILE"
        case EFBIG: return "EFBIG"
        case ENAMETOOLONG: return "ENAMETOOLONG"
        default: return "errno \(code)"
        }
    }

    /// The sentence a refusal produces:
    /// `shared frame allocation failed: shm_open ENAMETOOLONG (File name too
    /// long), attempted 48-byte name against a 31-byte limit`.
    public static func message(operation: SharedFrameAllocationOperation, systemErrorCode: Int32,
                               requestedBytes: Int = 0, attemptedNameBytes: Int? = nil) -> String {
        var text = "\(messagePrefix): \(operation.rawValue) \(systemErrorName(systemErrorCode)) (\(String(cString: strerror(systemErrorCode))))"
        if let attemptedNameBytes {
            text += ", attempted \(attemptedNameBytes)-byte name against a \(SharedMemoryName.darwinMaximumBytes)-byte limit"
        } else if requestedBytes > 0 {
            text += ", requested \(requestedBytes) bytes"
        }
        return text
    }

    /// Which call a written-out refusal blames, reading back what `message`
    /// produced.
    ///
    /// For logs, tests and the last-resort path where a viewer has only the text
    /// a peer sent it — the answers a UI acts on come from the typed
    /// `SharedFrameAllocationFailure` the worker keeps, not from here.
    public static func classify(message: String) -> SharedFrameAllocationOperation? {
        let prefix = messagePrefix + ": "
        guard message.hasPrefix(prefix) else { return nil }
        let remainder = message.dropFirst(prefix.count)
        return SharedFrameAllocationOperation(rawValue: String(remainder.prefix(while: { !$0.isWhitespace })))
    }
}
