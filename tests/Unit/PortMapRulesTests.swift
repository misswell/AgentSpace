import XCTest
@testable import AgentSpaceCore

/// The one pure function every mapping must satisfy before it is written —
/// shared by the app's fail-closed add path and unit-attacked here, because a
/// normal user meets these rules as sentences.
final class PortMapRulesTests: XCTestCase {

    private let listening: [ListeningPort] = [
        ListeningPort(address: "127.0.0.1", port: 8080, process: "node"),
        ListeningPort(address: "192.168.1.5", port: 5432, process: "pg"),
    ]

    func testTheHappyPathsPass() {
        XCTAssertNil(PortMapRules.validate(
            internal: 8080, listening: listening, mappedPorts: [],
            chosenExternal: 28080, takenExternals: []))
        XCTAssertNil(PortMapRules.validate(
            internal: 8080, listening: listening, mappedPorts: [],
            chosenExternal: nil, takenExternals: [28080]),
            "an auto-generated port ignores the taken set at rule level; the generator consults it")
    }

    func testEachRefusalNamesItsRule() {
        XCTAssertEqual(
            PortMapRules.validate(internal: 8081, listening: listening, mappedPorts: [],
                                  chosenExternal: 28080, takenExternals: []),
            .notListening(8081))
        XCTAssertEqual(
            PortMapRules.validate(internal: 5432, listening: listening, mappedPorts: [],
                                  chosenExternal: 28080, takenExternals: []),
            .notOnLoopback(5432))
        XCTAssertEqual(
            PortMapRules.validate(internal: 8080, listening: listening, mappedPorts: [8080],
                                  chosenExternal: 28080, takenExternals: []),
            .alreadyMapped(8080))
        XCTAssertEqual(
            PortMapRules.validate(internal: 8080, listening: listening, mappedPorts: [],
                                  chosenExternal: 80, takenExternals: []),
            .invalidExternal(.belowPrivilegedFloor))
        XCTAssertEqual(
            PortMapRules.validate(internal: 8080, listening: listening, mappedPorts: [],
                                  chosenExternal: 8080, takenExternals: []),
            .invalidExternal(.isInternalPort))
        XCTAssertEqual(
            PortMapRules.validate(internal: 8080, listening: listening, mappedPorts: [],
                                  chosenExternal: 45123, takenExternals: []),
            .invalidExternal(.insideGeneratedRange))
        XCTAssertEqual(
            PortMapRules.validate(internal: 8080, listening: listening, mappedPorts: [],
                                  chosenExternal: 28080, takenExternals: [28080]),
            .externalTakenByMapping(28080))
    }

    func testAWideBindCoversTheLoopbackRule() {
        let wide = [ListeningPort(address: "*", port: 3000, process: "svc")]
        XCTAssertNil(PortMapRules.validate(
            internal: 3000, listening: wide, mappedPorts: [],
            chosenExternal: 28080, takenExternals: []))
    }

    /// The §405 refinement: when the account's worker reports nothing but a
    /// machine-wide probe answers, the verdict upgrades to "held outside this
    /// account" — unless the answering port is one of this product's own
    /// forwarder endpoints, whose answering says nothing about a service.
    func testTheNotListeningRefinement() {
        XCTAssertEqual(
            PortMapRules.notListeningRefinement(probeAnswers: true, portIsAMappingEndpoint: false),
            .heldOutsideAccount)
        XCTAssertEqual(
            PortMapRules.notListeningRefinement(probeAnswers: false, portIsAMappingEndpoint: false),
            .nothingAnywhere,
            "a silent port stays a plain notListening refusal")
        XCTAssertEqual(
            PortMapRules.notListeningRefinement(probeAnswers: true, portIsAMappingEndpoint: true),
            .nothingAnywhere,
            "our own forwarder's endpoint answering is not a service's listener")
        XCTAssertEqual(
            PortMapRules.notListeningRefinement(probeAnswers: false, portIsAMappingEndpoint: true),
            .nothingAnywhere)
    }
}
