import SwiftUI
import AgentSpaceCore

/// The agent list — plan §27.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section(NSLocalizedString("My Agent Accounts", comment: "")) {
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
                    .help(Text("New agent"))

                    Spacer()

                    Button {
                        model.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Refresh"))
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

/// One Agent in full: plan §27's card, §30's real resource numbers, §38's
/// readiness, and — most importantly — the reason input is or is not available.
struct SpaceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apps: [AppEntry] = []
    @State private var appsError: AppModel.PresentedError?
    @State private var showingApps = false

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
                            resourcesCard(resources) { model.measureDisk(for: snapshot.space) }
                        }
                        if showingApps {
                            appsCard
                        }
                        setupCard(snapshot)
                        dangerCard(snapshot)
                    }
                    .padding(18)
                }
            } else if model.snapshots.isEmpty {
                EmptyStateView { model.showingNewSpace = true }
            } else {
                AgentCardGrid(
                    snapshots: model.snapshots,
                    onSelect: { model.selection = $0 },
                    onOpenDesktop: { snapshot in
                        model.selection = snapshot.space.id
                        model.showingDesktopViewer = true
                    })
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
                    model.showingDesktopViewer = true
                } label: {
                    Label(NSLocalizedString("Open Desktop", comment: ""), systemImage: "display")
                }
                .disabled(model.selected?.display == nil)

                // §40: three different endings for a Space, deliberately not
                // collapsed into one "stop". Stop keeps the session; Logout
                // ends the session but keeps the account; Delete removes
                // everything and asks about the home.
                Menu {
                    Button("Stop Agent") {
                        if let space = model.selected?.space { model.stopWorker(space) }
                    }
                    .disabled(model.selected?.workerOnline != true)
                    Button("Logout Desktop…") {
                        showingLogout = true
                    }
                    Divider()
                    Button(NSLocalizedString("Delete Agent…", comment: ""), role: .destructive) {
                        showingDelete = true
                    }
                    .disabled(model.selected == nil)
                } label: {
                    Label(NSLocalizedString("Agent", comment: ""), systemImage: "gearshape")
                }
                .disabled(model.selected == nil)
            }
        }
        .sheet(isPresented: $model.showingDesktopViewer) {
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
        case .sessionIsConsole: return NSLocalizedString("This agent is on your physical display", comment: "")
        case .workerOffline: return NSLocalizedString("No worker is running", comment: "")
        case .accessibilityDenied: return NSLocalizedString("Accessibility permission is missing", comment: "")
        case .screenRecordingDenied: return NSLocalizedString("Screen Recording permission is missing", comment: "")
        case .noWindowServer: return NSLocalizedString("This agent has no desktop session", comment: "")
        default: return NSLocalizedString("Unavailable", comment: "")
        }
    }

    // MARK: - Cards

    private func overviewCard(_ snapshot: SpaceSnapshot) -> some View {
        Card(title: NSLocalizedString("Overview", comment: "")) {
            Field(label: NSLocalizedString("macOS User", comment: ""), value: "\(snapshot.space.username) (uid \(snapshot.space.uid))", monospaced: true)
            Field(label: NSLocalizedString("Worker", comment: ""),
                  value: snapshot.workerOnline
                    ? String(format: NSLocalizedString("running (pid %@)", comment: ""), snapshot.workerPID.map(String.init) ?? "?")
                    : NSLocalizedString("not running", comment: ""),
                  tint: snapshot.workerOnline ? nil : .red)
            Field(label: NSLocalizedString("Session", comment: ""), value: snapshot.sessionVerdict ?? NSLocalizedString("unknown", comment: ""), monospaced: true)
            Field(label: NSLocalizedString("Accepts input", comment: ""),
                  value: snapshot.acceptsInput ? NSLocalizedString("yes", comment: "") : NSLocalizedString("no", comment: ""),
                  tint: snapshot.acceptsInput ? .green : .orange)
            Field(label: NSLocalizedString("Workspace", comment: ""), value: snapshot.space.workspace.displayName)
            if snapshot.space.sharedFolders.isEmpty {
                Field(label: NSLocalizedString("Shared folders", comment: ""), value: NSLocalizedString("none", comment: ""))
            } else {
                ForEach(snapshot.space.sharedFolders) { folder in
                    Field(label: NSLocalizedString("Shared", comment: ""), value: "\(folder.path) — \(folder.access.displayName)", monospaced: true)
                }
            }
            HStack(spacing: 8) {
                Spacer().frame(width: 108)
                PermissionChip(name: NSLocalizedString("Accessibility", comment: ""), granted: snapshot.accessibility)
                PermissionChip(name: NSLocalizedString("Screen Recording", comment: ""), granted: snapshot.screenRecording)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private func displayCard(_ display: DisplayGeometry) -> some View {
        Card(title: NSLocalizedString("Display", comment: "")) {
            Field(label: NSLocalizedString("Points", comment: ""), value: "\(display.width) × \(display.height)", monospaced: true)
            Field(label: NSLocalizedString("Pixels", comment: ""), value: "\(display.pixelWidth) × \(display.pixelHeight)", monospaced: true)
            Field(label: NSLocalizedString("Scale", comment: ""), value: "\(display.scale)×", monospaced: true)
            Text(String(format: NSLocalizedString("Input coordinates are points. A pixel read off a screenshot must be divided by %@ first.", comment: ""), "\(display.scale)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resourcesCard(_ resources: ResourceUsage, onMeasureDisk: @escaping () -> Void) -> some View {
        Card(title: NSLocalizedString("Resources", comment: "")) {
            Field(label: NSLocalizedString("CPU", comment: ""), value: String(format: "%.1f%%", resources.cpuPercent), monospaced: true)
            Field(label: NSLocalizedString("Memory", comment: ""), value: resources.memoryDisplay, monospaced: true)
            Field(label: NSLocalizedString("Processes", comment: ""), value: "\(resources.processCount)", monospaced: true)

            // Disk is a separate, explicitly-requested measurement, because it
            // walks the agent's whole home — tens of thousands of files for a
            // browser profile plus an IDE's caches. Measuring it on the 2–5 s
            // status poll would put the app permanently on the CPU, which §53
            // forbids. So it is a button, and it says what it costs.
            HStack(spacing: 8) {
                if resources.diskMeasured {
                    Field(label: NSLocalizedString("Home", comment: ""), value: resources.diskDisplay, monospaced: true)
                    if resources.diskTruncated {
                        Text(NSLocalizedString("(partial)", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help(Text("The walk hit its file budget. This is a lower bound, not an exact figure."))
                    }
                } else {
                    Button(NSLocalizedString("Measure Disk Usage", comment: "")) { onMeasureDisk() }
                        .controlSize(.small)
                        .help(Text("Walks every file in the agent's home. Takes a moment; not measured continuously."))
                }
            }

            Text(NSLocalizedString("Measured from this agent's own processes, aggregated by uid. An agent is not a VM, so there is no allocation to show.", comment: ""))
            Text("CPU is the sum across those processes, so it can exceed 100% on a multi-core Mac. If the worker is running as your own account rather than a dedicated agent account, these numbers describe your whole login session — which is what the uid aggregation is honestly reporting, not a leak from somewhere else.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appsCard: some View {
        Card(title: NSLocalizedString("Applications", comment: "")) {
            if let appsError {
                RefusalBanner(title: NSLocalizedString("Could not list applications", comment: ""),
                              code: appsError.code,
                              message: appsError.message,
                              fix: appsError.fix)
            } else if apps.isEmpty {
                Text(NSLocalizedString("Nothing is running in this agent.", comment: ""))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(apps) { app in
                    HStack(spacing: 8) {
                        Text(app.active ? "●" : "○")
                            .foregroundStyle(app.active ? Color.accentColor : Color.secondary)
                        Text(app.name).font(.callout)
                        if app.isAccessory {
                            Text(NSLocalizedString("accessory", comment: ""))
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }
                        Spacer()
                        Text("\(app.pid)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Text(NSLocalizedString("Menu-bar and accessory apps are listed too — omitting them makes every launch of one look like a failure.", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The first-login checklist from plan §28. Shown while the agent cannot yet
    /// accept input, because it is precisely then that the user needs to know what
    /// to do in the other session.
    @ViewBuilder
    private func setupCard(_ snapshot: SpaceSnapshot) -> some View {
        if !snapshot.acceptsInput && snapshot.effectiveState != .console {
            Card(title: NSLocalizedString("Setup", comment: "")) {
                Text(NSLocalizedString("An agent account needs one manual sign-in before it can run in the background.", comment: ""))
                    .font(.callout)
                VStack(alignment: .leading, spacing: 6) {
                    step(1, NSLocalizedString("Open Fast User Switching from the menu bar", comment: ""), done: true)
                    step(2, String(format: NSLocalizedString("Sign in as “AgentSpace – %@”", comment: ""), snapshot.space.name), done: snapshot.workerOnline)
                    step(3, NSLocalizedString("Grant Accessibility to agentspace-worker in System Settings", comment: ""), done: snapshot.accessibility)
                    step(4, NSLocalizedString("Grant Screen & System Audio Recording", comment: ""), done: snapshot.screenRecording)
                    step(5, NSLocalizedString("Switch back to your own account", comment: ""), done: false)
                }
                .padding(.top, 2)
                HStack {
                    Button(NSLocalizedString("Show Login Password", comment: "")) {
                        model.revealPassword(for: snapshot.space)
                    }
                    Button(NSLocalizedString("Open System Settings", comment: "")) {
                        NSWorkspace.shared.open(URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    Button(NSLocalizedString("Refresh", comment: "")) { model.reload() }
                }
                .controlSize(.small)
                Text(NSLocalizedString("AgentSpace never writes the TCC database. These grants are given by you, in that session, on purpose.", comment: ""))
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
        let space = snapshot.space
        return Card(title: NSLocalizedString("Maintenance", comment: "")) {
            HStack(spacing: 8) {
                Button(NSLocalizedString("Reveal Runtime Folder", comment: "")) { model.revealRuntimeDirectory() }
                Menu(NSLocalizedString("Install MCP Into…", comment: "")) {
                    ForEach([Integrations.Target.claudeCode, .codex, .openCode], id: \.self) { target in
                        Button(target.displayName) {
                            integrationTarget = target
                            showingIntegrationConfirm = true
                        }
                    }
                }
                Button(NSLocalizedString("Copy MCP Configuration", comment: "")) { model.copyMCPConfiguration() }
                Button(NSLocalizedString("Copy Agent Rules", comment: "")) {
                    model.copyAgentRules()
                }
                .help(Text("The §35 safety rules, for AGENTS.md or CLAUDE.md. Copying only — your instructions file is written by you."))
                Button(NSLocalizedString("Run Doctor", comment: "")) { model.showingDoctor = true }
            }
            .controlSize(.small)

            if let copied = model.copiedMessage {
                Text(copied)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .task {
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        model.copiedMessage = nil
                    }
            }


            HStack(spacing: 8) {
                Button(NSLocalizedString("Show Login Password", comment: "")) { model.revealPassword(for: space) }
                    .help(Text("Needed once, to sign in to this agent's macOS account for the first time."))
                Button(NSLocalizedString("Delete Agent…", comment: ""), role: .destructive) { showingDelete = true }
                    .disabled(model.provisioning != nil)
            }
            .controlSize(.small)

            Text(NSLocalizedString("Deleting removes this agent's macOS user, its runtime directory and its worker. A git worktree is removed but its branch is kept, and your own repository is never touched.", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .confirmationDialog(
            String(format: NSLocalizedString("Delete %@?", comment: ""), space.name),
            isPresented: $showingDelete,
            titleVisibility: .visible
        ) {
            // The home directory is a separate question because it is the one
            // irreversible step, and it holds the agent's own files — which the
            // user may want to look at after the agent is gone.
            Button(NSLocalizedString("Delete Agent, keep its home directory", comment: "")) {
                model.deleteSpace(space, removeHome: false)
            }
            Button(NSLocalizedString("Delete Agent and its home directory", comment: ""), role: .destructive) {
                model.deleteSpace(space, removeHome: true)
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(String(format: NSLocalizedString("The macOS user %@ will be removed, and it will no longer be able to run anything. The agent's files in its home directory are not affected unless you ask for them to be.", comment: ""), space.macOSUsername))
        }
        // A second dialog on the same view: SwiftUI allows several, each gated by
        // its own `isPresented`.
        .confirmationDialog(
            String(format: NSLocalizedString("Configure %@?", comment: ""), integrationTarget?.displayName ?? NSLocalizedString("this client", comment: "")),
            isPresented: $showingIntegrationConfirm,
            titleVisibility: .visible
        ) {
            Button(String(format: NSLocalizedString("Configure %@", comment: ""), integrationTarget?.displayName ?? "")) {
                if let target = integrationTarget { model.installIntegration(target) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            // §35: writing into a config file another tool owns is done only with
            // the user's explicit yes, and says exactly what will change.
            Text(String(format: NSLocalizedString("AgentSpace will add itself as an MCP server in %@. Nothing else in the file changes, and the previous contents are saved next to it.", comment: ""), integrationTarget?.configPath ?? ""))
        }
        // The "…" on Logout Desktop… promises this dialog. Logout is reversible
        // but not free: the agent worker dies with the session, and coming back
        // needs one manual fast-user-switch login — so the cost is said here,
        // where it can still be declined.
        .confirmationDialog(
            String(format: NSLocalizedString("Log out the desktop for %@?", comment: ""), model.selected?.space.name ?? NSLocalizedString("this agent", comment: "")),
            isPresented: $showingLogout,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Log Out Desktop", comment: "")) {
                if let space = model.selected?.space { model.logoutDesktop(space) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(NSLocalizedString("The agent worker stops with the session. To run agents again, sign in to this agent's desktop once more.", comment: ""))
        }
    }

    @State private var showingDelete = false
    @State private var showingLogout = false
    @State private var integrationTarget: Integrations.Target?
    @State private var showingIntegrationConfirm = false

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
