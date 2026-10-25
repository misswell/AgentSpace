import SwiftUI
import AgentSpaceCore

/// The account page's port-map card — the whole feature as a person meets it,
/// planned around one rule: **every state says what it is, and every problem
/// names its fix.**
///
/// - A precondition strip appears only when something stands in the way (the
///   worker is too old or offline, the configuration folder is not prepared),
///   each with the sentence and the button that fixes it — the app's own
///   worker-update flow, one tap away.
/// - The add-mapping form validates inline, in the reader's language: every
///   refusal is a typed `ActionError` with its own sentence, never a raw
///   NSError and never an untranslated product message.
/// - Every mapping row carries three verbs — copy, open in the browser,
///   remove — and the fixed-address section explains what its states mean,
///   retries on its own, and offers a manual retry when it failed.
struct PortMapCard: View {
    let account: AgentAccount
    @EnvironmentObject private var runtime: PortMapRuntime
    @EnvironmentObject private var model: AppModel

    enum WorkerState: Equatable { case offline, tooOld }

    @State private var listening: [ListeningPort] = []
    @State private var workerState: WorkerState?
    @State private var actionError: String?
    @State private var lastAdded: String?

    // The add-mapping form.
    @State private var internalPortText = ""
    @State private var externalPortText = ""

    /// The configuration folder the helper prepares on the next worker
    /// update. Shown as a precondition, not discovered by failing.
    private var storeNotPrepared: Bool {
        !FileManager.default.fileExists(atPath: VirtualNetworkPaths().directory)
    }

    var body: some View {
        Card(title: NSLocalizedString("Port Map", comment: "")) {
            Text(NSLocalizedString("Each mapping answers on 127.0.0.1 at a fixed port — generated, or one you choose (for example 8080 → 28080). Call it from the main system with no network at all; mappings are served while AgentSpace is open.", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("agentPortMapCardCaption")

            preconditionStrip

            if let actionError {
                Text(actionError).font(.caption).foregroundStyle(.red)
            }
            if let lastAdded {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(String(format: NSLocalizedString("Mapped: %@ — usable immediately.", comment: ""), lastAdded))
                        .font(.caption)
                    Button {
                        copy(lastAdded)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Copy address", comment: ""))
                }
                .accessibilityIdentifier("agentPortMapSuccessRow")
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

    // MARK: Preconditions — only when something stands in the way

    private var preconditionStrip: some View {
        Group {
            if workerState != nil || storeNotPrepared {
                VStack(alignment: .leading, spacing: 6) {
                    if storeNotPrepared {
                        problemRow(
                            icon: "externaldrive.badge.exclamationmark",
                            text: NSLocalizedString("The configuration folder is not ready on this Mac yet — one worker update creates it. Nothing you do here is lost by trying.", comment: ""),
                            action: NSLocalizedString("Update Worker", comment: "")) {
                            model.updateWorker(account)
                        }
                    }
                    switch workerState {
                    case .tooOld:
                        problemRow(
                            icon: "arrow.triangle.2.circlepath",
                            text: NSLocalizedString("The worker is older than this feature; the port list appears after one update.", comment: ""),
                            action: NSLocalizedString("Update Worker", comment: "")) {
                            model.updateWorker(account)
                        }
                    case .offline:
                        problemRow(
                            icon: "moon.zzz",
                            text: NSLocalizedString("The worker is offline — the account's desktop may be signed out or asleep. The list retries automatically every few seconds; opening the desktop brings it back.", comment: ""),
                            action: nil, handler: nil)
                    case nil:
                        EmptyView()
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func problemRow(icon: String, text: String, action: String?, handler: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.orange)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let action, let handler {
                Button(action) { handler() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("agentPortMapFixWorkerButton")
            }
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
                        .help(port.coversLoopback
                              ? NSLocalizedString("Fill the left field with this port", comment: "")
                              : NSLocalizedString("Not on loopback; cannot be mapped", comment: ""))
                    }
                }
            } else if workerState == nil {
                Text(NSLocalizedString("Nothing is listening in this account yet. Start the service in the agent's desktop and the port appears here within seconds.", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
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
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(String(entry.port))
                    .font(.system(.body, design: .monospaced))
                Image(systemName: "arrow.right")
                    .font(.caption).foregroundStyle(.secondary)
                Text("http://\(entry.endpoint)")
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("agentPortMapEndpointValue")
                stateBadge(entry.state.displayName, healthy: entry.state == .forwarding)
                Spacer()
                Button {
                    copy("http://\(entry.endpoint)")
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help(NSLocalizedString("Copy address", comment: ""))
                Button {
                    open("http://\(entry.endpoint)")
                } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .help(NSLocalizedString("Open in browser", comment: ""))
                Button(NSLocalizedString("Remove", comment: "")) {
                    unmap(entry.port)
                }
                .buttonStyle(.borderless)
            }
            if entry.state == .waiting && !listeningNow.contains(entry.port) {
                Text(NSLocalizedString("mapped, but nothing is listening on it right now", comment: ""))
                    .font(.caption).foregroundStyle(.orange)
            }
            if let alias = entry.aliasEndpoint {
                HStack(spacing: 8) {
                    Text(String(entry.port))
                        .font(.system(.caption, design: .monospaced))
                    Image(systemName: "arrow.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("http://\(alias)")
                        .font(.system(.caption, design: .monospaced))
                    if let aliasState = entry.aliasState {
                        stateBadge(aliasState.displayName, healthy: aliasState == .forwarding)
                    }
                    Spacer()
                    Button {
                        copy("http://\(alias)")
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Copy address", comment: ""))
                    Button {
                        open("http://\(alias)")
                    } label: { Image(systemName: "safari") }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Open in browser", comment: ""))
                }
                .padding(.leading, 14)
            }
        }
        .padding(.vertical, 1)
    }

    private func stateBadge(_ text: String, healthy: Bool) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((healthy ? Color.green : Color.orange).opacity(0.15), in: Capsule())
            .foregroundStyle(healthy ? .green : .orange)
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
                    Text(NSLocalizedString("Setting up… (retries automatically until the helper answers)", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                case .active(let address):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(String(format: NSLocalizedString("Active: %@", comment: ""), address))
                            .font(.system(.caption, design: .monospaced))
                        Button {
                            copy(address)
                        } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                            .help(NSLocalizedString("Copy address", comment: ""))
                    }
                case .failed(let reason):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: NSLocalizedString("Not active: %@", comment: ""), reason))
                            .font(.caption).foregroundStyle(.red)
                        Button(NSLocalizedString("Retry", comment: "")) {
                            runtime.retryNow()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("agentPortMapRetryButton")
                    }
                }
            }
        }
    }

    private var addressBinding: Binding<Bool> {
        Binding(
            get: { runtime.isAddressEnabled(account.id) },
            set: { newValue in
                actionError = nil
                do {
                    try runtime.setAddressEnabled(account.id, newValue)
                } catch let error as PortMapRuntime.ActionError {
                    actionError = error.message
                } catch {
                    actionError = String(describing: error)
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

    // MARK: Actions

    private func addMapping() {
        actionError = nil
        lastAdded = nil
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
            let external = try runtime.map(account: account.id, port: internalPort, external: external)
            internalPortText = ""
            externalPortText = ""
            lastAdded = "127.0.0.1:\(external)"
        } catch let error as PortMapRuntime.ActionError {
            actionError = error.message
        } catch {
            actionError = String(describing: error)
        }
    }

    private func unmap(_ port: UInt16) {
        actionError = nil
        lastAdded = nil
        do {
            try runtime.unmap(account: account.id, port: port)
        } catch let error as PortMapRuntime.ActionError {
            actionError = error.message
        } catch {
            actionError = String(describing: error)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func open(_ url: String) {
        if let target = URL(string: url) {
            NSWorkspace.shared.open(target)
        }
    }

    /// Poll the account's own worker for the ports it is listening on, and
    /// carry the *kind* of worker notice so the precondition strip can offer
    /// the right fix instead of one flat sentence.
    private func refreshLoop() async {
        while !Task.isCancelled {
            let connection = SpaceConnection(space: account)
            let outcome = await Task.detached(priority: .utility) { () -> (ports: [ListeningPort]?, state: WorkerState?) in
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
                        return (nil, .tooOld)
                    }
                    return (nil, .offline)
                } catch {
                    return (nil, .offline)
                }
            }.value
            listening = outcome.ports ?? []
            workerState = outcome.state
            try? await Task.sleep(for: .seconds(5))
        }
    }
}
