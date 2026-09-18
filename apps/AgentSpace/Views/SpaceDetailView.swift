import SwiftUI
import AgentSpaceCore

/// The Space list — plan §27.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Spaces") {
                ForEach(model.snapshots) { snapshot in
                    SidebarRow(snapshot: snapshot)
                        .tag(snapshot.id)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    Button {
                        model.showingNewSpace = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Create an Agent Space")

                    Spacer()

                    Button {
                        model.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                    .disabled(model.isLoading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct SidebarRow: View {
    var snapshot: SpaceSnapshot

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: snapshot.effectiveState)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.space.name)
                    .lineLimit(1)
                Text(snapshot.effectiveState.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.space.name), \(snapshot.effectiveState.displayName)")
    }
}

/// One Space in full: plan §27's card, §30's real resource numbers, §38's
/// readiness, and — most importantly — the reason input is or is not available.
struct SpaceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apps: [AppEntry] = []
    @State private var appsError: AppModel.PresentedError?
    @State private var showingApps = false
    @State private var showingViewer = false

    var body: some View {
        Group {
            if let snapshot = model.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(snapshot)
                        if let problem = snapshot.problem {
                            RefusalBanner(
                                title: refusalTitle(for: problem),
                                code: problem.code.rawValue,
                                message: problem.message,
                                fix: problem.code.remediation)
                        }
                        overviewCard(snapshot)
                        if let display = snapshot.display {
                            displayCard(display)
                        }
                        if let resources = snapshot.resources {
                            resourcesCard(resources)
                        }
                        if showingApps {
                            appsCard
                        }
                        setupCard(snapshot)
                        dangerCard(snapshot)
                    }
                    .padding(18)
                }
            } else {
                EmptyStateView { model.showingNewSpace = true }
            }
        }
        .navigationTitle(model.selected?.space.name ?? "AgentSpace")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingApps.toggle()
                    if showingApps { loadApps() }
                } label: {
                    Label("Apps", systemImage: "square.grid.2x2")
                }
                .disabled(model.selected == nil)

                Button {
                    showingViewer = true
                } label: {
                    Label("View Desktop", systemImage: "display")
                }
                .disabled(model.selected?.display == nil)
            }
        }
        .sheet(isPresented: $showingViewer) {
            DesktopViewerView().environmentObject(model)
        }
    }

    // MARK: - Header

    private func header(_ snapshot: SpaceSnapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            StatusDot(state: snapshot.effectiveState)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.space.name).font(.title2.weight(.semibold))
                Text(snapshot.effectiveState.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refreshSelectedResources()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(snapshot.problem?.code == .workerOffline)
        }
    }

    private func refusalTitle(for error: AgentSpaceError) -> String {
        switch error.code {
        case .sessionIsConsole: return "This Space is on your physical display"
        case .workerOffline: return "No worker is running"
        case .accessibilityDenied: return "Accessibility permission is missing"
        case .screenRecordingDenied: return "Screen Recording permission is missing"
        case .noWindowServer: return "This Space has no desktop session"
        default: return "Unavailable"
        }
    }

    // MARK: - Cards

    private func overviewCard(_ snapshot: SpaceSnapshot) -> some View {
        Card(title: "Overview") {
            Field(label: "User", value: "\(snapshot.space.username) (uid \(snapshot.space.uid))", monospaced: true)
            Field(label: "Worker",
                  value: snapshot.workerOnline
                    ? "running (pid \(snapshot.workerPID.map(String.init) ?? "?"))"
                    : "not running",
                  tint: snapshot.workerOnline ? nil : .red)
            Field(label: "Session", value: snapshot.sessionVerdict ?? "unknown", monospaced: true)
            Field(label: "Accepts input",
                  value: snapshot.acceptsInput ? "yes" : "no",
                  tint: snapshot.acceptsInput ? .green : .orange)
            Field(label: "Workspace", value: snapshot.space.workspace.displayName)
            if snapshot.space.sharedFolders.isEmpty {
                Field(label: "Shared folders", value: "none")
            } else {
                ForEach(snapshot.space.sharedFolders) { folder in
                    Field(label: "Shared", value: "\(folder.path) — \(folder.access.displayName)", monospaced: true)
                }
            }
            HStack(spacing: 8) {
                Spacer().frame(width: 108)
                PermissionChip(name: "Accessibility", granted: snapshot.accessibility)
                PermissionChip(name: "Screen Recording", granted: snapshot.screenRecording)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private func displayCard(_ display: DisplayGeometry) -> some View {
        Card(title: "Display") {
            Field(label: "Points", value: "\(display.width) × \(display.height)", monospaced: true)
            Field(label: "Pixels", value: "\(display.pixelWidth) × \(display.pixelHeight)", monospaced: true)
            Field(label: "Scale", value: "\(display.scale)×", monospaced: true)
            Text("Input coordinates are points. A pixel read off a screenshot must be divided by \(display.scale) first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resourcesCard(_ resources: ResourceUsage) -> some View {
        Card(title: "Resources") {
            Field(label: "CPU", value: String(format: "%.1f%%", resources.cpuPercent), monospaced: true)
            Field(label: "Memory", value: resources.memoryDisplay, monospaced: true)
            Field(label: "Processes", value: "\(resources.processCount)", monospaced: true)
            if resources.diskBytes > 0 {
                Field(label: "Home", value: resources.diskDisplay, monospaced: true)
            }
            Text("Measured from this Space's own processes, aggregated by uid. A Space is not a VM, so there is no allocation to show.")
            Text("CPU is the sum across those processes, so it can exceed 100% on a multi-core Mac. If the worker is running as your own account rather than a dedicated Space user, these numbers describe your whole login session — which is what the uid aggregation is honestly reporting, not a leak from somewhere else.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appsCard: some View {
        Card(title: "Applications") {
            if let appsError {
                RefusalBanner(title: "Could not list applications",
                              code: appsError.code,
                              message: appsError.message,
                              fix: appsError.fix)
            } else if apps.isEmpty {
                Text("Nothing is running in this Space.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(apps) { app in
                    HStack(spacing: 8) {
                        Text(app.active ? "●" : "○")
                            .foregroundStyle(app.active ? Color.accentColor : Color.secondary)
                        Text(app.name).font(.callout)
                        if app.isAccessory {
                            Text("accessory")
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                        Spacer()
                        Text("\(app.pid)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Text("Menu-bar and accessory apps are listed too — omitting them makes every launch of one look like a failure.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The first-login checklist from plan §28. Shown while the Space cannot yet
    /// accept input, because it is precisely then that the user needs to know what
    /// to do in the other session.
    @ViewBuilder
    private func setupCard(_ snapshot: SpaceSnapshot) -> some View {
        if !snapshot.acceptsInput && snapshot.effectiveState != .console {
            Card(title: "Setup") {
                Text("An Agent Space needs one manual sign-in before it can run in the background.")
                    .font(.callout)
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Open Fast User Switching from the menu bar", done: true)
                    step(2, "Sign in as “AgentSpace – \(snapshot.space.name)”", done: snapshot.workerOnline)
                    step(3, "Grant Accessibility to agentspace-worker in System Settings", done: snapshot.accessibility)
                    step(4, "Grant Screen & System Audio Recording", done: snapshot.screenRecording)
                    step(5, "Switch back to your own account", done: false)
                }
                .padding(.top, 2)
                HStack {
                    Button("Show Login Password") {
                        model.present(AgentSpaceError(
                            code: .internalError,
                            message: "the login password is stored in the Keychain when the Space is created; the Spaces list is managed by the privileged helper, which is phase 3"),
                            space: snapshot.space)
                    }
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Button("Refresh") { model.reload() }
                }
                .controlSize(.small)
                Text("AgentSpace never writes the TCC database. These grants are given by you, in that session, on purpose.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func step(_ number: Int, _ text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(text).font(.callout)
        }
    }

    private func dangerCard(_ snapshot: SpaceSnapshot) -> some View {
        Card(title: "Maintenance") {
            HStack(spacing: 8) {
                Button("Reveal Runtime Folder") { model.revealRuntimeDirectory() }
                Button("Copy MCP Configuration") { model.copyMCPConfiguration() }
                Button("Run Doctor") { model.showingDoctor = true }
            }
            .controlSize(.small)

            Text("Deleting a Space removes a macOS user, so it goes through the privileged helper and a confirmation in this window — never from the CLI. That arrives in phase 3.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func loadApps() {
        guard let snapshot = model.selected else { return }
        let space = snapshot.space
        Task { @MainActor in
            let outcome = await Task.detached(priority: .userInitiated) {
                SpaceService().apps(for: space)
            }.value
            switch outcome {
            case .success(let entries):
                apps = entries
                appsError = nil
            case .failure(let error):
                apps = []
                appsError = AppModel.PresentedError(
                    code: error.code.rawValue,
                    message: error.message,
                    fix: error.code.remediation,
                    spaceName: space.name)
            }
        }
    }
}
