import Foundation

/// A quiet input channel waits indefinitely for its next reply. Keep that wait
/// off the ordered write queue so a click can be sent while no reply is due.
public final class InputChannelWorkQueues {
    private let writer: DispatchQueue
    private let reader: DispatchQueue

    public init(label: String) {
        writer = DispatchQueue(label: label + ".write", qos: .userInteractive)
        reader = DispatchQueue(label: label + ".read", qos: .userInteractive)
    }

    public func write(_ work: @escaping () -> Void) { writer.async(execute: work) }
    public func read(_ work: @escaping () -> Void) { reader.async(execute: work) }
}
