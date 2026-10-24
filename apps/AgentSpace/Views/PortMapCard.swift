import SwiftUI
import AgentSpaceCore

/// The account page's port-map card — the whole feature, no command line:
///
/// - the mappings that exist, each answering on `127.0.0.1:<external>` and,
///   when the account's fixed address is on, on `127.100.x.y:<internal>` too;
/// - an add-mapping form: the account's port (pickable from what its session
///   really listens on) and, optionally, the main-system port a person wants
///   (`8080` → `28080`), left empty to generate one;
/// - the fixed-address switch, off by default, which is the only thing that
///   ever involves the privileged helper.
struct PortMapCard: View {
    let account: AgentAccount
    @EnvironmentObject private var runtime: PortMapRuntime

    @State private var listening: [ListeningPort] = []
    @State private var workerNotice: String?
    @State private var actionError: String?

    // The add-mapping form.
    @State private var internalPortText = ""
    @State private var externalPortText = ""

    var body: some View {
        Card(title: NSLocalizedString("Port Map", comment: "")) {
            Text(NSLocalizedString("Each mapping answers on 127.0.0.1 at a fixed port — generated, or one you choose (for example 8080 → 28080). Call it from the main system with no network at all; mappings are served while AgentSpace is open.", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("agentPortMapCardCaption")

            if let workerNotice {
                Text(workerNotice).font(.caption).foregroundStyle(.secondary)
            }
            if let actionError {
                Text(actionError).font(.caption).foregroundStyle(.red)
            }

            addMappingSection
            if !runtime.entries.filter({ $0.account == account.id }).isEmpty {
                mappingsSection
            }
            addressSection
        }
        .accessibilityIdentifier("agentPortMapCardView")
        .task(id: account.id) {
            await refreshLoop()
        }
    }

    // MARK: Add a mapping

    private var addMappingSection: some View {
        Group {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Add a mapping", comment: ""))
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    TextField(NSLocalizedString("Agent account port", comment: ""), text: $internalPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .accessibilityIdentifier("agentPortMapInternalField")
                    TextField(NSLocalizedString("Main-system port", comment: ""), text: $externalPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .accessibilityIdentifier("agentPortMapExternalField")
                    Button(NSLocalizedString("Add", comment: "")) { addMapping() }
                        .buttonStyle(.borderedProminent)
                        .disabled(internalPortText.isEmpty)
                        .accessibilityIdentifier("agentPortMapAddButton")
                }
                Text(NSLocalizedString("The left port is the one this account listens on; the right one is what the main system calls — leave it empty to generate one. The left field also offers what the account is listening on right now.", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !listening.isEmpty {
                HStack(spacing: 6) {
                    Text(NSLocalizedString("Listening now:", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(displayedPorts, id: \.port) { port in
                        Button {
                            internalPortText = String(port.port)
                            externalPortText = ""
                        } label: {
                            Text("\(port.port)" + (port.process.map { " · \($0)" } ?? ""))
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!port.coversLoopback)
                    }
                }
            }
        }
    }

    // MARK: The mappings

    private var mappingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("Mapped ports", comment: ""))
                .font(.subheadline.weight(.semibold))
            ForEach(runtime.entries.filter { $0.account == account.id }) { entry in
                mappingRow(entry)
            }
        }
    }

    private func mappingRow(_ entry: PortMapRuntime.Entry) -> some View {
        let listeningNow = Set(displayedPorts.map(\.port))
        let serviceDown = !listeningNow.contains(entry.port)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(String(entry.port))
                        .font(.system(.body, design: .monospaced))
                    Image(systemName: "arrow.right")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(entry.endpoint)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("agentPortMapEndpointValue")
                    Text(entry.state.displayName)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let alias = entry.aliasEndpoint {
                    HStack(spacing: 8) {
                        Text(String(entry.port))
                            .font(.system(.caption, design: .monospaced))
                        Image(systemName: "arrow.right")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(alias)
                            .font(.system(.caption, design: .monospaced))
                        Text(entry.aliasState?.displayName ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if serviceDown {
                    Text(NSLocalizedString("mapped, but nothing is listening on it right now", comment: ""))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(NSLocalizedString("Remove", comment: "")) {
                unmap(entry.port)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: The fixed address

    private var addressSection: some View {
        Group {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: addressBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Give this account a fixed address", comment: ""))
                        Text(NSLocalizedString("Off by default. When on, the already-installed helper puts one address of the feature's own range (127.100.0.0/16) onto the loopback interface for this account, and every mapped port answers there at its own port number too. Nothing runs and nothing is authorized while this is off.", comment: ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("agentPortMapAddressToggle")

                switch runtime.addressStates[account.id] ?? .off {
                case .off:
                    EmptyView()
                case .pending:
                    Text(NSLocalizedString("Setting up…", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                case .active(let address):
                    HStack(spacing: 6) {
                        Text(String(format: NSLocalizedString("Active: %@", comment: ""), address))
                            .font(.system(.caption, design: .monospaced))
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(address, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Copy address", comment: ""))
                    }
                case .failed(let reason):
                    Text(String(format: NSLocalizedString("Not active: %@", comment: ""), reason))
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var addressBinding: Binding<Bool> {
        Binding(
            get: { runtime.isAddressEnabled(account.id) },
            set: { newValue in
                do {
                    try runtime.setAddressEnabled(account.id, newValue)
                } catch {
                    actionError = String(
                        format: NSLocalizedString("Could not write the choice: %@", comment: ""),
                        String(describing: error))
                }
            })
    }

    // MARK: Data

    private var displayedPorts: [ListeningPort] {
        var seen = Set<UInt16>()
        var rows: [ListeningPort] = []
        for port in listening.sorted(by: { $0.port < $1.port }) where !seen.contains(port.port) {
            seen.insert(port.port)
            rows.append(port)
        }
        return rows
    }

    private func addMapping() {
        actionError = nil
        guard let internalPort = UInt16(internalPortText), internalPort != 0 else {
            actionError = NSLocalizedString("The agent account port must be a number between 1 and 65535.", comment: "")
            return
        }
        var external: UInt16?
        if !externalPortText.isEmpty {
            guard let parsed = UInt16(externalPortText), parsed != 0 else {
                actionError = NSLocalizedString("The main-system port must be a number between 1 and 65535.", comment: "")
                return
            }
            external = parsed
        }
        do {
            try runtime.map(account: account.id, port: internalPort, external: external)
            internalPortText = ""
            externalPortText = ""
        } catch {
            actionError = String(describing: (error as? AgentSpaceError)?.message ?? String(describing: error))
        }
    }

    private func unmap(_ port: UInt16) {
        actionError = nil
        do {
            try runtime.unmap(account: account.id, port: port)
        } catch {
            actionError = String(
                format: NSLocalizedString("Could not write the mapping: %@", comment: ""),
                String(describing: error))
        }
    }

    /// Poll the account's own worker for the ports it is listening on. The
    /// worker offline / too old to answer is a notice, not an error state: the
    /// mapped ports keep their forwarders, which fail closed on their own.
    private func refreshLoop() async {
        while !Task.isCancelled {
            let connection = SpaceConnection(space: account)
            let outcome = await Task.detached(priority: .utility) { () -> (ports: [ListeningPort]?, notice: String?) in
                do {
                    let response = try connection.client.call(
                        method: Method.portsList, token: connection.token, timeout: 5)
                    if response.ok, let rows = response.result?["ports"]?.arrayValue {
                        let ports = rows.compactMap { row -> ListeningPort? in
                            guard let port = row["port"]?.intValue,
                                  let portNumber = UInt16(exactly: port),
                                  let address = row["address"]?.stringValue else { return nil }
                            return ListeningPort(
                                address: address, port: portNumber,
                                process: row["process"]?.stringValue,
                                pid: row["pid"]?.intValue)
                        }
                        return (ports, nil)
                    }
                    if let error = response.error, error.code == .methodNotFound {
                        return (nil, NSLocalizedString(
                            "The worker is older than this feature. Update it (the app offers this after an app update) and the port list appears here.", comment: ""))
                    }
                    return (nil, NSLocalizedString(
                        "The worker could not list this account's ports.", comment: ""))
                } catch {
                    return (nil, NSLocalizedString(
                        "The worker is offline, so this account's ports cannot be listed. Mapped ports refuse connections until it is back.", comment: ""))
                }
            }.value
            listening = outcome.ports ?? []
            workerNotice = outcome.notice
            try? await Task.sleep(for: .seconds(5))
        }
    }
}
