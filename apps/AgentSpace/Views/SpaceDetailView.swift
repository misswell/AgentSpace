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
                            .accessibilityIdentifier("appBuildVersionStamp")

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
            StatusDot(state: snapshot.displayState)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.space.name)
                    .lineLimit(1)
                Text(snapshot.statusDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.space.name), \(snapshot.statusDisplayName)")
    }
}

/// One Agent in full: plan §27's card, §30's real resource numbers, §38's
/// readiness, and — most importantly — the reason input is or is not available.
struct SpaceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apps: [AppEntry] = []
    @State private var appsError: AppModel.PresentedError?
    @State private var showingApps = false
    @State private var showingFusionPicker = false
    @State private var showingFusionWindows = false
    @State private var desktopSheet: DesktopSheet?

    /// The page's one Screen Sharing door has two intents: sign in (the window
    /// is temporary and closes when the desktop is up), and look at a working
    /// desktop to approve panes (the window stays until the person is done).
    private struct DesktopSheet: Identifiable {
        let account: AgentAccount
        let closesWindowWhenConnected: Bool
        var id: AgentAccount.ID { account.id }
    }

    var body: some View {
        Group {
            if let snapshot = model.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let problem = snapshot.problem {
                            RefusalBanner(
                                title: refusalTitle(for: problem),
                                code: problem.code.rawValue,
                                message: problem.message,
                                fix: problem.code.remediation)
                        }
                        if snapshot.workerOnline,
                           !snapshot.accessibility || !snapshot.screenRecording {
                            setupBanner(snapshot)
                        }
                        overviewCard(snapshot)
                        permissionsCard(snapshot)
                        ListeningPortsCard(account: snapshot.space)
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
                        DesktopViewerWindowManager.shared.open(for: snapshot.space, model: model)
                    })
            }
        }
        .navigationTitle(model.selected?.space.name ?? "AgentSpace")
        // One group of direct actions, no menus. The Authorize shield menu and
        // the Agent gear menu used to sit here, but every item they offered was
        // already on the page — the authorization card and the maintenance
        // card — so the toolbar repeated the window instead of adding to it.
        // Stop Agent, the one command that had no card home, moved into
        // Maintenance.
        .toolbar {
            ToolbarItemGroup {
                Button {
                    if let space = model.selected?.space {
                        DesktopViewerWindowManager.shared.open(for: space, model: model)
                    }
                } label: {
                    Label(NSLocalizedString("Open Desktop", comment: ""), systemImage: "display")
                }
                .disabled(model.selected?.display == nil)

                Button {
                    showingFusionWindows = true
                } label: {
                    Label(NSLocalizedString("Open Apps", comment: ""), systemImage: "macwindow.on.rectangle")
                }
                .disabled(model.selected?.acceptsInput != true
                    || model.selected?.screenRecording != true
                    || model.selected?.accessibility != true)

                // Launching an App in the agent session does not open a local
                // proxy. Open Apps lists windows for a separate manual choice.
                Button {
                    showingFusionPicker = true
                } label: {
                    Label(NSLocalizedString("Launch in Agent…", comment: ""), systemImage: "plus.rectangle.on.rectangle")
                }
                .accessibilityIdentifier("fusionAppPickerButton")
                .disabled(model.selected?.acceptsInput != true
                    || model.selected?.screenRecording != true
                    || model.selected?.accessibility != true)

                Button {
                    showingApps.toggle()
                    if showingApps { loadApps() }
                } label: {
                    Label("Apps", systemImage: "square.grid.2x2")
                }
                .disabled(model.selected == nil)

                // The one refresh on this page. The page header and the
                // authorization card each carried a button that ran this same
                // full reload; ⌘R still runs it from the menu bar too.
                Button {
                    model.reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)

                // The app's Settings scene (⌘,) — a window the page does not
                // contain, so unlike the menus §344 removed this entry adds
                // somewhere to go rather than repeating the page. 0.1.56 ran
                // AppKit's `showSettingsWindow:` selector here and the owner
                // measured the result: nothing — the Settings scene of newer
                // SDKs no longer connects that legacy action, and the fallback
                // spelling is equally dead. macOS 14 and later therefore get
                // `SettingsLink`, the first-class entry the scene itself
                // honours; only the macOS 13 build floor keeps the selector.
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Label("Settings…", systemImage: "gearshape")
                    }
                    .help(Text("Settings…"))
                    .accessibilityIdentifier("mainToolbarSettings")
                } else {
                    Button {
                        let opened = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        if !opened { _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) }
                    } label: {
                        Label("Settings…", systemImage: "gearshape")
                    }
                    .help(Text("Settings…"))
                    .accessibilityIdentifier("mainToolbarSettings")
                }
            }
        }
        // The guide request lives on the model, not in local state: the New
        // Agent wizard's completion step raises it after the wizard sheet is
        // down (§269 — one sheet at a time), from a view that cannot reach a
        // @State here.
        .sheet(isPresented: Binding(
            get: { model.permissionGuideRequest != nil },
            set: { if !$0 { model.permissionGuideRequest = nil }
            })) {
            if let requestID = model.permissionGuideRequest,
               let snapshot = model.snapshots.first(where: { $0.id == requestID }) {
                PermissionGuideView(spaceID: snapshot.space.id)
                    .environmentObject(model)
            }
        }
        .sheet(isPresented: $showingFusionPicker) {
            if let space = model.selected?.space {
                FusionAppPickerView(space: space)
            }
        }
        .sheet(isPresented: $showingFusionWindows) {
            if let space = model.selected?.space {
                FusionWindowPickerView(space: space)
            }
        }
        .sheet(item: $desktopSheet) { sheet in
            AccountLoginView(account: sheet.account, model: model,
                             closesWindowWhenConnected: sheet.closesWindowWhenConnected)
        }
    }

    // MARK: - Cards

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

    /// The account at a glance: its state, its session facts and its display
    /// geometry. The old in-page title header is gone — the toolbar's
    /// navigation title and the sidebar row both already carry the name — and
    /// the display card merged in here, so the page is one card shorter and
    /// the permission chips are no longer printed twice in a row.
    private func overviewCard(_ snapshot: SpaceSnapshot) -> some View {
        Card(title: NSLocalizedString("Overview", comment: "")) {
            Field(label: NSLocalizedString("Status", comment: ""), value: snapshot.statusDisplayName)
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
            // Which clients can actually launch this install's MCP service (§384).
            // 就绪 describes the desktop; this describes the client, and an account
            // on this very page has read as ready while every client registration
            // was dead — the client then reports "no AgentSpace" and drives the
            // human's own session. The two facts belong side by side.
            Field(label: NSLocalizedString("Agent connections", comment: ""),
                  value: connectionValue,
                  tint: connectionTint,
                  identifier: "agentConnectionsValue")
            if let caption = connectionCaption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let display = snapshot.display {
                Field(label: NSLocalizedString("Points", comment: ""), value: "\(display.width) × \(display.height)", monospaced: true)
                Field(label: NSLocalizedString("Pixels", comment: ""), value: "\(display.pixelWidth) × \(display.pixelHeight)", monospaced: true)
                Field(label: NSLocalizedString("Scale", comment: ""), value: "\(display.scale)×", monospaced: true)
                Text(String(format: NSLocalizedString("Input coordinates are points. A pixel read off a screenshot must be divided by %@ first.", comment: ""), "\(display.scale)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Whether ⌘V in this account's windows can carry a file, not just
            // text. It is a fact about the *worker binary*, not about the
            // desktop: a new viewer driving a pre-0.1.96 worker has to forward
            // ⌘V untouched, so the person needs somewhere to read which of the
            // two they have — otherwise the difference between "the feature is
            // broken" and "the worker is old" is invisible (§397).
            Field(label: NSLocalizedString("Clipboard paste", comment: ""),
                  value: clipboardPasteValue(snapshot),
                  tint: clipboardPasteTint(snapshot),
                  identifier: "agentClipboardBridgeValue")
            if snapshot.clipboardBridge == nil {
                Text(NSLocalizedString("Update this account's Worker to paste text and files into its desktop with ⌘V.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Field(label: NSLocalizedString("Workspace", comment: ""), value: snapshot.space.workspace.displayName)
            if snapshot.space.sharedFolders.isEmpty {
                Field(label: NSLocalizedString("Shared folders", comment: ""), value: NSLocalizedString("none", comment: ""))
            } else {
                ForEach(snapshot.space.sharedFolders) { folder in
                    Field(label: NSLocalizedString("Shared", comment: ""), value: "\(folder.path) — \(folder.access.displayName)", monospaced: true)
                }
            }
        }
    }

    /// Which clients can launch this install's MCP service (§384), in the terms a
    /// person reads on this page: the client names, and what to run when one of
    /// them cannot start.
    /// Three states, because "unknown" is not "no": a sleeping worker has not
    /// been asked, and saying 「no」 there would send the person to reinstall a
    /// worker that is already current.
    private func clipboardPasteValue(_ snapshot: SpaceSnapshot) -> String {
        guard let bridge = snapshot.clipboardBridge else {
            return snapshot.workerOnline
                ? NSLocalizedString("not supported by this Worker", comment: "")
                : NSLocalizedString("unknown (Worker not running)", comment: "")
        }
        guard bridge else { return NSLocalizedString("not supported by this Worker", comment: "") }
        return snapshot.clipboardFiles == true
            ? NSLocalizedString("text and files", comment: "")
            : NSLocalizedString("text only", comment: "")
    }

    private func clipboardPasteTint(_ snapshot: SpaceSnapshot) -> Color? {
        switch snapshot.clipboardBridge {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return snapshot.workerOnline ? .orange : nil
        }
    }

    private var connectionValue: String {
        guard let connections = model.mcpConnections else { return NSLocalizedString("checking…", comment: "") }
        let names = connections.reachable.map(\.target.displayName)
            + connections.broken.map { "\($0.target.displayName) (\(NSLocalizedString("not usable", comment: "")))" }
        return names.isEmpty ? NSLocalizedString("none", comment: "") : names.joined(separator: ", ")
    }

    private var connectionTint: Color? {
        guard let connections = model.mcpConnections, !connections.reachable.isEmpty else { return .orange }
        return connections.broken.isEmpty ? .green : .orange
    }

    private var connectionCaption: String? {
        guard let connections = model.mcpConnections else { return nil }
        if !connections.broken.isEmpty {
            let fixes = connections.broken
                .map { MCPClients.repairCommand(for: $0.target) }
                .joined(separator: "; ")
            return String(format: NSLocalizedString("Fix: %@, then restart that client.", comment: ""), fixes)
        }
        if connections.reachable.isEmpty {
            return NSLocalizedString("No AI client is set up to use this desktop, so its sessions begin with no agentspace_* tools. Configure yours from the Install MCP Into… menu on this page, or run `agentspace integrate <target> --install` (run `agentspace integrate` with no target to list every supported client).", comment: "")
        }
        return nil
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

            // While the worker is offline or the desktop is locked, every button
            // below this point needs the session this door starts — so the door
            // goes above them. It is still one control on the page (§344): the
            // healthy state draws it after the grant buttons instead.
            if snapshot.offersSignInDoor, snapshot.signInDoorIsUrgent {
                signInDoor(snapshot)
            }

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

            if snapshot.offersSignInDoor, !snapshot.signInDoorIsUrgent {
                signInDoor(snapshot)
            }

            HStack(spacing: 8) {
                Button {
                    model.permissionGuideRequest = snapshot.space.id
                } label: {
                    Label(NSLocalizedString("Open authorization guide", comment: ""), systemImage: "checklist")
                }
                .accessibilityIdentifier("openAgentPermissionGuide")
                .disabled(model.authorizingPermission != nil || model.openingSystemSettings != nil || model.updatingWorker != nil || model.finishingSetup != nil)
            }

            if !snapshot.workerOnline {
                Label(NSLocalizedString("The worker is not running yet. Clicking any permission button will install/start it first, then open the matching System Settings pane.", comment: ""), systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The door stays on the page whatever the worker says. It used to appear
    /// only while the account was offline or locked, so the one person who most
    /// needed it — a grant ticked, the Screen Sharing window closed, two panes
    /// still to approve — had a single way back into that session: Fast User
    /// Switching, once per remaining permission. Watching that session is also
    /// the only way to approve at all while Screen Recording, the permission
    /// being granted, is still missing: the built-in viewer cannot show a frame
    /// without it.
    private func signInDoor(_ snapshot: SpaceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            doorButton(space: snapshot.space, urgent: snapshot.signInDoorIsUrgent)
            Text(snapshot.signInDoorIsUrgent
                 ? NSLocalizedString("Keep that window on screen while you approve. Every pane the buttons below open appears inside it, so all three grants happen in one visit and you never switch users.", comment: "")
                 : NSLocalizedString("Keep that window on screen while you approve. Every pane the buttons above open appears inside it, so all three grants happen in one visit and you never switch users.", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func doorButton(space: AgentAccount, urgent: Bool) -> some View {
        let label = Label(urgent
                          ? NSLocalizedString("Sign In or Unlock Agent", comment: "")
                          : NSLocalizedString("Open this desktop with Screen Sharing", comment: ""),
                          systemImage: "person.crop.circle.badge.key")
        // One handle per surface, at 16 characters or longer. Both halves are
        // about `scripts/release.sh` step 1b, which reads the identifiers layer 4
        // presses out of the bundle it is about to sign: this surface's name must
        // not be a substring of the viewer's or it could be satisfied by the other
        // view's literal, and a name of 15 bytes or fewer is a Swift *small
        // string* — inline in the String's own words, never contiguous in the
        // binary — so the check cannot see it at all (validation §386).
        let action: () -> Void = {
            desktopSheet = DesktopSheet(account: space, closesWindowWhenConnected: urgent)
        }
        let blocked = model.finishingSetup != nil || model.updatingWorker != nil || model.authorizingPermission != nil
        if urgent {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("agentSignInDoorCard")
                .disabled(blocked)
        } else {
            Button(action: action) { label }
                .accessibilityIdentifier("agentSignInDoorCard")
                .disabled(blocked)
        }
    }

    /// The one thing a freshly connected account still needs, impossible to
    /// scroll past: the worker is answering and the desktop cannot be operated
    /// until its privacy grants exist. The grants belong to the account's own
    /// session, so this banner's button opens the guide that walks it — it
    /// does not print the instructions a second time.
    private func setupBanner(_ snapshot: SpaceSnapshot) -> some View {
        let missing = (snapshot.accessibility ? 0 : 1) + (snapshot.screenRecording ? 0 : 1)
        return HStack(spacing: 14) {
            Image(systemName: "checklist")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: NSLocalizedString("%ld approval(s) away from a usable desktop", comment: ""), missing))
                    .font(.callout.weight(.semibold))
                Text(String(format: NSLocalizedString("The grants belong to %@'s own session. AgentSpace opens the right System Settings pane there; you approve, then switch back.", comment: ""), snapshot.space.username))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button {
                model.permissionGuideRequest = snapshot.space.id
            } label: {
                Text(NSLocalizedString("Start authorization…", comment: ""))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("setupBannerAuthorize")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.30), lineWidth: 1)
        )
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
                Text(NSLocalizedString("Use Sign In Agent to sign in from this desktop, or use Fast User Switching.", comment: ""))
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
                    step(5, NSLocalizedString("Return to AgentSpace", comment: ""), done: snapshot.workerOnline)
                }
                .padding(.top, 2)
                Text(NSLocalizedString("After signing in with Screen Sharing, AgentSpace finishes setup automatically. After Fast User Switching, return here and click Finish setup.", comment: ""))
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

    private func categoryTitle(_ category: Integrations.Target.Category) -> String {
        switch category {
        case .terminal: return NSLocalizedString("Command-line agents", comment: "")
        case .editor: return NSLocalizedString("Editors", comment: "")
        case .desktop: return NSLocalizedString("Desktop apps", comment: "")
        case .editorExtension: return NSLocalizedString("Editor extensions", comment: "")
        }
    }

    private func menuRegistration(_ target: Integrations.Target) -> MCPClients.Registration? {
        model.mcpConnections?.registration(for: target)
    }

    /// What a person needs at the moment of choosing a client: the ones already
    /// wired to this install first, then a reachable foreign command, then a
    /// broken entry that wants attention, then clients whose config file exists
    /// but has no AgentSpace entry, then the rest. Ties keep the declared order.
    private func menuTargets(_ category: Integrations.Target.Category) -> [Integrations.Target] {
        Integrations.installableTargets
            .filter { $0.category == category }
            .enumerated()
            .sorted { lhs, rhs in
                let left = menuRank(lhs.element)
                let right = menuRank(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    private func menuRank(_ target: Integrations.Target) -> Int {
        guard let registration = menuRegistration(target) else { return 4 }
        switch registration.verdict {
        case .current: return 0
        case .other: return 1
        case .absent: return registration.hasConfig ? 3 : 4
        default: return 2
        }
    }

    private func menuState(_ target: Integrations.Target) -> (text: String, symbol: String)? {
        guard let registration = menuRegistration(target) else { return nil }
        switch registration.verdict {
        case .current:
            return (NSLocalizedString("ready", comment: ""), "checkmark.circle")
        case .other:
            return (NSLocalizedString("reachable, but not this install", comment: ""), "questionmark.circle")
        case .packageNeverPublished, .commandMissing, .agentCLIMissing, .unreadable:
            return (NSLocalizedString("needs repair", comment: ""), "exclamationmark.triangle")
        case .absent:
            // No config file at all is not the same state as a client already
            // configured with something else; only the second is worth a mark.
            return registration.hasConfig
                ? (NSLocalizedString("not configured", comment: ""), "circle.dashed")
                : nil
        }
    }

    private func dangerCard(_ snapshot: SpaceSnapshot) -> some View {
        let space = snapshot.space
        return Card(title: NSLocalizedString("Maintenance", comment: "")) {
            HStack(spacing: 8) {
                Button(NSLocalizedString("Reveal Runtime Folder", comment: "")) { model.revealRuntimeDirectory() }
                Menu(NSLocalizedString("Install MCP Into…", comment: "")) {
                    ForEach(Integrations.Target.Category.allCases, id: \.self) { category in
                        let targets = menuTargets(category)
                        if !targets.isEmpty {
                            Section(header: Text(categoryTitle(category))) {
                                ForEach(targets, id: \.self) { target in
                                    Button {
                                        integrationTarget = target
                                        showingIntegrationConfirm = true
                                    } label: {
                                        if let state = menuState(target) {
                                            Label {
                                                Text(verbatim: "\(target.displayName) — \(state.text)")
                                            } icon: {
                                                Image(systemName: state.symbol)
                                            }
                                        } else {
                                            Text(verbatim: target.displayName)
                                        }
                                    }
                                }
                            }
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


            // Stop keeps the session; Disconnect removes only
            // AgentSpace-owned setup. Both used to live in the toolbar's gear
            // menu, which repeated this card.
            HStack(spacing: 8) {
                Button(NSLocalizedString("Stop Agent", comment: "")) {
                    if let space = model.selected?.space { model.stopWorker(space) }
                }
                .disabled(snapshot.workerOnline != true)
                .help(Text("Stops this account's background worker. The macOS session stays signed in."))

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
