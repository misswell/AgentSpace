import Foundation
import AgentSpaceCore
import os

/// One job left over from the removed fixed-address feature (§406): a Mac
/// that switched it on while running 0.1.99–0.1.104 may still carry a
/// `127.100.x.y` alias on `lo0`, and nothing else will ever remove it. At
/// launch the app asks the helper to take down any alias this product could
/// have derived — never an address the derivation could not produce (the
/// §404 rule; a person's own manually-added address survives).
///
/// The two alias operations stay in the helper's closed list so an old
/// helper, whatever release it came from, still accepts the removal call on
/// the first launch after this update.
enum LoopbackAliasCleaner {
    private static let log = Logger(
        subsystem: BundleIdentifiers.logSubsystem, category: "alias-cleanup")
    private static var done = false

    @MainActor static func cleanOnce() {
        guard !done else { return }
        done = true
        Task.detached(priority: .utility) {
            let registry = SpaceRegistry.load()
            let derivable = Set(
                AgentLoopbackAddress.addresses(for: registry.spaces.map(\.id))
                    .values.map(\.rawValue))
            guard !derivable.isEmpty else { return }
            let present = (LocalNetworkProbe.interfaceSnapshot()?.addresses ?? [])
                .filter(AgentLoopbackAddress.isAlias)
            guard !present.isEmpty else { return }
            for address in present where derivable.contains(address.rawValue) {
                do {
                    let reply = try HelperClient.call(
                        HelperRequest(operation: .removeLoopbackAlias, address: address.description),
                        timeout: 10)
                    if let error = reply.error {
                        log.error("alias \(address.description, privacy: .public) not removed: \(error.code.rawValue, privacy: .public) \(error.message, privacy: .public)")
                    } else {
                        log.info("leftover alias \(address.description, privacy: .public) removed")
                    }
                } catch {
                    // The helper may be missing or old; the next launch tries
                    // again. An inert alias on lo0 is the cost of not retrying
                    // harder, and it is only that.
                    log.error("alias \(address.description, privacy: .public) not removed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }
}
