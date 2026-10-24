import Foundation
import NetworkExtension

/// The packet-tunnel system extension's entry point.
///
/// macOS runs this file as the extension's main executable. `NEProvider`
/// installs the provider and parks the main run loop; there is deliberately
/// nothing else here, because anything that runs before the provider is set up
/// happens outside the Network Extension lifecycle and would be invisible to it.
autoreleasepool {
    NEProvider.startSystemExtensionMode()
}
dispatchMain()
