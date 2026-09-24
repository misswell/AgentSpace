import SwiftUI
import AgentSpaceCore

/// Listing windows is read-only. A proxy is created only for the row whose
/// explicit Open Window button the person presses.
struct FusionWindowPickerView: View {
    let space: AgentAccount

    @Environment(\.dismiss) private var dismiss
    @State private var windows: [RemoteWindow] = []
    @State private var loading = true
    @State private var error: AgentSpaceError?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose a Window to Open").font(.headline)
                Spacer()
                Button("Refresh") { load() }
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                Text(verbatim: "\(error.code.rawValue): \(error.message)")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if windows.isEmpty {
                Text("No app windows are available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(windows) { remote in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(verbatim: remote.appName).fontWeight(.medium)
                                    Text(verbatim: remote.title ?? "")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Open Window") {
                                    FusionManager.shared.openWindow(remote, for: space)
                                    dismiss()
                                }
                            }
                            .padding(8)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
        .task { load() }
    }

    private func load() {
        loading = true
        error = nil
        let space = self.space
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SpaceService().windows(for: space)
            Task { @MainActor in
                loading = false
                switch result {
                case .success(let windows): self.windows = windows
                case .failure(let error): self.error = error
                }
            }
        }
    }
}
