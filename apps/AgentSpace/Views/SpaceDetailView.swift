import SwiftUI
import AgentSpaceCore

/// The agent list — plan §27.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            List(selection: $model.selection) {
                Section(NSLocalizedString("My Agent Accounts", comment: "")) {
                    ForEach(model.snapshots) { snapshot in
                        SidebarRow(snapshot: snapshot)
                            .tag(snapshot.id)
                    }
                }
            }
            .listStyle(.sidebar)

            // Keep this as a bottom-aligned sibling rather than a
            // List.safeAreaInset. An empty List in an attached account can
            // report an unbounded content height; SwiftUI then places an
            // inset below the window, hiding the build stamp and refresh
            // control even though they remain in AX.
            if !model.snapshots.isEmpty {
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

                        // The build stamp, always on screen when the sidebar
                        // has rows. Empty attached accounts render their stamp
                        // in EmptyStateView instead of relying on List sizing.
                        Text("Build \(AppModel.displayVersion)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("appBuildVersion")

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
    @State private var showingPermissionGuide = false

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
                        permissionsCard(snapshot)
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
                Menu {
                    if let space = model.selected?.space {
                        Button {
                            model.authorizeAgent(space, pane: .accessibility)
                        } label: {
                            Label(NSLocalizedString("Accessibility", comment: ""), systemImage: "person.crop.circle.badge.checkmark")
                        }
                        Button {
                            model.authorizeAgent(space, pane: .screenRecording)
                        } label: {
                            Label(NSLocalizedString("Screen Recording", comment: ""), systemImage: "record.circle")
                        }
                        Divider()
                        Button {
                            showingPermissionGuide = true
                        } label: {
                            Label(NSLocalizedString("Open authorization guide", comment: ""), systemImage: "checklist")
                        }
                    }
                } label: {
                    Label(NSLocalizedString("Authorize", comment: ""), systemImage: "lock.shield")
                }
                .accessibilityIdentifier("openAgentPermissionToolbar")
                .disabled(model.selected == nil
                    || model.authorizingPermission != nil
                    || model.openingSystemSettings != nil
                    || model.updatingWorker != nil
                    || model.finishingSetup != nil)

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

                // Stop keeps the session; Disconnect removes only
                // AgentSpace-owned setup.
                Menu {
                    Button("Stop Agent") {
                        if let space = model.selected?.space { model.stopWorker(space) }
                    }
                    .disabled(model.selected?.workerOnline != true)
                    Divider()
                    Button(NSLocalizedString("Disconnect Account…", comment: ""), role: .destructive) {
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
        .sheet(isPresented: $showingPermissionGuide) {
            if let snapshot = model.snapshots.first(where: { $0.id == model.selection }) {
                PermissionGuideView(spaceID: snapshot.space.id)
                    .environmentObject(model)
            }
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
                if let fileAccess = snapshot.fileAccess {
                    PermissionChip(name: NSLocalizedString("Full Disk Access", comment: ""), granted: fileAccess)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    /// Permissions are a first-class main-page action, not a step hidden inside
    /// the first-login checklist. The attached account has no AgentSpace GUI;
    /// this card is the one place users need to come back to for authorization.
    private func permissionsCard(_ snapshot: SpaceSnapshot) -> some View {
        Card(title: NSLocalizedString("Permissions & authorization", comment: "")) {
            Text(String(format: NSLocalizedString("Authorize %@ here. These buttons open System Settings in that account's own session; you do not need to find AgentSpace after switching users.", comment: ""), snapshot.space.username))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(NSLocalizedString("The permission entry is agentspace-worker. It is a background process, not a separate app to launch or install.", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                PermissionChip(name: NSLocalizedString("Accessibility", comment: ""), granted: snapshot.accessibility)
                PermissionChip(name: NSLocalizedString("Screen Recording", comment: ""), granted: snapshot.screenRecording)
                if let fileAccess = snapshot.fileAccess {
                    PermissionChip(name: NSLocalizedString("Full Disk Access", comment: ""), granted: fileAccess)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                permissionButton(
                    snapshot,
                    pane: .accessibility,
                    title: NSLocalizedString("Open Accessibility settings", comment: ""),
                    icon: "person.crop.circle.badge.checkmark",
                    identifier: "openAgentAccessibilitySettings")
                permissionButton(
                    snapshot,
                    pane: .screenRecording,
                    title: NSLocalizedString("Open Screen Recording settings", comment: ""),
                    icon: "record.circle",
                    identifier: "openAgentScreenRecordingSettings")
            }

            permissionButton(
                snapshot,
                pane: .fullDiskAccess,
                title: NSLocalizedString("Open Full Disk Access settings", comment: ""),
                icon: "lock.open.trianglebadge.exclamationmark",
                identifier: "openAgentFullDiskAccessSettings")

            Text(NSLocalizedString("The first two are required. Full Disk Access is optional and covers this account's Desktop, Documents, Downloads and other apps' data; without it the agent simply keeps out of those folders.", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    showingPermissionGuide = true
                } label: {
                    Label(NSLocalizedString("Open authorization guide", comment: ""), systemImage: "checklist")
                }
                .accessibilityIdentifier("openAgentPermissionGuide")
                .disabled(model.authorizingPermission != nil || model.openingSystemSettings != nil || model.updatingWorker != nil || model.finishingSetup != nil)

                Button {
                    model.reload()
                } label: {
                    Label(NSLocalizedString("Refresh authorization status", comment: ""), systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("refreshPermissionStatus")
                .disabled(model.isLoading || model.authorizingPermission != nil)
            }

            if !snapshot.workerOnline {
                Label(NSLocalizedString("The worker is not running yet. Clicking any permission button will install/start it first, then open the matching System Settings pane.", comment: ""), systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionButton(
        _ snapshot: SpaceSnapshot,
        pane: SystemSettingsPane,
        title: String,
        icon: String,
        identifier: String
    ) -> some View {
        Button {
            model.authorizeAgent(snapshot.space, pane: pane)
        } label: {
            if model.authorizingPermission == snapshot.space.id {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(NSLocalizedString("Preparing authorization…", comment: ""))
                }
            } else {
                Label(title, systemImage: icon)
            }
        }
        .accessibilityIdentifier(identifier)
        .disabled(model.authorizingPermission != nil || model.openingSystemSettings != nil || model.updatingWorker != nil || model.finishingSetup != nil)
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

            // Without Full Disk Access the walk stops at the folder gates instead
            // of spending one of the user's privacy decisions on a metric, so the
            // number is a lower bound and has to say so.
            if resources.diskMeasured && resources.diskExcludesProtected {
                Text(NSLocalizedString("macOS-protected folders were left out of this figure, not counted as zero. Grant Full Disk Access to include them.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text(NSLocalizedString("The connected account does not contain a second AgentSpace app. The background agentspace-worker runs there and uses that account's System Settings permissions.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("When you switch to the connected account, its AgentSpace panel is intentionally empty. Use the System Settings opened by these buttons, then switch back to your own account.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    step(1, NSLocalizedString("Open Fast User Switching from the menu bar", comment: ""), done: true)
                    step(2, String(format: NSLocalizedString("Sign in as “%@”", comment: ""), snapshot.space.username), done: snapshot.workerOnline)
                    step(3, NSLocalizedString("Grant Accessibility to agentspace-worker in System Settings", comment: ""), done: snapshot.accessibility)
                    step(4, NSLocalizedString("Grant Screen & System Audio Recording", comment: ""), done: snapshot.screenRecording)
                    step(5, NSLocalizedString("Switch back to your own account", comment: ""), done: false)
                }
                .padding(.top, 2)
                Text(NSLocalizedString("After the first login, switch back to your account and click Finish setup. The worker must start before macOS can show its privacy-permission prompts.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("Use the Permissions & authorization card above. Its buttons install/start the worker when needed, then open the privacy pane inside the connected account's session.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        model.finishPendingSetup(snapshot.space)
                    } label: {
                        if model.finishingSetup == snapshot.space.id {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(NSLocalizedString("Finishing setup…", comment: ""))
                            }
                        } else {
                            Text(NSLocalizedString("Finish setup", comment: ""))
                        }
                    }
                    .disabled(model.finishingSetup != nil || model.updatingWorker != nil)
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
                Button(NSLocalizedString("Disconnect Account…", comment: ""), role: .destructive) { showingDelete = true }
                    .disabled(model.provisioning != nil)
            }
            .controlSize(.small)

            Text(NSLocalizedString("Disconnecting removes the AgentSpace worker and runtime. The existing macOS account and its home are always kept.", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .confirmationDialog(
            String(format: NSLocalizedString("Disconnect %@?", comment: ""), space.name),
            isPresented: $showingDelete,
            titleVisibility: .visible
        ) {
            // Detach only removes AgentSpace-owned runtime state.
            Button(NSLocalizedString("Disconnect Account", comment: ""), role: .destructive) {
                model.deleteSpace(space)
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(String(format: NSLocalizedString("The existing macOS user %@ and its home directory will not be deleted.", comment: ""), space.macOSUsername))
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
    }

    @State private var showingDelete = false
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
