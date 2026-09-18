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
    ],
    swiftLanguageVersions: [.v5]
)
