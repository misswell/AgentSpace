import SwiftUI
import AgentSpaceCore

/// Settings → Virtual Network.
///
/// The page is editable, and it applies through the same Core validator the CLI
/// uses. Two rules shaped it:
///
/// - **Nothing here is a report.** A page that shows a pool but cannot change it
///   is a defect (the owner's rule: a settings page that only reports state is
///   not a settings page). Every value shown is in a control that writes it.
/// - **A change is previewed before it is committed.** Applying a pool or an
///   address runs the validator, shows the exact address changes and the
///   conflicts, and only then writes the configuration — keeping the previous
///   version for rollback. The tunnel is the app's to move; the page never
///   claims a tunnel change it did not make.
struct VirtualNetworkSettingsView: View {
    @State private var configuration: VirtualNetworkConfig?
    @State private var validation: NetworkValidation?
    @State private var snapshot = LocalNetworkSnapshot.unknown
    @State private var extensionState = SystemExtensionProbe(state: .unknown, detail: "")
    @State private var apiConfiguration: APIConfiguration?
    @State private var activeTokenCount = 0

    // Editing state. Text, because a half-typed address must be editable; the
    // Apply button is what turns text into a configuration.
    @State private var poolText = ""
    @State private var localText = ""
    @State private var controllerText = ""
    @State private var hubText = ""
    @State private var portText = ""
    @State private var mode = VirtualAddressMode.automatic
    @State private var allowOverlap = false
    @State private var allowNonPrivatePool = false

    @State private var statusLine: String?
    @State private var errorLine: String?
    @State private var pendingPlan: NetworkMigrationPlan?

    private let store = VirtualNetworkStore()

    var body: some View {
        Form {
            if configuration == nil {
                Section {
                    Text("No virtual network is configured yet.")
                    Text("Automatic mode picks a private pool that does not overlap this Mac's networks, and gives the hub, the main system and this Mac fixed addresses inside it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Choose a pool automatically") { enableNetwork() }
                        .accessibilityIdentifier("networkEnableButton")
                }
            } else {
                addressSection
                advancedSection
                apiSection
                nodesSection
                statusSection
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 460)
        .onAppear(perform: reload)
    }

    // MARK: Sections

    private var addressSection: some View {
        Section("Virtual network") {
            Picker("Mode", selection: $mode) {
                ForEach(VirtualAddressMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .accessibilityIdentifier("networkModePicker")

            TextField("Pool", text: $poolText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("networkPoolField")
            fieldHint("The CIDR this network owns, for example 100.64.7.0/24. Only RFC 1918 or 100.64.0.0/10 pools are accepted without the advanced override.")

            TextField("This Mac", text: $localText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("networkLocalField")
            TextField("Main system", text: $controllerText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("networkControllerField")
            TextField("Network hub", text: $hubText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("networkHubField")

            TextField("API port", text: $portText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("networkPortField")

            HStack {
                Button("Preview change") { preview() }
                    .accessibilityIdentifier("networkPreviewButton")
                Button("Apply") { apply() }
                    .disabled(pendingPlan == nil)
                    .accessibilityIdentifier("networkApplyButton")
                Button("Restore previous") { restorePrevious() }
                    .disabled(store.loadPrevious() == nil)
                    .accessibilityIdentifier("networkRestoreButton")
            }

            if let plan = pendingPlan {
                previewView(plan)
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Toggle("Allow a pool that overlaps a local network", isOn: $allowOverlap)
                .accessibilityIdentifier("networkAllowOverlapToggle")
            Text("Precise host routes keep other traffic out of the tunnel, so an overlapping subnet can still work. An address this Mac already holds is always refused — no route can fix that.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Allow a pool that is not private", isOn: $allowNonPrivatePool)
                .accessibilityIdentifier("networkAllowNonPrivateToggle")
            Text("Off by default. A public range inside the tunnel would collide with the real internet.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var apiSection: some View {
        Section("Remote API") {
            if let api = apiConfiguration {
                LabeledContent("Listener") {
                    Text(api.enabled
                         ? "\(configuration.map { "\($0.local.description)" } ?? "—"):\(api.port)"
                         : "Off")
                }
                LabeledContent("Tokens", value: "\(activeTokenCount) active")
                HStack {
                    Button(api.enabled ? "Disable API" : "Enable API") {
                        toggleAPI()
                    }
                    .accessibilityIdentifier("apiToggleButton")
                    Button("Create token…") { createToken() }
                        .accessibilityIdentifier("apiCreateTokenButton")
                }
                Text("The API listens only on this Mac's virtual address, never on all interfaces. Tokens are created with a scope; the secret is shown once.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Enable the virtual network first: the API binds to its address.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var nodesSection: some View {
        Section("Nodes") {
            if let configuration {
                ForEach(configuration.allNodes) { node in
                    HStack {
                        Text(node.address.description)
                            .font(.system(.body, design: .monospaced))
                        Text(node.name)
                        Spacer()
                        Text(node.role.displayName).foregroundStyle(.secondary)
                        if node.publicKey == nil {
                            Text("no key").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            if let validation {
                if validation.isValid {
                    Label("No conflicts found", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("\(validation.blocking.count + validation.overrideable.count) conflict(s) to resolve",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                ForEach(validation.conflicts) { conflict in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conflict.detail)
                        Text(conflict.remediation)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !snapshot.complete {
                    Text("This Mac's interfaces and routes could not be read, so overlap was not checked.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("System extension", value: extensionState.detail)
            if let statusLine {
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
            }
            if let errorLine {
                Text(errorLine).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func previewView(_ plan: NetworkMigrationPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Version \(plan.fromVersion) → \(plan.toVersion)")
                .font(.headline)
            if plan.isNoOp {
                Text("No address changes.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(plan.addressChanges, id: \.node) { change in
                    Text("\(change.node): \(change.from.description) → \(change.to.description)")
                        .font(.caption)
                }
            }
            if !plan.offlineNodes.isEmpty {
                Text("Offline and will keep their old address until they reconnect: \(plan.offlineNodes.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func fieldHint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Actions

    private func reload() {
        configuration = store.load()
        snapshot = LocalNetworkProbe.snapshot()
        extensionState = SystemExtensionProbe.installedState()
        apiConfiguration = APIConfiguration.load()
        activeTokenCount = APITokenStore.load().tokens.filter(\.isActive).count
        if let configuration {
            poolText = configuration.pool.description
            localText = configuration.local.description
            controllerText = configuration.controller.description
            hubText = configuration.hub.description
            portText = String(configuration.apiPort)
            mode = configuration.mode
            allowOverlap = configuration.allowOverlap
            allowNonPrivatePool = configuration.allowNonPrivatePool
            validation = VirtualNetworkValidator.validate(configuration, local: snapshot)
        } else {
            validation = nil
        }
    }

    private func candidate() -> VirtualNetworkConfig? {
        guard var base = configuration else { return nil }
        guard let pool = IPv4Network(poolText) else {
            errorLine = "“\(poolText)” is not a CIDR network."
            return nil
        }
        guard let local = IPv4Address(localText) else {
            errorLine = "“\(localText)” is not an IPv4 address."
            return nil
        }
        guard let controller = IPv4Address(controllerText) else {
            errorLine = "“\(controllerText)” is not an IPv4 address."
            return nil
        }
        guard let hub = IPv4Address(hubText) else {
            errorLine = "“\(hubText)” is not an IPv4 address."
            return nil
        }
        guard let port = Int(portText) else {
            errorLine = "“\(portText)” is not a port number."
            return nil
        }
        base.pool = pool
        base.local = local
        base.controller = controller
        base.hub = hub
        base.apiPort = port
        base.mode = mode
        base.allowOverlap = allowOverlap
        base.allowNonPrivatePool = allowNonPrivatePool
        base.version = (configuration?.version ?? 0) + 1
        return base
    }

    private func preview() {
        errorLine = nil
        statusLine = nil
        guard let candidate = candidate() else { return }
        let result = VirtualNetworkValidator.validate(candidate, local: snapshot)
        validation = result
        guard result.isValid else {
            pendingPlan = nil
            errorLine = result.conflicts
                .filter { $0.severity != .warning }
                .map { "\($0.detail) \($0.remediation)" }
                .joined(separator: " ")
            return
        }
        pendingPlan = NetworkMigrationPlan.plan(
            from: configuration!, to: candidate, offlineNodes: [])
    }

    private func apply() {
        guard let candidate = candidate() else { return }
        let result = VirtualNetworkValidator.validate(candidate, local: snapshot)
        validation = result
        guard result.isValid else {
            pendingPlan = nil
            errorLine = result.conflicts
                .filter { $0.severity != .warning }
                .map { "\($0.detail) \($0.remediation)" }
                .joined(separator: " ")
            return
        }
        do {
            try store.commit(candidate)
            pendingPlan = nil
            statusLine = "Applied version \(candidate.version). The previous version is kept for rollback."
            errorLine = nil
            reload()
        } catch {
            errorLine = "Could not write the configuration: \(error)"
        }
    }

    private func restorePrevious() {
        do {
            guard let restored = try store.restorePrevious() else {
                errorLine = "There is no previous version to restore."
                return
            }
            statusLine = "Restored version \(restored.version)."
            errorLine = nil
            pendingPlan = nil
            reload()
        } catch {
            errorLine = "Could not restore the previous configuration: \(error)"
        }
    }

    private func enableNetwork() {
        let snapshot = LocalNetworkProbe.snapshot()
        let seed = UInt64(Date().timeIntervalSince1970) ^ UInt64.random(in: 0...UInt64.max)
        let pool = VirtualAddressAllocator.choosePool(seed: seed, excluding: snapshot)
        let layout = VirtualAddressAllocator.defaultLayout(pool: pool)
        let candidate = VirtualNetworkConfig(
            pool: pool, hub: layout.hub, controller: layout.controller, local: layout.local)
        let result = VirtualNetworkValidator.validate(candidate, local: snapshot)
        guard result.isValid else {
            errorLine = result.conflicts.map(\.detail).joined(separator: " ")
            return
        }
        do {
            try store.commit(candidate)
            statusLine = "Configured \(pool.description)."
            reload()
        } catch {
            errorLine = "Could not write the configuration: \(error)"
        }
    }

    private func toggleAPI() {
        guard let configuration else { return }
        var api = apiConfiguration ?? APIConfiguration(
            enabled: false, port: configuration.apiPort)
        api.enabled.toggle()
        api.port = configuration.apiPort
        do {
            try api.save()
            apiConfiguration = api
            statusLine = api.enabled
                ? "API enabled on \(configuration.local):\(api.port)."
                : "API disabled."
        } catch {
            errorLine = "Could not write the API configuration: \(error)"
        }
    }

    private func createToken() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Create an API token", comment: "")
        alert.informativeText = NSLocalizedString(
            "The token is shown once. Choose the smallest scope that does the job.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Create", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = NSLocalizedString("Token name", comment: "")
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        do {
            let (record, secret) = try APITokenStore.create(name: field.stringValue, scopes: [.observe])
            activeTokenCount = APITokenStore.load().tokens.filter(\.isActive).count
            statusLine = "Created \(record.id). Copy it now — it is not shown again:\n\(secret)"
        } catch {
            errorLine = "Could not create the token: \(error)"
        }
    }
}
