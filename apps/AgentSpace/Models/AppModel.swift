import Foundation
import SwiftUI
import AgentSpaceCore

/// The GUI's state.
///
/// Two deliberate choices are visible here.
///
/// **Refresh is slow and on demand.** Plan §53 sets a 2–5 s floor on status
/// polling and forbids the 100 ms loop that makes a management app cost more than
/// the thing it manages. Nothing here polls while the window is closed, and the
/// only fast timer in the app is the desktop preview, which runs at 1 FPS and only
/// while it is on screen.
///
/// **Input is gated on `acceptsInput`.** The buttons that drive the agent's
/// desktop are disabled unless the worker itself said input is permitted. The GUI
/// does not decide whether a Space is usable; it asks, and it believes the answer.
@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var snapshots: [SpaceSnapshot] = []
    @Published var selection: UUID?
    /// Settable because SwiftUI's `alert(item:)` needs a two-way binding.
    @Published var lastError: PresentedError?
    @Published private(set) var isLoading = false
    @Published var showingNewSpace = false
    @Published var showingDoctor = false
    @Published private(set) var doctorReport: Doctor.Report?

    /// A failure phrased for a human, with the code kept for the detail line.
    struct PresentedError: Identifiable, Equatable {
        var id = UUID()
        var code: String
        var message: String
        var fix: String?
        var spaceName: String?
    }

    private let service: SpaceService
    private var refreshTask: Task<Void, Never>?

    init(service: SpaceService = SpaceService()) {
        self.service = service
    }

    // MARK: - Loading

    func reload() {
        isLoading = true
        let registry = service.loadRegistry()
        let spaces = registry.spaces

        if selection == nil || !spaces.contains(where: { $0.id == selection }) {
            selection = spaces.first?.id
        }

        // Resources are fetched only for the Space on screen: one `ps` fork per
        // Space per refresh would be exactly the overhead §53 forbids.
        snapshots = spaces.map { space in
            service.snapshot(for: space, includeResources: space.id == selection)
        }
        isLoading = false

        if let selected = snapshots.first(where: { $0.id == selection }), let problem = selected.problem {
            // A refusal is normal and is shown in the detail pane, not as an
            // alert. Only something the user did is worth interrupting for.
            _ = problem
        }
    }

    /// Refresh the resource numbers for whichever Space is selected.
    func refreshSelectedResources() {
        guard let index = snapshots.firstIndex(where: { $0.id == selection }) else { return }
        let space = snapshots[index].space
        snapshots[index] = service.snapshot(for: space, includeResources: true)
    }

    var selected: SpaceSnapshot? {
        snapshots.first { $0.id == selection }
    }

    // MARK: - Doctor

    func runDoctor() {
        doctorReport = Doctor.run()
    }

    // MARK: - Space actions

    func present(_ error: AgentSpaceError, space: AgentSpace?) {
        lastError = PresentedError(
            code: error.code.rawValue,
            message: error.message,
            fix: error.code.remediation,
            spaceName: space?.name)
    }

    func dismissError() { lastError = nil }

    /// Write the Space's screenshot to a file the user asked for.
    ///
    /// Note this asks the *worker* for the capture; it never grabs this session's
    /// screen. If the Space is unavailable the user gets the refusal, not a
    /// picture of their own desktop labelled as the agent's.
    func captureScreenshot(maxWidth: Int = 1600) -> ScreenshotResult? {
        guard let snapshot = selected else { return nil }
        switch service.screenshot(for: snapshot.space, maxWidth: maxWidth, inline: false) {
        case .failure(let error):
            present(error, space: snapshot.space)
            return nil
        case .success(let result):
            return result
        }
    }

    /// Reveal the Space's runtime directory, the honest place to look when the
    /// worker is not answering.
    func revealRuntimeDirectory() {
        guard let snapshot = selected else { return }
        let path = service.paths(for: snapshot.space).directory
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } else {
            present(AgentSpaceError(
                code: .workerOffline,
                message: "there is no runtime directory for '\(snapshot.space.name)' yet, so the worker has never started"),
                space: snapshot.space)
        }
    }

    /// Copy the install instructions for the MCP server (plan §34).
    func copyMCPConfiguration() {
        let binary = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/agentspace").path
        let snippet = """
        {
          "mcpServers": {
            "agentspace": {
              "command": "npx",
              "args": ["-y", "@agentspace/mcp"],
              "env": { "AGENTSPACE_BIN": "\(binary)" }
            }
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
    }
}
