import AppKit
import Foundation
import AgentSpaceCore

/// The account's fast input channel, shared by every surface that drives it.
///
/// A Space has one session, one pointer and one human lease, so it gets one
/// connection: the desktop viewer and any number of Fusion proxies post through
/// the same socket, tagged with the target each packet is aimed at. The
/// alternative — a socket per proxy — has a failure the shared one cannot: two
/// connections are two write queues, and a proxy whose remote window stopped
/// answering could put its backlog in front of a click meant for the desktop.
///
/// The socket's lifetime is reference-counted, because surfaces open and close
/// independently: the first holder connects, the last one releases, and a worker
/// restart is one reconnect for every window of that account.
@MainActor
final class InputChannelRegistry {
    static let shared = InputChannelRegistry()

    private var channels: [UUID: InputChannel] = [:]

    func channel(for space: AgentAccount) -> InputChannel {
        if let existing = channels[space.id] { return existing }
        let channel = InputChannel(space: space)
        channels[space.id] = channel
        return channel
    }

    func discard(_ spaceID: UUID) {
        channels.removeValue(forKey: spaceID)?.shutdown()
    }
}

/// One account's connection, with a use count so the socket lives exactly as
/// long as somebody is looking at that account's desktop.
@MainActor
final class InputChannel {
    let space: AgentAccount
    /// The socket itself. Exposed because every surface wants the same two
    /// things from it and wrapping each one would only add a place for them to
    /// disagree about a refusal.
    private(set) var client: InputClient?
    private var uses = 0

    init(space: AgentAccount) { self.space = space }

    /// A surface asks for the channel. The first use opens the socket; later
    /// ones share it.
    @discardableResult
    func use() -> InputClient {
        uses += 1
        if let client { return client }
        let created = InputClient(space: space)
        client = created
        created.connect()
        return created
    }

    /// A surface stopped using it. The last one closes the socket.
    func endUse() {
        uses = max(0, uses - 1)
        guard uses == 0 else { return }
        client?.disconnect()
        client = nil
    }

    /// Drop the socket and open a new one. Used when the worker restarted: the
    /// old connection is to a process that no longer exists.
    func reconnect() {
        client?.disconnect()
        client = nil
        guard uses > 0 else { return }
        let created = InputClient(space: space)
        client = created
        created.connect()
    }

    func shutdown() {
        uses = 0
        client?.disconnect()
        client = nil
    }
}
