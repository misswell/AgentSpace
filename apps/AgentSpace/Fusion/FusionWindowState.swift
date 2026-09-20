import AppKit
import Foundation
import AgentSpaceCore

@MainActor
final class FusionWindowState: ObservableObject {
    @Published var image: NSImage?
    @Published var error: AgentSpaceError?
}

/// One answer from a proxy's frame pull.
///
/// `image` is nil when the worker said "nothing newer than the frame you
/// named". That is not a failure and not an empty window: the proxy keeps
/// drawing the image it already has, which is the same pixels.
struct FusionFrame {
    var image: NSImage?
    var sequence: Int
}
