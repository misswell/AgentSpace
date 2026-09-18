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
            NewSpaceView().environmentObject(model)
        }
        // Provisioning is a sheet rather than a spinner because creating a Space
        // makes real changes to the machine, and if a step fails the user needs to
        // see which one — and whether it was undone.
        .sheet(item: $model.provisioning) { provisioning in
            ProvisioningView(provisioning: provisioning) { model.dismissProvisioning() }
        }
        .sheet(item: $model.revealedPassword) { revealed in
            LoginPasswordView(revealed: revealed) { model.revealedPassword = nil }
        }
        .sheet(isPresented: $model.showingDoctor) {
            DoctorView().environmentObject(model)
        }
        .alert(item: $model.lastError) { error in
            Alert(
                title: Text(error.code),
                message: Text([error.message, error.fix].compactMap { $0 }.joined(separator: "\n\n")),
                dismissButton: .default(Text("OK")))
        }
        .onAppear { model.reload() }
        // `agentspace://space/<uuid>` — from the CLI's `desktop` command or any
        // other poster. Handled by the model so the failure of a dead link is
        // visible in the app's own error presentation.
        .onOpenURL { model.handleDeepLink($0) }
    }
}

@main
struct AgentSpaceApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("AgentSpace") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Agent Space…") { model.showingNewSpace = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh Spaces") { model.reload() }
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

/// Preferences. Deliberately sparse — plan §61 keeps V1 to one Mac and a few
/// Spaces, and every preference here is something the user can actually change
/// today rather than a placeholder for a phase that has not landed.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("statusRefreshSeconds") private var statusRefreshSeconds = 3.0
    @AppStorage("previewMaxWidth") private var previewMaxWidth = 1600
    @State private var advancedRoot = AgentSpaceEnvironment.rootOverride ?? ""

    var body: some View {
        TabView {
            Form {
                Section {
                    Slider(value: $statusRefreshSeconds, in: 2...10, step: 1) {
                        Text(String(format: NSLocalizedString("Status refresh: %lds", comment: ""), Int(statusRefreshSeconds)))
                    }
                    Text("Plan §53 sets a 2–5 s floor. Polling faster costs more than the app manages, so it is not offered.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Picker("Preview width", selection: $previewMaxWidth) {
                        Text("960 px").tag(960)
                        Text("1280 px").tag(1280)
                        Text("1600 px").tag(1600)
                        Text("1920 px").tag(1920)
                    }
                    Text("The Desktop Viewer captures at 1 FPS while it is open, and never while it is closed. Click coordinates are unaffected by this: they are derived from the display's own size, not the image's.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section {
                    TextField("AgentSpace root", text: $advancedRoot)
                        .textFieldStyle(.roundedBorder)
                    Text("Where Spaces, their runtime sockets and their logs live. Empty means /Users/Shared/.AgentSpace. This is read from AGENTSPACE_ROOT at launch; restart to apply.")
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
        .frame(width: 520, height: 340)
    }
}
