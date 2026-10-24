import SwiftUI
import AgentSpaceCore

/// The account page's port-map card: the ports this account's own session is
/// listening on right now, and for each one a toggle that maps it onto a
/// fixed generated port on `127.0.0.1` — the address the main system then
/// calls, with no network at all.
///
/// The list comes from the account's own worker (`ports.list`, answered by
/// lsof as that account's uid), so a port this card offers is a port this
/// account — not another one — actually serves. The forwarder itself lives in
/// `PortMapRuntime`; this card only writes the shared mapping file and shows
/// the runtime's verdict for it.
struct PortMapCard: View {
    let account: AgentAccount
    @EnvironmentObject private var runtime: PortMapRuntime

    @State private var listening: [ListeningPort] = []
    @State private var workerNotice: String?
    @State private var actionError: String?

    var body: some View {
        Card(title: NSLocalizedString("Port Map", comment: "")) {
            Text(NSLocalizedString("Map a port and it answers on a fixed generated port: call it as http://127.0.0.1:PORT from the main system, with no network at all. Mappings are served while AgentSpace is open.", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("agentPortMapCardCaption")

            if let workerNotice {
                Text(workerNotice).font(.caption).foregroundStyle(.secondary)
            }
            if let actionError {
                Text(actionError).font(.caption).foregroundStyle(.red)
            }

            ForEach(displayedPorts, id: \.port) { port in
                portRow(port)
            }
            ForEach(runtime.entries.filter { $0.account == account.id }) { entry in
                if !displayedPorts.contains(where: { $0.port == entry.port }) {
                    dormantRow(entry)
                }
            }
        }
        .accessibilityIdentifier("agentPortMapCardView")
        .task(id: account.id) {
            await refreshLoop()
        }
    }

    /// One row per distinct port: lsof can list several sockets for one port
    /// (several addresses or file descriptors), and a person maps a port, not
    /// a socket.
    private var displayedPorts: [ListeningPort] {
        var seen = Set<UInt16>()
        var rows: [ListeningPort] = []
        for port in listening.sorted(by: { $0.port < $1.port }) where !seen.contains(port.port) {
            seen.insert(port.port)
            rows.append(port)
        }
        return rows
    }

    private func portRow(_ port: ListeningPort) -> some View {
        let mapped = runtime.entries.first { $0.account == account.id && $0.port == port.port }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(port.port)).font(.system(.body, design: .monospaced))
                    Text(port.process ?? NSLocalizedString("unknown process", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                    if !port.coversLoopback {
                        Text(NSLocalizedString("not on loopback", comment: ""))
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                if let mapped {
                    HStack(spacing: 6) {
                        Text(mapped.endpoint)
                            .font(.system(.caption, design: .monospaced))
                            .accessibilityIdentifier("agentPortMapEndpointValue")
                        Text(mapped.state.displayName)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if mapped != nil {
                Button(NSLocalizedString("Unmap", comment: "")) {
                    unmap(port.port)
                }
                .buttonStyle(.borderless)
            } else {
                Button(NSLocalizedString("Map", comment: "")) {
                    map(port.port)
                }
                .buttonStyle(.borderless)
                .disabled(!port.coversLoopback)
            }
        }
    }

    /// A mapped port whose service is not in the worker's answer right now:
    /// the mapping keeps its generated port, and the forwarder refuses
    /// connections until the service is back.
    private func dormantRow(_ entry: PortMapRuntime.Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(entry.port)).font(.system(.body, design: .monospaced))
                    Text(NSLocalizedString("mapped, but nothing is listening on it right now", comment: ""))
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(entry.endpoint).font(.system(.caption, design: .monospaced))
            }
            Spacer()
            Button(NSLocalizedString("Remove", comment: "")) {
                unmap(entry.port)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: Actions

    private func map(_ port: UInt16) {
        actionError = nil
        do {
            try runtime.map(account: account.id, port: port)
        } catch {
            actionError = String(
                format: NSLocalizedString("Could not write the mapping: %@", comment: ""),
                String(describing: error))
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
            do {
                let response = try connection.client.call(
                    method: Method.portsList, token: connection.token, timeout: 5)
                if response.ok, let rows = response.result?["ports"]?.arrayValue {
                    listening = rows.compactMap { row in
                        guard let port = row["port"]?.intValue,
                              let portNumber = UInt16(exactly: port),
                              let address = row["address"]?.stringValue else { return nil }
                        return ListeningPort(
                            address: address,
                            port: portNumber,
                            process: row["process"]?.stringValue,
                            pid: row["pid"]?.intValue)
                    }
                    workerNotice = nil
                } else if let error = response.error,
                          error.code == .methodNotFound {
                    workerNotice = NSLocalizedString(
                        "The worker is older than this feature. Update it (the app offers this after an app update) and the port list appears here.", comment: "")
                } else {
                    workerNotice = NSLocalizedString(
                        "The worker could not list this account's ports.", comment: "")
                }
            } catch {
                listening = []
                workerNotice = NSLocalizedString(
                    "The worker is offline, so this account's ports cannot be listed. Mapped ports refuse connections until it is back.", comment: "")
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }
}
