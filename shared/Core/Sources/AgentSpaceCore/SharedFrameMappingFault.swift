import Foundation

/// A shared frame buffer the viewer cannot lay out, and the numbers that say so.
///
/// The distinction this type exists to make is the one the reader has to act on:
/// a *sequence gap* means the mapping is fine and the viewer simply missed a
/// frame, which is answered by asking for a baseline; anything in here means the
/// mapping itself cannot be trusted, and continuing to read it — or asking for a
/// baseline and writing it into a buffer whose layout is in question — is how a
/// viewer ends up showing pixels from a different surface. So a fault is thrown
/// out of the read loop, which ends the connection and makes the next attempt
/// re-handshake, re-receive the descriptor and re-map.
///
/// The message is for the log. It carries sizes and never the shared memory name:
/// the name is a random token, so a record carrying it identifies nothing while a
/// record carrying its length names the bug.
public struct SharedFrameMappingFault: Error, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// The frame header's dimensions cannot describe a region at all.
        case invalidDimensions
        /// The notice names a slot this protocol does not have.
        case invalidSlot
        /// The notice's logical size disagrees with the size the frame's own
        /// dimensions imply: two ends laying the buffer out differently.
        case logicalSizeMismatch
        /// The descriptor holds fewer bytes than the logical layout needs, so
        /// reading it would run past the end of the mapping.
        case capacityTooSmall
        /// Slot metadata disagrees with the transport that pointed at it.
        case metadataMismatch
        /// More patches than the descriptor area can hold.
        case patchCountInvalid
        /// A descriptor or patch reaches outside the logical region.
        case descriptorOutOfBounds
    }

    public let kind: Kind
    public let width: Int
    public let height: Int
    public var logicalRegionSize: Int?
    public var noticeMappingSize: Int?
    public var mappedCapacity: Int?
    public var slot: Int?
    public var generation: UInt64?
    public var sequence: UInt64?

    public init(kind: Kind, width: Int, height: Int, logicalRegionSize: Int? = nil,
                noticeMappingSize: Int? = nil, mappedCapacity: Int? = nil, slot: Int? = nil,
                generation: UInt64? = nil, sequence: UInt64? = nil) {
        self.kind = kind; self.width = width; self.height = height
        self.logicalRegionSize = logicalRegionSize; self.noticeMappingSize = noticeMappingSize
        self.mappedCapacity = mappedCapacity; self.slot = slot
        self.generation = generation; self.sequence = sequence
    }

    /// One line, every measurement, no names. What a stream that will not come up
    /// needs from a log is the two sizes being compared, so the reader can tell a
    /// page-rounded mapping from a genuinely wrong notice.
    public var logLine: String {
        "frame mapping \(kind.rawValue): width=\(width) height=\(height)"
            + " logical=\(logicalRegionSize.map(String.init) ?? "-")"
            + " notice=\(noticeMappingSize.map(String.init) ?? "-")"
            + " capacity=\(mappedCapacity.map(String.init) ?? "-")"
            + " slot=\(slot.map(String.init) ?? "-")"
            + " generation=\(generation.map(String.init) ?? "-")"
            + " sequence=\(sequence.map(String.init) ?? "-")"
    }
}
