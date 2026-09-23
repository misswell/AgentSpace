import XCTest
@testable import AgentSpaceCore

/// How much of a source's own detail a viewer asks the worker to capture.
///
/// The property under test is that no mode ever asks for more pixels than the
/// source has. That is what §320 row 837 left open — 「原生」 on a Retina panel
/// asked a 1920-wide desktop for 2280×1283 pixels, the worker granted the
/// enlargement, and from there the H.264 encoder spent bits describing
/// interpolation — and the test that closes it is written against the *measured*
/// viewer case rather than a hypothetical one.
final class DisplayQualityTests: XCTestCase {

    /// The desktop every number here is measured against (`docs/validation.md`
    /// §320: an agent session reporting a 1920×1080 display at scale 1).
    private let source = (width: 1920, height: 1080)

    /// The viewer described in §320 row 837: a 1140×642 point window on a 2x
    /// panel, i.e. 2280×1283 device pixels, which is more than the desktop has.
    func testTheMeasuredRetinaViewerCaseIsNoLongerAnUpscale() {
        let ceiling = DisplayQuality.native.captureSize(sourceWidth: source.width, sourceHeight: source.height)
        // What `RemoteSurfaceNSView.layout()` asks: the smaller of the window's
        // own device pixels and the source's.
        let asked = (width: min(2280, ceiling.width), height: min(1283, ceiling.height))
        XCTAssertEqual(asked.width, 1920)
        XCTAssertEqual(asked.height, 1080)

        // And what the worker builds for that request — the same call the capture
        // makes — is the desktop's own frame, with no interpolation anywhere.
        let buffer = CaptureSizing.resolved(naturalWidth: source.width, naturalHeight: source.height,
                                           targetWidth: asked.width, targetHeight: asked.height)
        XCTAssertEqual(buffer.width, 1920)
        XCTAssertEqual(buffer.height, 1080)
    }

    func testTheDefaultIsTheSourcesOwnPixels() {
        XCTAssertEqual(DisplayQuality.default, .native)
    }

    func testNativeIsTheSourceExactly() {
        XCTAssertEqual(DisplayQuality.native.captureSize(sourceWidth: 3024, sourceHeight: 1964).width, 3024)
        XCTAssertEqual(DisplayQuality.native.captureSize(sourceWidth: 3024, sourceHeight: 1964).height, 1964)
    }

    /// A percentage is per axis, which is what someone choosing 75 % means — and
    /// what the old width list could not express at all.
    func testBalancedIsThreeQuartersOfEachAxis() {
        let small = DisplayQuality.balanced.captureSize(sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertEqual(small.width, 1440)
        XCTAssertEqual(small.height, 810)
        let large = DisplayQuality.balanced.captureSize(sourceWidth: 3024, sourceHeight: 1964)
        XCTAssertEqual(large.width, 2268)
        XCTAssertEqual(large.height, 1473, "1964 × 0.75 is 1473 exactly")
    }

    func testPerformanceIsBoundedByItsOwnWidthAndKeepsTheShape() {
        let size = DisplayQuality.performance.captureSize(sourceWidth: 3840, sourceHeight: 2160)
        XCTAssertEqual(size.width, DisplayQuality.performanceWidthInPixels)
        XCTAssertEqual(size.height, 720, "the aspect is the source's, not 16:9 by luck")
    }

    /// The ceiling every mode shares: a source smaller than the mode's own number
    /// keeps its pixels. Without this a 640-wide desktop would be blown up to
    /// 1280 by "performance", which is the defect this whole enum exists against.
    func testNoModeEnlargesASourceSmallerThanItsOwnNumber() {
        for quality in DisplayQuality.allCases {
            let size = quality.captureSize(sourceWidth: 640, sourceHeight: 480)
            XCTAssertLessThanOrEqual(size.width, 640, "\(quality) enlarged a 640-wide source")
            XCTAssertLessThanOrEqual(size.height, 480, "\(quality) enlarged a 480-tall source")
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
        }
    }

    func testADegenerateSourceStillProducesAUsableSize() {
        for quality in DisplayQuality.allCases {
            let size = quality.captureSize(sourceWidth: 0, sourceHeight: 0)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
        }
    }

    func testTheStoredFormRoundTrips() {
        for quality in DisplayQuality.allCases {
            XCTAssertEqual(DisplayQuality.parse(quality.rawValue), quality)
        }
        XCTAssertNil(DisplayQuality.parse(nil))
        XCTAssertNil(DisplayQuality.parse("retina"), "the old word for the mode is not a stored spelling")
    }

    func testAStoredWidthBecomesTheModeItMeant() {
        XCTAssertEqual(DisplayQuality.migrated(fromWidthLimit: nil), .native)
        XCTAssertEqual(DisplayQuality.migrated(fromWidthLimit: 0), .native, "0 meant the source's own pixels")
        XCTAssertEqual(DisplayQuality.migrated(fromWidthLimit: 960), .performance)
        XCTAssertEqual(DisplayQuality.migrated(fromWidthLimit: 1280), .performance)
        XCTAssertEqual(DisplayQuality.migrated(fromWidthLimit: 1600), .balanced)
        XCTAssertEqual(DisplayQuality.migrated(fromWidthLimit: 2560), .balanced)
    }

    /// The migration is a one-time translation, not a preference that overwrites
    /// itself on every launch: a machine that has since chosen a mode keeps it.
    func testTheMigrationRunsOnceAndKeepsAChoiceMadeSince() throws {
        let name = "agentspace.DisplayQualityTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defaults.set(1600, forKey: DisplayQuality.legacyWidthKey)

        DisplayQuality.migrateStoredPreference(defaults)
        XCTAssertEqual(defaults.string(forKey: DisplayQuality.storageKey), DisplayQuality.balanced.rawValue)

        defaults.set(DisplayQuality.performance.rawValue, forKey: DisplayQuality.storageKey)
        DisplayQuality.migrateStoredPreference(defaults)
        XCTAssertEqual(defaults.string(forKey: DisplayQuality.storageKey), DisplayQuality.performance.rawValue,
                       "a second launch must not translate over the choice")
    }

    /// Nothing to translate: a machine that never moved either control is left
    /// empty, so the enum's own default is what both views read.
    func testTheMigrationIsANoOpWithNoStoredPreference() throws {
        let name = "agentspace.DisplayQualityTests.empty"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        DisplayQuality.migrateStoredPreference(defaults)
        XCTAssertNil(defaults.string(forKey: DisplayQuality.storageKey))
    }
}
