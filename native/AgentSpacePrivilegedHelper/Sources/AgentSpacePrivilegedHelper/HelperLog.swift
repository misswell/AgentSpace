import Foundation
import OSLog
import AgentSpaceCore

/// The helper's log.
///
/// Separate subsystem category so a security review can read exactly what the
/// root component did: `log show --predicate 'subsystem == "com.agentspace.app"
/// AND category == "helper"'`. Everything goes through `Redaction` — a password
/// or a session token reaching `log show` would put it in a world-readable store.
final class HelperLog {
    private let logger = Logger(subsystem: BundleIdentifiers.logSubsystem, category: "helper")

    func info(_ message: String) {
        logger.info("\(Redaction.scrubString(message), privacy: .public)")
    }

    func warning(_ message: String) {
        logger.warning("\(Redaction.scrubString(message), privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(Redaction.scrubString(message), privacy: .public)")
    }
}
