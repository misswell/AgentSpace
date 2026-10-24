import SwiftUI
import AgentSpaceCore
import os

/// What a window is for.
///
/// Window chrome cannot answer this: on macOS 26 the Settings window carries a
/// toolbar too (one button per tab), so the old "has a toolbar" rule matched
/// Settings as well as the dashboard and a Dock click could land on the pane
/// the person had used last (§396).
enum AgentSpaceWindowRole: Equatable {
    case dashboard
    case desktop

    /// The WindowGroup's SwiftUI id, so the dashboard can be recreated after
    /// the person closed its window.
    static let dashboardScene = "main"
}

enum AgentSpaceWindowPolicy {
    /// A window a person works in. Only windows the app tagged have a role at
    /// all, so Settings — which has no role — is never a work surface, however
    /// much its chrome resembles the dashboard's.
    static func isWorkSurface(role: AgentSpaceWindowRole?,
                              isSheet: Bool,
                              canBecomeKey: Bool) -> Bool {
        guard !isSheet, canBecomeKey, let role else { return false }
        return role == .dashboard || role == .desktop
    }
}

/// Remembers which windows are the app's work surfaces.
///
/// A weak reference, not the window's `identifier`: SwiftUI rewrites that
/// property after the content attaches, and a Dock click in the first build of
/// this round found no tagged window and created a duplicate dashboard
/// (measured 2026-10-22 in the agent session).
@MainActor
final class AgentSpaceWindowRegistry {
    static let shared = AgentSpaceWindowRegistry()

    private final class WeakWindow {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }

    private weak var dashboard: NSWindow?
    private var dashboards: [WeakWindow] = []
    private var desktops: [WeakWindow] = []

    func remember(_ window: NSWindow, as role: AgentSpaceWindowRole) {
        prune()
        switch role {
        case .dashboard:
            dashboard = window
            guard !dashboards.contains(where: { $0.window === window }) else { return }
            dashboards.append(WeakWindow(window))
        case .desktop:
            guard !desktops.contains(where: { $0.window === window }) else { return }
            desktops.append(WeakWindow(window))
        }
    }

    func forget(_ window: NSWindow) {
        dashboards.removeAll { $0.window == nil || $0.window === window }
        desktops.removeAll { $0.window == nil || $0.window === window }
        if dashboard === window { dashboard = dashboards.first?.window }
    }

    func role(of window: NSWindow) -> AgentSpaceWindowRole? {
        prune()
        if dashboards.contains(where: { $0.window === window }) { return .dashboard }
        if desktops.contains(where: { $0.window === window }) { return .desktop }
        return nil
    }

    /// Every live dashboard, in the order SwiftUI made them. More than one is
    /// the launch-storm duplicate the delegate closes; the first is the main.
    func dashboardWindows() -> [NSWindow] {
        prune()
        return dashboards.compactMap(\.window)
    }

    func isWorkSurface(_ window: NSWindow) -> Bool {
        AgentSpaceWindowPolicy.isWorkSurface(role: role(of: window),
                                             isSheet: window.isSheet,
                                             canBecomeKey: window.canBecomeKey)
    }

    /// The window a Dock click should show: the frontmost work surface AppKit
    /// has on screen, else one that is minimized or otherwise not visible.
    func workSurface() -> NSWindow? {
        NSApp.orderedWindows.first(where: isWorkSurface)
            ?? NSApp.windows.first(where: isWorkSurface)
    }

    /// The dashboard's window, if SwiftUI still owns one. A closed WindowGroup
    /// window is released, so this answers nil and the caller recreates it.
    func dashboardWindow() -> NSWindow? { dashboard }

    func dashboardState() -> String {
        guard let dashboard else { return "no dashboard reference" }
        return "dashboard ref: windows \(dashboard.windowNumber), visible \(dashboard.isVisible), miniaturized \(dashboard.isMiniaturized)"
    }

    private func prune() {
        dashboards.removeAll { $0.window == nil }
        desktops.removeAll { $0.window == nil }
        if dashboard == nil { dashboard = dashboards.first?.window }
    }
}

/// The dashboard's `openWindow`, captured where SwiftUI vends it. The app
/// delegate is not a view; without it a closed dashboard window could not be
/// brought back.
@MainActor
final class MainWindowOpener {
    static let shared = MainWindowOpener()
    var open: (() -> Void)?
}

/// Reports the NSWindow hosting this view to the registry, with its role.
private struct WindowTag: NSViewRepresentable {
    let role: AgentSpaceWindowRole

    func makeNSView(context: Context) -> NSView { TaggingView(role: role) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TaggingView: NSView {
        private let role: AgentSpaceWindowRole

        init(role: AgentSpaceWindowRole) {
            self.role = role
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            AgentSpaceWindowRegistry.shared.remember(window, as: role)
            windowLog.log("window \(window.title, privacy: .public) is a \(String(describing: self.role), privacy: .public) work surface")
        }
    }
}

/// The window's layout shell — plan §27's two-pane dashboard, native macOS.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: SoftwareUpdater
    @Environment(\.openWindow) private var openWindow
    @AppStorage("automaticallyChecksForUpdates") private var checksAutomatically = true

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            SpaceDetailView()
        }
        .sheet(isPresented: $model.showingNewSpace) {
            NewAgentWizard().environmentObject(model)
        }
        // Provisioning is a sheet rather than a spinner because creating a Space
        // makes real changes to the machine, and if a step fails the user needs to
        // see which one — and whether it was undone.
        .sheet(item: $model.provisioning) { provisioning in
            ProvisioningView(provisioning: provisioning) { model.dismissProvisioning() }
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showingDoctor) {
            DoctorView().environmentObject(model)
        }
        .alert(item: $model.lastError) { error in
            let dismiss = Alert.Button.default(Text("OK"))
            // A one-button recovery turns the alert into a fix-it dialog: the
            // secondary button runs the action, so the problem is fixed from
            // the dialog itself, never from a terminal.
            if let actionTitle = error.actionTitle, let action = error.action {
                return Alert(
                    title: Text(error.code),
                    message: Text([error.message, error.fix].compactMap { $0 }.joined(separator: "\n\n")),
                    primaryButton: dismiss,
                    secondaryButton: .default(Text(actionTitle), action: action))
            }
            return Alert(
                title: Text(error.code),
                message: Text([error.message, error.fix].compactMap { $0 }.joined(separator: "\n\n")),
                dismissButton: dismiss)
        }
        .onAppear {
            model.reload()
            MainWindowOpener.shared.open = { openWindow(id: AgentSpaceWindowRole.dashboardScene) }
        }
        // The dashboard's automatic half: the Settings slider's status tick.
        // Owned by this view's lifecycle — closing the window stops the RPCs,
        // reopening starts them after the onAppear reload — so the loop is
        // exactly as alive as the surface it serves.
        .task {
            await model.runStatusPolling()
        }
        // One quiet check per launch. Failures are logged, not shown: a banner
        // for a request the user never made is worse than no banner, and the
        // Update tab says the same thing on demand.
        .task {
            if checksAutomatically { await updater.checkForUpdates(automatic: true) }
        }
        // Running-app delivery goes through the scene modifier; the delegate
        // below handles only the launch-storm dedup.
        .onOpenURL { model.handleDeepLink($0) }
        .background(WindowTag(role: .dashboard))
    }
}

@main
struct AgentSpaceApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = SoftwareUpdater()

    /// Bring the dashboard forward, optionally selecting one account.
    /// The window is found by the role its content tagged, never by its
    /// chrome; when the person has closed it, the captured `openWindow`
    /// recreates it.
    private func showMainWindow(selecting id: UUID? = nil) {
        if let id { model.selection = id }
        NSApp.activate(ignoringOtherApps: true)
        if let window = AgentSpaceWindowRegistry.shared.dashboardWindow() {
            window.makeKeyAndOrderFront(nil)
        } else {
            MainWindowOpener.shared.open?()
        }
    }
    // The deep link arrives through the AppKit open-documents path, not
    // through `.onOpenURL`: when LaunchServices re-delivers a backlog of
    // agentspace:// events at launch, the scene-level modifier can end up on
    // more than one freshly-minted WindowGroup instance (three identical
    // windows, each with its own handler). The delegate method receives the
    // whole batch in one call on the one real window, which is what the
    // gui-verify "exactly one window" check pins.
    @NSApplicationDelegateAdaptor private var appDelegate: OpenLinkDelegate

    init() {
        // A headless verification hook. The virtual network needs a system
        // extension, and the only process macOS will accept an activation from is
        // the signed app itself — so the gate has to run the app to test the
        // path. Nothing is installed or activated unless this argument is
        // present, and it exists for `scripts/network-e2e.sh`, not for users.
        if let mode = ProcessInfo.processInfo.environment["AGENTSPACE_TUNNEL_SELFTEST"] {
            TunnelSelfTest.run(mode: mode)
        }
        appDelegate.model = model
        // The display-quality choice is read by two views and stored once. A
        // build older than this one stored a *width limit* on a key of its own,
        // so it is translated here, at launch, before either view reads it.
        DisplayQuality.migrateStoredPreference()
        MouseCaptureMode.discardRemovedPreference()
    }

    var body: some Scene {
        WindowGroup("AgentSpace", id: AgentSpaceWindowRole.dashboardScene) {
            RootView()
                .environmentObject(model)
                .environmentObject(updater)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        // The menu bar (plan(v2) §15): every agent account and its status,
        // plus the three things the main window is opened for. Reads the same
        // AppModel the window uses, so one refresh serves both.
        MenuBarExtra {
            ForEach(model.snapshots) { snapshot in
                Button {
                    showMainWindow(selecting: snapshot.space.id)
                } label: {
                    Text(snapshot.space.displayName + " — " + snapshot.effectiveState.displayName)
                }
            }
            if !model.snapshots.isEmpty { Divider() }
            Button(NSLocalizedString("Open AgentSpace", comment: "")) {
                showMainWindow()
            }
            Button(NSLocalizedString("Settings…", comment: "")) {
                showMainWindow()
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            // Only after a check has actually found something. The menu bar is
            // where an app-level fact belongs; the Update tab is where the user
            // decides, so this opens Settings rather than downloading anything.
            if let available = updater.state.availableRelease {
                Button(String(format: NSLocalizedString("Update to AgentSpace %@…", comment: ""),
                              available.version.description)) {
                    UserDefaults.standard.set("update", forKey: "settingsTab")
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
            Divider()
            Button(NSLocalizedString("Quit AgentSpace", comment: "")) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "person.2.crop.square.stack")
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(NSLocalizedString("New Agent…", comment: "")) { model.showingNewSpace = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh agents") { model.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Run Diagnostics…") { model.showingDoctor = true }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView().environmentObject(model).environmentObject(updater)
        }
    }
}

private let windowLog = Logger(subsystem: BundleIdentifiers.logSubsystem, category: "windows")

/// Receives `agentspace://` open events through the AppKit documents path.
/// Holding the model here is safe: the adaptor creates the delegate before the
/// first scene, and the model is the app's single source of truth.
@MainActor
final class OpenLinkDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { model?.handleDeepLink(url) }
    }

    /// A Dock click asks for the app's work surface. AppKit's default leaves
    /// whichever window was frontmost in front, which is Settings whenever the
    /// person checked a preference last — the report of 2026-10-22
    /// 「我点击dock栏图标，很多时候跳出设置页面」. Order the frontmost dashboard or
    /// agent desktop instead; recreate the dashboard when none is left.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.activate(ignoringOtherApps: true)
        if let window = AgentSpaceWindowRegistry.shared.workSurface() {
            window.makeKeyAndOrderFront(nil)
            windowLog.log("Dock click showed the work surface \(window.title, privacy: .public)")
            return false
        }
        if let open = MainWindowOpener.shared.open {
            windowLog.log("Dock click recreated the dashboard: \(AgentSpaceWindowRegistry.shared.dashboardState(), privacy: .public)")
            open()
            return false
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // An app can remain alive in another Fast User Switching session while
        // /Applications is replaced. Its old executable then reads new bundle
        // resources and SwiftUI can wedge. Exit that mixed-version process as
        // soon as its session becomes active; reopening uses the installed app.
        if AppBundleCompatibility.requiresRelaunch(
            runningVersion: agentSpaceVersion,
            bundleURL: Bundle.main.bundleURL) {
            NSApp.terminate(nil)
            return
        }

        // AppKit's fallback for a URL event that no scene claims is to open
        // another WindowGroup instance; a launch-time backlog of agentspace://
        // re-deliveries therefore produced N identical windows before any
        // handler could run. By didBecomeActive every such window exists, so
        // this is the first point where the extras can be closed. The main
        // window is the one SwiftUI created first; sheets are not windows.
        DispatchQueue.main.async {
            // WindowGroup titles are the selected agent's display name (for
            // example, "AgentUse"), not the scene label, and Settings has a
            // toolbar of its own — so the dashboard is the window tagged with
            // its role. The old toolbar guess could match Settings and order
            // it in front on activation (§396).
            let registry = AgentSpaceWindowRegistry.shared
            let dashboards = registry.dashboardWindows()
            // State restoration can recreate the dashboard without ordering it
            // on screen. That leaves a healthy process with no usable window,
            // which looks exactly like a hung app after switching accounts.
            // Order it only when it is the app's only window: activation from
            // a Settings window must not pull the dashboard over it.
            if let dashboard = dashboards.first, !dashboard.isVisible,
               !NSApp.windows.contains(where: { $0.isVisible && $0 !== dashboard && !$0.isSheet }) {
                dashboard.makeKeyAndOrderFront(nil)
            }
            for extra in dashboards.dropFirst() {
                registry.forget(extra)
                extra.close()
            }

            // A worker can be restarted while this account's AgentSpace window
            // remains open. Re-read the worker status when the session returns
            // to the foreground so the authorization card cannot retain the
            // pre-restart snapshot until the user discovers the manual button.
            self.model?.reload()
        }
    }
}

/// V4 settings separate account bindings, grants and capture policy so the
/// dashboard can stay focused on opening the two presentation surfaces.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(StatusRefresh.storageKey) private var statusRefreshSeconds = StatusRefresh.defaultValue
    @AppStorage(DisplayQuality.storageKey) private var displayQuality = DisplayQuality.default.rawValue
    @AppStorage(ViewerFrameRate.storageKey) private var previewFPS = ViewerFrameRate.defaultValue
    @AppStorage("settingsTab") private var selectedTab = "accounts"
    @State private var advancedRoot = AgentSpaceEnvironment.rootOverride ?? ""

    /// What the mode in force means, in the mode's own words.
    private var qualityExplanation: String {
        (DisplayQuality.parse(displayQuality) ?? .default).explanation
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Form {
                Section {
                    ForEach(model.snapshots) { snapshot in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(snapshot.space.displayName).font(.headline)
                                Text(String(format: NSLocalizedString("UID %ld", comment: ""), snapshot.space.uid))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(snapshot.effectiveState.displayName)
                        }
                    }
                    if model.snapshots.isEmpty { Text("No connected accounts") }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Accounts", systemImage: "person.2") }
            .tag("accounts")

            Form {
                ForEach(model.snapshots) { snapshot in
                    Section(snapshot.space.displayName) {
                        permissionRow("Accessibility", granted: snapshot.accessibility)
                        permissionRow("Screen Recording", granted: snapshot.screenRecording)
                        permissionRow("Full Disk Access", granted: snapshot.fileAccess, optional: true)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Permissions", systemImage: "lock.shield") }
            .tag("permissions")

            Form {
                Section {
                    Picker("Frame rate", selection: $previewFPS) {
                        ForEach(ViewerFrameRate.options, id: \.self) { fps in Text("\(fps) FPS").tag(fps) }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Performance", systemImage: "gauge.with.dots.needle.67percent") }
            .tag("performance")

            Form {
                Section {
                    Slider(value: $statusRefreshSeconds, in: 2...10, step: 1) {
                        Text(String(format: NSLocalizedString("Status refresh: %lds", comment: ""), Int(statusRefreshSeconds)))
                    }
                    .accessibilityIdentifier("statusRefreshSlider")
                    // What the control drives, in one sentence: the dashboard's
                    // automatic status tick. §367 found this slider promising a
                    // refresh nothing performed; the caption exists so the
                    // control's meaning is on the screen and not only in the
                    // validation log.
                    Text("The dashboard refreshes account status automatically on this interval; heavier checks (helper, worker versions, disk) stay event-driven.")
                        .font(.caption).foregroundStyle(.secondary)
                    // One control, one key, the same options as the viewer's
                    // footer — see `DisplayQualityPicker`. The mode chosen here is
                    // what the live stream and the saved snapshot both use.
                    DisplayQualityPicker(identifier: "displayQualityPicker")
                    Text(qualityExplanation)
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("AgentSpace root", text: $advancedRoot)
                        .textFieldStyle(.roundedBorder)
                    Text("Where accounts, runtime sockets and logs live. Empty means /Library/Application Support/AgentSpace. AGENTSPACE_ROOT is read at launch; restart to apply.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Reveal Log Folder") {
                        NSWorkspace.shared.selectFile(nil,
                            inFileViewerRootedAtPath: RuntimePaths.root + "/Logs")
                    }
                    Button("Copy MCP Configuration") { model.copyMCPConfiguration() }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            .tag("advanced")

            // Declared after Advanced and before Update on purpose: layer 4's
            // console gate clicks toolbar button 4 and expects the Advanced
            // slider, and it finds the update tab as the *last* button. Adding
            // this tab between them keeps both readings true.
            VirtualNetworkSettingsView()
                .tabItem { Label("Virtual Network", systemImage: "network") }
                .tag("network")

            // Declared last: `scripts/gui-verify.sh` finds the Advanced tab as the
            // fourth toolbar button, so the tab order is a gate contract.
            SoftwareUpdateView()
                .tag("update")
        }
        .frame(width: 620, height: 420)
    }

    private func permissionRow(_ title: LocalizedStringKey, granted: Bool?, optional: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let granted {
                Label(granted ? "Granted" : "Not Granted", systemImage: granted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(granted ? .green : .secondary)
            } else {
                Text(optional ? "Optional" : "Unknown").foregroundStyle(.secondary)
            }
        }
    }
}
