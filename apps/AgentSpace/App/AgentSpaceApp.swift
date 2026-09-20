import SwiftUI
import AgentSpaceCore

/// The window's layout shell — plan §27's two-pane dashboard, native macOS.
struct RootView: View {
    @EnvironmentObject private var model: AppModel

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
        .onAppear { model.reload() }
        // Running-app delivery goes through the scene modifier; the delegate
        // below handles only the launch-storm dedup.
        .onOpenURL { model.handleDeepLink($0) }
    }
}

@main
struct AgentSpaceApp: App {
    @StateObject private var model = AppModel()

    /// Bring the main window forward, optionally selecting one account.
    /// The menu bar must not rely on SwiftUI's window-management APIs here:
    /// activating the app and ordering the WindowGroup's window front is the
    /// whole job, and it works whether or not the window is already open.
    private func showMainWindow(selecting id: UUID? = nil) {
        if let id { model.selection = id }
        NSApp.activate(ignoringOtherApps: true)
        let window = NSApp.windows.first { $0.toolbar != nil || $0.title == "AgentSpace" }
        window?.makeKeyAndOrderFront(nil)
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
        appDelegate.model = model
    }

    var body: some Scene {
        WindowGroup("AgentSpace") {
            RootView()
                .environmentObject(model)
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
            SettingsView().environmentObject(model)
        }
    }
}

/// Receives `agentspace://` open events through the AppKit documents path.
/// Holding the model here is safe: the adaptor creates the delegate before the
/// first scene, and the model is the app's single source of truth.
final class OpenLinkDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { model?.handleDeepLink(url) }
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
            let mains = NSApp.windows.filter {
                // WindowGroup titles are the selected agent's display name
                // (for example, "AgentUse"), not the scene label.  The
                // toolbar is the stable AppKit marker for the dashboard
                // window; matching the old fixed title left restored
                // duplicates alive and made every settings sheet ambiguous.
                !$0.isSheet && $0.toolbar != nil
            }
            // State restoration can recreate the dashboard without ordering it
            // on screen. That leaves a healthy process with no usable window,
            // which looks exactly like a hung app after switching accounts.
            // Activation is the user's request to see the app, so make the
            // surviving dashboard visible before closing any duplicates.
            mains.first?.makeKeyAndOrderFront(nil)
            for extra in mains.dropFirst() { extra.close() }

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
    @AppStorage("statusRefreshSeconds") private var statusRefreshSeconds = 3.0
    @AppStorage("previewMaxWidth") private var previewMaxWidth = 1600
    @AppStorage("fusionFPSPolicy") private var fusionFPSPolicy = 0
    @State private var advancedRoot = AgentSpaceEnvironment.rootOverride ?? ""

    var body: some View {
        TabView {
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

            Form {
                Section {
                    Picker("Fusion FPS", selection: $fusionFPSPolicy) {
                        Text("Auto").tag(0); Text("5 FPS").tag(5); Text("10 FPS").tag(10); Text("15 FPS").tag(15)
                    }
                    Text("Auto uses 15 FPS for the key Agent window, 5 FPS for other visible windows, and 0 FPS while minimized.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Performance", systemImage: "gauge.with.dots.needle.67percent") }

            Form {
                Section {
                    Slider(value: $statusRefreshSeconds, in: 2...10, step: 1) {
                        Text(String(format: NSLocalizedString("Status refresh: %lds", comment: ""), Int(statusRefreshSeconds)))
                    }
                    Picker("Preview width", selection: $previewMaxWidth) {
                        Text("960 px").tag(960); Text("1280 px").tag(1280)
                        Text("1600 px").tag(1600); Text("1920 px").tag(1920)
                    }
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
