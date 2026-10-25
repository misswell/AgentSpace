import Foundation
import Network

/// Whether something answers a TCP connect. Never on a hot path; blocking
/// with a timeout is the point. Born in `PortForwarder.swift` for the port
/// map's freeness probes; the port map is gone (§406) and the API feature's
/// port checks are what keep this alive.
public enum TCPProbe {

    public static func answers(host: String, port: UInt16, timeout: TimeInterval = 1.5) -> Bool {
        let queue = DispatchQueue(label: "com.agentspace.portmap.probe")
        let semaphore = DispatchSemaphore(value: 0)
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        var answered = false
        var settled = false
        func finish(_ value: Bool) {
            guard !settled else { return }
            settled = true
            answered = value
            semaphore.signal()
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.cancel()
                finish(true)
            case .failed:
                finish(false)
            case .cancelled:
                // Reached without `.ready`: our own post-timeout cancel, or a
                // cancellation we did not ask for. Either way, no answer.
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + timeout)
        connection.stateUpdateHandler = nil
        connection.cancel()
        return answered
    }
}
