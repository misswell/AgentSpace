import Foundation

/// Scheduling for a frame stream: the reader occupies its queue until disconnect.
public final class FrameStreamScheduling {
    public let reader: DispatchQueue
    public let control: DispatchQueue

    public init(label: String) {
        reader = DispatchQueue(label: label + ".reader", qos: .userInitiated)
        control = DispatchQueue(label: label + ".control", qos: .userInitiated)
    }
}
