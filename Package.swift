// swift-tools-version: 5.9
//
// AgentSpace — run AI agents in isolated macOS desktop sessions.
//
// One package, three shipped artifacts:
//   AgentSpaceCore        shared protocol + models + safety logic (library)
//   agentspace-worker     the per-Space daemon that lives in an Aqua session
//   agentspace            the CLI (also the transport the GUI and MCP use)
//
// Swift 5 language mode is deliberate. The worker intentionally holds plain
// mutable state shared across a serial connection queue (mirroring the shape
// that has been measured to work); Swift 6 strict concurrency would demand a
// rewrite that buys nothing for a single-session daemon.

import PackageDescription

let package = Package(
    name: "AgentSpace",
    // Deliberately below macOS 26: the v1 runtime requirement is macOS 26+,
    // but compiling against a lower deployment target keeps us honest about
    // not reaching for macOS 26-only API. See docs/architecture.md.
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AgentSpaceCore", targets: ["AgentSpaceCore"]),
        .executable(name: "agentspace-worker", targets: ["AgentSpaceWorker"]),
        .executable(name: "agentspace", targets: ["AgentSpaceCLI"]),
        // Named `AgentSpaceApp`, not `AgentSpace`, because the CLI product is
        // `agentspace` and the default macOS filesystem is case-insensitive: two
        // products whose names differ only in case land on the same path in
        // `.build/debug` and silently overwrite each other. The bundle renames it
        // to `AgentSpace` on the way in, where the destinations differ.
        .executable(name: "AgentSpaceApp", targets: ["AgentSpaceApp"]),
        .executable(name: "agentspace-session-test", targets: ["SessionAcceptanceTest"]),
        .executable(name: "agentspace-helper", targets: ["AgentSpacePrivilegedHelper"]),
    ],
    targets: [
        .target(
            name: "AgentSpaceCore",
            path: "shared/Core/Sources/AgentSpaceCore"
        ),
        .executableTarget(
            name: "AgentSpaceWorker",
            dependencies: ["AgentSpaceCore"],
            path: "native/AgentSpaceWorker/Sources/AgentSpaceWorker"
        ),
        .executableTarget(
            name: "AgentSpaceCLI",
            dependencies: ["AgentSpaceCore"],
            path: "native/AgentSpaceCLI/Sources/AgentSpaceCLI"
        ),
        // The GUI. An executable rather than an app bundle target because SwiftPM
        // has no bundle product; scripts/bundle-app.sh wraps the binary into a
        // proper .app with an Info.plist, which is what TCC and the Dock need.
        .executableTarget(
            name: "AgentSpaceApp",
            dependencies: ["AgentSpaceCore"],
            path: "apps/AgentSpace",
            // Both plists are consumed by scripts/bundle-app.sh, which copies them
            // to the places macOS requires (Contents/Info.plist and
            // Contents/Library/LaunchDaemons/). Declaring them as resources would
            // put a second, ignored copy in Contents/Resources, and an Info.plist
            // sitting in Resources is both wrong and confusing.
            exclude: ["Resources/Info.plist",
                      "Resources/com.agentspace.AgentSpace.Helper.plist"]
        ),
        // The phase-0 acceptance test (plan §44), as a runnable program rather
        // than an XCTest case: it must run from the *console* session and open a
        // real TextEdit, which a test host cannot do. `swift run
        // agentspace-session-test` or scripts/acceptance.sh.
        // The privileged helper — plan §6, §7. Root, launched by launchd from a
        // SMAppService LaunchDaemon inside the app bundle.
        .executableTarget(
            name: "AgentSpacePrivilegedHelper",
            dependencies: ["AgentSpaceCore"],
            path: "native/AgentSpacePrivilegedHelper/Sources/AgentSpacePrivilegedHelper"
        ),
        .executableTarget(
            name: "SessionAcceptanceTest",
            dependencies: ["AgentSpaceCore"],
            path: "tests/Session"
        ),
        .testTarget(
            name: "AgentSpaceUnitTests",
            dependencies: ["AgentSpaceCore"],
            path: "tests/Unit"
        ),
        .testTarget(
            name: "AgentSpaceSafetyTests",
            dependencies: ["AgentSpaceCore"],
            path: "tests/Safety"
        ),
        .testTarget(
            name: "AgentSpaceIntegrationTests",
            dependencies: ["AgentSpaceCore"],
            path: "tests/Integration"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
