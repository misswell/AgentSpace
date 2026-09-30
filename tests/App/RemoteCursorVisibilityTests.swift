import XCTest
import AppKit
import AgentSpaceCore
@testable import AgentSpaceApp

final class RemoteCursorVisibilityTests: XCTestCase {
    @MainActor
    func testHiddenModeSuppressesRealLayerAcrossPacketsPredictionAndLayout() {
        let layer = RemoteCursorOverlayLayer()
        layer.mapping = PreviewMapping(imageWidth: 100, imageHeight: 100,
                                       displayWidth: 100, displayHeight: 100,
                                       viewWidth: 100, viewHeight: 100)
        let proxy = RemoteCursorOverlayProxy()
        proxy.attach(layer)
        let cursor = InputClient.CursorPresentation(x: 30, y: 30, shapeID: 1,
            hotSpotX: 0, hotSpotY: 0, size: CGSize(width: 2, height: 2),
            image: Data(repeating: 255, count: 16))
        proxy.hidesCursor = true
        proxy.apply(cursor)
        layer.layoutSublayers()
        XCTAssertFalse(layer.isHidden, "Control: a visible mode draws the sprite")
        proxy.hidesCursor = false
        proxy.isDrawingCursor = false
        XCTAssertTrue(layer.isHidden, "Mode changes hide the layer immediately")
        layer.layoutSublayers()
        XCTAssertTrue(layer.isHidden, "Switching modes must clear an already visible cursor")
        proxy.apply(cursor)
        layer.predict(displayPoint: CGPoint(x: 40, y: 40))
        layer.layoutSublayers()
        XCTAssertTrue(layer.isHidden, "A packet or predicted move must not resurrect the hidden sprite")
        proxy.hidesCursor = true
        proxy.apply(cursor)
        layer.layoutSublayers()
        XCTAssertFalse(layer.isHidden, "Returning to a visible mode restores the sprite")
        proxy.detach()
        layer.layoutSublayers()
        XCTAssertTrue(layer.isHidden, "Disconnect clears the sprite")
    }
}
