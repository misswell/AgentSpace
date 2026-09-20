import AppKit
import Foundation
import AgentSpaceCore

@MainActor
final class FusionWindowState: ObservableObject {
    @Published var image: NSImage?
    @Published var error: AgentSpaceError?
    @Published var humanHasControl = true
}
