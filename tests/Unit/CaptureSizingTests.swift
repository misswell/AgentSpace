import XCTest
@testable import AgentSpaceCore

/// What size a capture buffer is built at.
///
/// The property under test is the one both ends of a frame stream depend on: the
/// buffer holds *exactly* its subject. A viewer is told the buffer's size and
/// nothing else, so a buffer that carries its subject plus black pillars is a
/// picture the viewer cannot measure — which is how a click at the left edge of
/// the desktop landed 236 points into it (§320).
///
/// Pure geometry, so it is tested here rather than in front of a WindowServer.
final class CaptureSizingTests: XCTestCase {

    /// A 1920×1080 desktop, the one the real machine under `docs/validation.md` runs.
    private let desktop = (width: 1920, height: 1080)

    func testABoxShapedLikeTheSubjectIsHonouredToThePixel() {
        let downscaled = CaptureSizing.resolved(naturalWidth: 1920, naturalHeight: 1080,
                                               targetWidth: 1280, targetHeight: 720)
        XCTAssertEqual(downscaled.width, 1280)
        XCTAssertEqual(downscaled.height, 720)

        let upscaled = CaptureSizing.resolved(naturalWidth: 1920, naturalHeight: 1080,
                                              targetWidth: 3840, targetHeight: 2160)
        XCTAssertEqual(upscaled.width, 3840)
        XCTAssertEqual(upscaled.height, 2160, "a 2x window asking for 2x pixels must not lose any to rounding")
    }

    /// The measured viewer case: a 1512×641 point window on a 2x panel, capped at
    /// 1280 px wide, asks for 1280×543. ScreenCaptureKit answered that with a
    /// 965×543 desktop centred in 1280×543 of buffer.
    func testAWideBoxGivesUpTheWidthThatWouldHaveBeenPillars() {
        let fitted = CaptureSizing.resolved(naturalWidth: desktop.width, naturalHeight: desktop.height,
                                            targetWidth: 1280, targetHeight: 543)
        XCTAssertEqual(fitted.width, 965)
        XCTAssertEqual(fitted.height, 543)
        assertSameShapeAsSubject(fitted, "a wide box must not come back wide")
    }

    /// The same defect on its other side: a box taller than the subject loses
    /// height, because a desktop cannot be made square by asking for a square.
    func testATallBoxGivesUpTheHeightThatWouldHaveBeenPillars() {
        let fitted = CaptureSizing.resolved(naturalWidth: desktop.width, naturalHeight: desktop.height,
                                            targetWidth: 1600, targetHeight: 1800)
        XCTAssertEqual(fitted.width, 1600)
        XCTAssertEqual(fitted.height, 900)
        assertSameShapeAsSubject(fitted, "a tall box must not come back tall")
    }

    /// A Fusion proxy resizes freely and its subject is a remote window, so the
    /// subject's shape is whatever that window's is.
    func testAWindowSubjectKeepsItsOwnShapeInAProxyBox() {
        let fitted = CaptureSizing.resolved(naturalWidth: 1200, naturalHeight: 800,
                                            targetWidth: 900, targetHeight: 900)
        XCTAssertEqual(fitted.width, 900)
        XCTAssertEqual(fitted.height, 600)
    }

    /// A one-dimensional request is what `screenshot --max-width` and a viewer's
    /// width cap mean: scale the subject by that dimension. Those already produced
    /// a subject-shaped buffer, so this fix must not move them.
    func testOneDimensionalRequestsStillScaleByTheDimensionGiven() {
        let byWidth = CaptureSizing.resolved(naturalWidth: 1920, naturalHeight: 1080,
                                             targetWidth: 1280, targetHeight: 0)
        XCTAssertEqual(byWidth.width, 1280)
        XCTAssertEqual(byWidth.height, 720)
        let byHeight = CaptureSizing.resolved(naturalWidth: 1920, naturalHeight: 1080,
                                              targetWidth: 0, targetHeight: 540)
        XCTAssertEqual(byHeight.width, 960)
        XCTAssertEqual(byHeight.height, 540)
    }

    func testNoRequestIsTheSubjectsOwnSize() {
        let natural = CaptureSizing.resolved(naturalWidth: 1920, naturalHeight: 1080,
                                             targetWidth: 0, targetHeight: 0)
        XCTAssertEqual(natural.width, 1920)
        XCTAssertEqual(natural.height, 1080)
    }

    /// The buffer is never larger than the box in either dimension — the request is
    /// a budget, and "fit" is what keeps a wide window from asking for more pixels
    /// than it can show.
    func testTheBufferNeverExceedsTheBoxItWasGiven() {
        for box in [(1280, 543), (1600, 1800), (3024, 1283), (400, 400), (2560, 1440)] {
            let resolved = CaptureSizing.resolved(naturalWidth: desktop.width, naturalHeight: desktop.height,
                                                  targetWidth: box.0, targetHeight: box.1)
            XCTAssertLessThanOrEqual(resolved.width, box.0, "\(box) came back wider than it asked")
            XCTAssertLessThanOrEqual(resolved.height, box.1, "\(box) came back taller than it asked")
            XCTAssertGreaterThan(resolved.width, 0)
            XCTAssertGreaterThan(resolved.height, 0)
            assertSameShapeAsSubject(resolved, "box \(box)")
        }
    }

    /// 「原生」 on a Retina panel asks for the view's own pixel size, which for a
    /// 1920×1080 desktop in a 1140×642 point view is 2280×1283 — an upscale in both
    /// dimensions, and the box is 1 px out of the desktop's exact shape. This fix is
    /// about shape, not about resolution: the upscale is granted whole (the 2x pixel
    /// question is §320 row 837's own open task), and the odd pixel of the request is
    /// absorbed by rounding rather than by a pillar.
    func testANativeRetinaRequestKeepsTheUpscaleAndShedsThePillar() {
        let native = CaptureSizing.resolved(naturalWidth: desktop.width, naturalHeight: desktop.height,
                                            targetWidth: 2280, targetHeight: 1283)
        XCTAssertEqual(native.width, 2280, "a request wider than the desktop is still an upscale")
        // 1080 × (2280 ÷ 1920) is exactly 1282.5, and Swift's `rounded()` breaks a
        // tie away from zero. Measured, not assumed: the other rule would ship a
        // buffer one pixel short of the box and nobody downstream would notice.
        XCTAssertEqual(native.height, 1283)
        assertSameShapeAsSubject(native, "the native request")
    }

    /// The consequence the whole choice exists for, measured the way the viewer
    /// measures it: a click at the left edge of the *picture* is a click at the
    /// left edge of the *desktop*.
    ///
    /// Both mappings are handed the same 1512×641 point view and the same click at
    /// x = 187 — the point the desktop's own left edge appears at in the viewer.
    /// With the fitted buffer that is x = 0 on the desktop. With the 1280×543 buffer
    /// the viewer used to get, the picture's edge sits inside a pillar the mapping
    /// cannot see, and the same click is x = 236.
    func testThePicturesOwnEdgeIsWhereAClickLands() {
        let fitted = CaptureSizing.resolved(naturalWidth: 1920, naturalHeight: 1080,
                                            targetWidth: 1280, targetHeight: 543)
        let mapping = PreviewMapping(imageWidth: fitted.width, imageHeight: fitted.height,
                                     displayWidth: 1920, displayHeight: 1080,
                                     viewWidth: 1512, viewHeight: 641)
        let point = mapping.displayPoint(viewX: 187, viewY: 320)
        XCTAssertNotNil(point, "the picture's left edge is inside the fitted rect")
        XCTAssertEqual(point?.x ?? -1, 0, accuracy: 1,
                       "a click on the left edge of the desktop's picture is the desktop's left edge")

        let pillared = PreviewMapping(imageWidth: 1280, imageHeight: 543,
                                      displayWidth: 1920, displayHeight: 1080,
                                      viewWidth: 1512, viewHeight: 641)
        XCTAssertGreaterThan(pillared.displayPoint(viewX: 187, viewY: 320)?.x ?? 0, 200,
                             "the pillar buffer is what put the click 236 points away; if this stops "
                             + "being true the defect this guards is gone by some other route")
    }

    /// A buffer is subject-shaped when its own aspect is the subject's to within
    /// half a pixel — the rounding floor, and far tighter than any pillar.
    private func assertSameShapeAsSubject(_ size: (width: Int, height: Int), _ detail: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let subjectAspect = Double(desktop.width) / Double(desktop.height)
        XCTAssertLessThan(abs(Double(size.width) / Double(size.height) - subjectAspect), 0.005,
                          "\(detail): \(size.width)×\(size.height) is not 1920×1080's shape",
                          file: file, line: line)
    }
}
