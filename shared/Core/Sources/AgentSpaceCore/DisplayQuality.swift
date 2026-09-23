import Foundation

/// How much of a source's own pixel detail a viewer asks the worker to capture.
///
/// A capture is a copy, and this is the size of the copy. Three things about it
/// are decisions rather than numbers.
///
/// 1. **Native is a ceiling, not a multiplier.** Every mode is expressed against
///    the *source's* pixel size, and no mode asks for more pixels than the source
///    has: a buffer larger than its subject is interpolation — paid for in H.264
///    bits and in shared memory, and visible to nobody, because the renderer fits
///    whatever arrives into the window either way. A viewer that also knows how
///    many device pixels its own window has (`RemoteSurfaceNSView`) asks for the
///    smaller of the two, so a small window asks for less and the picture is never
///    an upscale.
///
///    The alternative is what `0.1.29` shipped: 「原生」 on a Retina panel asked a
///    1920-wide desktop for 2280×1283 (`docs/validation.md` §320 row 837), which
///    ScreenCaptureKit dutifully scaled *up*, and the encoder then spent bits
///    describing an enlargement of detail that was never captured.
/// 2. **A percentage is per axis.** 75 % of 1920×1080 is 1440×810 — 56 % of the
///    pixels — because that is what someone choosing 75 % means by it, the same
///    convention a display's own scaled resolution modes use.
/// 3. **The raw value is the stored form.** It is what a preference or a wire
///    field carries, so it is a stable spelling and never a display string; the
///    three names a person reads live in the GUI's localization tables.
public enum DisplayQuality: String, CaseIterable, Sendable {
    /// The source's own pixels. The default, and the sharpest a capture can be.
    case native
    /// 75 % per axis: the picture a link cannot quite afford to carry at native.
    case balanced
    /// A bounded width, for a viewer that is being carried over something slow.
    case performance

    /// What a viewer uses when nobody chose.
    public static let `default`: DisplayQuality = .native

    /// The pixel width `performance` holds a wider source to.
    public static let performanceWidthInPixels = 1280

    /// The per-axis fraction `balanced` means.
    public static let balancedScale = 0.75

    public static func parse(_ raw: String?) -> DisplayQuality? {
        guard let raw else { return nil }
        return DisplayQuality(rawValue: raw.lowercased())
    }

    /// The most pixels this mode wants from a source of this size.
    ///
    /// Never larger than the source in either axis: that is the ceiling the whole
    /// enum is built on, and it holds for a source smaller than any mode's own
    /// number too — a 640-wide desktop keeps its 640 pixels under every mode.
    public func captureSize(sourceWidth: Int, sourceHeight: Int) -> (width: Int, height: Int) {
        let width = max(1, sourceWidth), height = max(1, sourceHeight)
        switch self {
        case .native:
            return (width, height)
        case .balanced:
            return (Self.scaled(width, by: Self.balancedScale), Self.scaled(height, by: Self.balancedScale))
        case .performance:
            guard width > Self.performanceWidthInPixels else { return (width, height) }
            return (Self.performanceWidthInPixels,
                    max(1, Int((Double(Self.performanceWidthInPixels) * Double(height) / Double(width)).rounded())))
        }
    }

    private static func scaled(_ value: Int, by scale: Double) -> Int {
        max(1, Int((Double(value) * scale).rounded()))
    }

    /// What a preference stored as a pixel width meant, now that the choice is a
    /// mode.
    ///
    /// The old key held a width limit, where `0` meant the source's own pixels.
    /// It is read once, at launch, and written as the mode closest to what it
    /// bought: `0` is `native`, a limit at or below `performance`'s own width is
    /// `performance`, and anything larger was a request for most of the source's
    /// detail, which is `balanced`. A stored `1920` on a 1920-wide source
    /// therefore becomes `balanced` (1440) rather than `native` — one step
    /// softer than it was, because the mode list has no fourth value and
    /// rounding a preference *up* to more pixels than it asked for is the
    /// direction that costs bandwidth without being asked.
    public static func migrated(fromWidthLimit width: Int?) -> DisplayQuality {
        guard let width, width > 0 else { return .native }
        return width <= performanceWidthInPixels ? .performance : .balanced
    }

    // MARK: - Where the choice is kept

    /// The preference this choice is stored under.
    ///
    /// A key of its own rather than the old width limit, because a mode is not a
    /// width. It lives here rather than in the GUI because two views read it and
    /// only one of them may be instantiated at a time: a key spelled in two
    /// places is a key that eventually disagrees with itself, which is exactly
    /// what the old `previewMaxWidth` did — the viewer's picker defaulted to the
    /// source's own pixels while Settings' defaulted to 1600 px.
    public static let storageKey = "displayQuality"

    /// The width limit older builds stored. Read once, never written.
    public static let legacyWidthKey = "previewMaxWidth"

    /// Turn an existing width preference into the mode it meant, once.
    ///
    /// Called at launch. A no-op unless the old key is set and the new one is
    /// not, so a machine that never touched either control keeps this enum's own
    /// default and this can never overwrite a choice made in the mode picker.
    public static func migrateStoredPreference(_ defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: storageKey) == nil else { return }
        guard defaults.object(forKey: legacyWidthKey) != nil else { return }
        defaults.set(migrated(fromWidthLimit: defaults.integer(forKey: legacyWidthKey)).rawValue,
                     forKey: storageKey)
    }
}
