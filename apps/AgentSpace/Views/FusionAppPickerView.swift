import AppKit
import SwiftUI
import AgentSpaceCore

/// The Fusion app picker: what is *installed* in the Space, and one button to
/// bring it up there.
///
/// Before this existed, Fusion could only mirror what was already running:
/// 「打开应用」 showed proxies for the windows that happened to be open, so the
/// product's own promise — fuse Safari, Terminal or Xcode on their own — began
/// with "start it some other way first". The worker answers the missing question
/// (`apps.available`, additive at protocol version 1) and this is its surface.
///
/// The search filters locally against the reply that already arrived: typing
/// costs no round trip, and the list cannot blink through a loading state while
/// somebody types.
struct FusionAppPickerView: View {
    let space: AgentAccount

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var apps: [InstalledApplication] = []
    @State private var failure: AgentSpaceError?
    @State private var loading = true
    /// The path currently being launched, so one row can say so instead of the
    /// whole sheet freezing.
    @State private var launching: String?
    @State private var launchFailure: AgentSpaceError?

    /// Recently fused apps, most recent first. Kept per Space: two agents have
    /// different jobs, and a shared list would be wrong for both.
    @State private var recent: [String] = []

    private var matches: [InstalledApplication] {
        ApplicationCatalog.filtered(apps, query: query)
    }

    /// The recent list, resolved against what is actually installed — an app
    /// uninstalled since is dropped rather than shown as a broken row.
    private var recentApps: [InstalledApplication] {
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return recent.compactMap { path in apps.first { $0.path == path } }
    }

    private var recentPaths: Set<String> { Set(recentApps.map(\.path)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose an App to Fuse")
                .font(.headline)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(NSLocalizedString("Search applications", comment: ""), text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("fusionAppSearchField")
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fusionAppSearchClear")
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))

            content

            if let launchFailure {
                Text(verbatim: "\(launchFailure.code.rawValue): \(launchFailure.message)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("fusionAppLaunchError")
            }

            HStack {
                Text("Fusing an app starts it inside \(space.name)'s own desktop, not on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("fusionAppPickerCancel")
            }
        }
        .padding(20)
        // A definite size rather than a minimum: a picker is a fixed little
        // window, and `minWidth` lets the longest row's ideal width — which for
        // a row containing an absolute path is very long — decide how big the
        // sheet becomes.
        .frame(width: 620, height: 480)
        .task { load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            centered(Text("Loading applications…"))
        } else if let failure {
            centered(VStack(spacing: 6) {
                Text("Could not list applications")
                    .font(.headline)
                Text(verbatim: "\(failure.code.rawValue): \(failure.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            })
        } else if matches.isEmpty {
            centered(Text("No application matches that search"))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !recentApps.isEmpty {
                        sectionHeader(Text("Recently used"))
                        ForEach(recentApps, id: \.path) { row($0) }
                        sectionHeader(Text("All applications"))
                    }
                    ForEach(matches, id: \.path) { row($0) }
                }
            }
            .accessibilityIdentifier("fusionAppList")
        }
    }

    private func centered<Content: View>(_ view: Content) -> some View {
        VStack {
            Spacer()
            view.foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(_ text: Text) -> some View {
        text.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
    }

    private func row(_ app: InstalledApplication) -> some View {
        HStack(spacing: 10) {
            icon(app)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: app.name).lineLimit(1)
                Text(verbatim: app.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            // Takes the width left after the icon, the badge and the button, and
            // truncates inside it: an absolute path has no business deciding how
            // wide the sheet is.
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            if app.isRunning {
                // Already up in that session: the useful action is to show the
                // windows it has, not to start a second copy of it.
                Text("Running").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("fusionAppRunningBadge")
                Button(NSLocalizedString("Show Windows", comment: "")) { fuse(app) }
                    .accessibilityIdentifier("fusionAppShowButton")
            } else {
                Button(NSLocalizedString("Fuse", comment: "")) { fuse(app) }
                    .accessibilityIdentifier("fusionAppFuseButton")
                    .disabled(launching != nil)
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("fusionAppRow")
    }

    @ViewBuilder
    private func icon(_ app: InstalledApplication) -> some View {
        if let base64 = app.icon, let data = Data(base64Encoded: base64), let image = NSImage(data: data) {
            Image(nsImage: image).resizable().frame(width: 24, height: 24)
        } else {
            // A row without an icon is honest; a fabricated one would hide that
            // the bundle could not be read.
            Image(systemName: "app.dashed").frame(width: 24, height: 24).foregroundStyle(.secondary)
        }
    }

    // MARK: - Loading and launching

    private func load() {
        loading = true
        failure = nil
        recent = FusionManager.shared.recentApps(for: space)
        let space = self.space
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SpaceService().availableApps(for: space)
            Task { @MainActor in
                loading = false
                switch result {
                case .success(let apps): self.apps = apps
                case .failure(let error): self.failure = error
                }
            }
        }
    }

    private func fuse(_ app: InstalledApplication) {
        launching = app.path
        launchFailure = nil
        FusionManager.shared.fuse(app: app, in: space) { error in
            launching = nil
            if let error {
                // Stay open on a failure: the sheet is where the reason is
                // readable, and closing it would leave the person with a row
                // that did nothing.
                launchFailure = error
                return
            }
            FusionManager.shared.rememberRecent(app: app, for: space)
            dismiss()
        }
    }
}
