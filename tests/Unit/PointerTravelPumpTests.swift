import XCTest
import AgentSpaceCore

final class PointerTravelPumpTests: XCTestCase {
    @MainActor
    func testFinalHoverArrivesWithoutAnotherMouseEventOrFrame() async throws {
        var delivered: [Int] = []
        let pump = PointerTravelPump<Int>(minimumInterval: 0.03) { delivered.append($0) }
        pump.offer(0)
        for point in 1...9 { pump.offer(point) }
        XCTAssertEqual(delivered, [0])
        let deadline = Date().addingTimeInterval(5)
        while delivered.count < 2 && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(delivered, [0, 9], "The final point must not wait for another mouse event")
    }

    @MainActor
    func testResetCancelsPendingTravel() async throws {
        var delivered: [Int] = []
        let pump = PointerTravelPump<Int>(minimumInterval: 0.03) { delivered.append($0) }
        pump.offer(0); pump.offer(1); pump.reset()
        pump.offer(2); pump.offer(3)
        let deadline = Date().addingTimeInterval(5)
        while delivered.count < 3 && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(delivered, [0, 2, 3], "Reset must cancel the old pending point while new travel still works")
    }
}
