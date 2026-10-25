import SwiftUI
import AgentSpaceCore

/// The account page's listening-ports card — the one piece of the removed
/// port map (§406) that stays, because the question it answers is still
/// real: *what is this account's session listening on right now?* Every
/// account shares one loopback with the main system, so each row is already
/// callable from the main system at `127.0.0.1:<the same port>` with no
/// forwarding at all — the card names the ports, the machine does the rest.
///
/// The list is the account's own worker's word (`ports.list`, lsof as that
/// uid), refreshed every few seconds; the precondition strip appears only
/// when the worker cannot be asked, with the button that fixes it.
struct ListeningPortsCard: View {
    let account: AgentAccount
    @EnvironmentObject private var model: AppModel

    enum WorkerState: Equatable { case offline, tooOld }

    @State private var listening: [ListeningPort] = []
    @State private var workerState: WorkerState?

    var body: some View {
        Card(title: NSLocalizedString("Listening Ports", comment: "")) {
            Text(NSLocalizedString("TCP ports this account's own processes are listening on, refreshed automatically. Every account on this Mac shares one loopback, so the main system already reaches each of them at 127.0.0.1 with the same port number — no mapping needed.", comment: ""))
                .font(.caption).foregroundStyle(.secondary)

            preconditionStrip

            if workerState == nil {
                if displayedPorts.isEmpty {
                    Text(NSLocalizedString("Nothing is listening in this account yet. Start the service in the agent's desktop and the port appears here within seconds.", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("agentPortsEmptyRow")
                } else {
                    ForEach(displayedPorts, id: \.port) { port in
                        HStack(spacing: 8) {
                            Text(String(port.port))
                                .font(.system(.body, design: .monospaced))
                            if let process = port.process {
                                Text("· \(process)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(port.address)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("agentPortsRow")
                    }
                }
            }
        }
        .accessibilityIdentifier("agentPortsCardView")
        .task(id: account.id) {
            await refreshLoop()
        }
    }

    // MARK: Preconditions — only when something stands in the way

    private var preconditionStrip: some View {
        Group {
            if let state = workerState {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: state == .tooOld
                          ? "arrow.triangle.2.circlepath" : "moon.zzz")
                        .foregroundStyle(.orange)
                    Text(state == .tooOld
                         ? NSLocalizedString("The worker is older than this feature; the port list appears after one update.", comment: "")
                         : NSLocalizedString("The worker is offline — the account's desktop may be signed out or asleep. The list retries automatically every few seconds; opening the desktop brings it back.", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if state == .tooOld {
                        Button(NSLocalizedString("Update Worker", comment: "")) {
                            model.updateWorker(account)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("agentPortsFixWorkerButton")
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: Data

    /// Distinct ports: several sockets can share a port (several addresses or
    /// file descriptors); a loopback-covering row wins the representative
    /// slot, the same choice the CLI makes.
    private var displayedPorts: [ListeningPort] {
        var distinct: [UInt16: ListeningPort] = [:]
        for row in listening.sorted(by: { $0.port < $1.port }) {
            if let existing = distinct[row.port], existing.coversLoopback, !row.coversLoopback { continue }
            distinct[row.port] = row
        }
        return distinct.values.sorted { $0.port < $1.port }
    }

    // MARK: Actions

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
