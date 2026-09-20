import Foundation
import ServiceManagement

/// The helper's Mach service name. It must match the `MachServices` key in
/// `com.agentspace.AgentSpace.Helper.plist` exactly; launchd owns the name, and a
/// mismatch means the listener never receives a connection and the app sees a
/// timeout rather than an error.
public let helperMachServiceName = BundleIdentifiers.helper

/// The helper's build version, bumped when its *behaviour* changes so the app can
/// tell "the helper is installed" from "the right helper is installed".
public let helperVersion = "0.1.8"

/// The XPC surface, as Objective-C sees it.
///
/// Two methods, both taking and returning `Data`. That is deliberate: the typed
/// Swift model (`HelperRequest` / `HelperResponse`) stays the single description
/// of what the helper can do, and the Objective-C layer cannot grow a method by
/// accident. There is no `@objc` method here that takes a path, a command or a
/// string to execute — the only thing a caller can send is a serialised
/// `HelperRequest`, and the helper validates that on arrival regardless of what
/// the caller believes it sent.
@objc public protocol HelperXPCProtocol {
    func perform(_ request: Data, withReply reply: @escaping (Data) -> Void)
    func ping(withReply reply: @escaping (Data) -> Void)
}

/// Why a helper call did not happen.
public enum HelperClientError: Error, CustomStringConvertible {
    case notInstalled
    case notReachable(String)
    case transport(String)
    case malformedReply

    public var description: String {
        switch self {
        case .notInstalled:
            return "the AgentSpace privileged helper is not installed"
        case .notReachable(let detail):
            return "the AgentSpace privileged helper did not answer: \(detail)"
        case .transport(let detail):
            return "the helper connection failed: \(detail)"
        case .malformedReply:
            return "the helper returned something that is not a HelperResponse"
        }
    }

    /// The code the caller should report. A missing helper is recoverable —
    /// installing it is something a human can do — and says exactly that.
    public var code: AgentSpaceErrorCode {
        switch self {
        case .notInstalled, .notReachable: return .helperUnavailable
        case .transport, .malformedReply: return .helperRejected
        }
    }

    public var agentSpaceError: AgentSpaceError {
        AgentSpaceError(code: code, message: description)
    }
}

/// Talks to the privileged helper.
///
/// Deliberately synchronous and one-shot: a connection per request, torn down
/// afterwards. The helper performs at most a handful of privileged operations in
/// a Space's whole lifetime, so pooling buys nothing and would keep a root
/// connection alive and idle — a standing target for no benefit.
public enum HelperClient {

    /// Is the LaunchDaemon registered and enabled?
    ///
    /// `SMAppService.daemon(plistName:)` requires the app to be a real bundle with
    /// the plist in `Contents/Library/LaunchDaemons`. When AgentSpace is run from
    /// a build directory this returns `.notFound`, which is the honest answer and
    /// the one the UI shows.
    public static var status: SMAppService.Status {
        SMAppService.daemon(plistName: BundleIdentifiers.helperPlist).status
    }

    public static var isInstalled: Bool {
        let value = status
        return value == .enabled || value == .requiresApproval
    }

    /// Human-readable state, for `doctor` and for the app's helper card.
    public static func statusDescription() -> String {
        switch status {
        case .enabled:
            return "installed and enabled"
        case .requiresApproval:
            return "installed, waiting for approval in System Settings → General → Login Items"
        case .notFound:
            return "not installed (no helper inside this bundle)"
        case .notRegistered:
            return "not registered"
        @unknown default:
            return "unknown state"
        }
    }

    /// Call the helper. Throws rather than returning a half-filled response, so a
    /// caller cannot mistake "the helper never answered" for "the helper said no".
    public static func call(_ request: HelperRequest, timeout: TimeInterval = 120) throws -> HelperResponse {
        let connection = NSXPCConnection(
            machServiceName: helperMachServiceName,
            options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)

        let semaphore = DispatchSemaphore(value: 0)
        var payload: Data?
        var failure: String?

        connection.invalidationHandler = {
            // Only report invalidation if no reply arrived: a normal completion
            // also invalidates the connection, and reporting both would turn every
            // success into a spurious error.
            if payload == nil, failure == nil {
                failure = "the connection was invalidated before a reply arrived"
            }
            semaphore.signal()
        }
        connection.interruptionHandler = {
            if payload == nil, failure == nil {
                failure = "the connection was interrupted"
            }
        }
        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            failure = error.localizedDescription
            semaphore.signal()
        }) as? HelperXPCProtocol else {
            connection.invalidate()
            throw HelperClientError.transport("could not obtain a remote proxy")
        }

        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(request)
        } catch {
            connection.invalidate()
            throw HelperClientError.transport("could not encode the request: \(error)")
        }

        proxy.perform(encoded) { replyData in
            payload = replyData
            semaphore.signal()
        }

        // One signal per outcome, and `invalidationHandler` also signals, so this
        // waits for whichever happens first rather than assuming an order.
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            connection.invalidate()
            throw HelperClientError.notReachable("no reply within \(Int(timeout))s")
        }
        connection.invalidate()

        if let failure, payload == nil {
            // A connection-level failure to a registered daemon usually means the
            // daemon is not running. That is `notReachable`, not a refusal.
            throw HelperClientError.notReachable(failure)
        }
        guard let payload else {
            throw HelperClientError.notReachable("the helper returned no data")
        }
        guard let response = try? JSONDecoder().decode(HelperResponse.self, from: payload) else {
            throw HelperClientError.malformedReply
        }
        return response
    }

    /// Ask the helper for its version, to distinguish "installed" from "installed
    /// but outdated". Returns `nil` if it cannot be reached.
    public static func ping(timeout: TimeInterval = 10) -> HelperResponse? {
        let connection = NSXPCConnection(machServiceName: helperMachServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)

        let semaphore = DispatchSemaphore(value: 0)
        var payload: Data?
        connection.invalidationHandler = { semaphore.signal() }
        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in semaphore.signal() }) as? HelperXPCProtocol else {
            connection.invalidate()
            return nil
        }
        proxy.ping { replyData in
            payload = replyData
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            connection.invalidate()
            return nil
        }
        connection.invalidate()
        guard let payload, let response = try? JSONDecoder().decode(HelperResponse.self, from: payload) else {
            return nil
        }
        return response
    }

    /// The AgentSpace-named accounts the helper can see, or `nil` when the
    /// helper is unreachable. Used by Doctor's orphan check: names here that
    /// have no Space record are accounts an interrupted creation left behind,
    /// and they are otherwise invisible to the app.
    public static func agentSpaceAccounts(timeout: TimeInterval = 10) -> [String]? {
        let request = HelperRequest(operation: .helperStatus)
        guard let response = try? call(request, timeout: timeout), response.ok else {
            return nil
        }
        return response.reportedAccounts
    }
}
