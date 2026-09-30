import Foundation

/// The dashboard's automatic status interval — the policy behind the Settings
/// slider labelled "Status refresh". The wiring defect this closes, and the
/// measured red/green, are recorded as validation §367: the slider shipped in
/// the first GUI commit and nothing consumed its value.
///
/// This lives in Core, not the GUI, for the same reason `DisplayQuality` does:
/// the band is a product-wide rule (plan §53 — "never poll `status` faster than
/// every 2–5 s"), the GUI's own tests cannot reach `AppModel`, and a second
/// copy of the clamp in the view would let the slider and the loop drift.
///
/// The slider in Settings offers 2–10 s; this resolver is what the polling
/// loop actually waits on. It re-reads the stored value every tick, so moving
/// the slider applies at the next tick without a restart. Values outside the
/// slider can only arrive through `defaults write`, and the clamp keeps even
/// those inside the plan: never faster than 2 s, never an absurd wait.
public enum StatusRefresh: Sendable {

    /// The `UserDefaults` key the slider writes. One key, one meaning: the
    /// seconds between automatic dashboard status ticks.
    public static let storageKey = "statusRefreshSeconds"

    /// The slider's default — and the loop's, because an untouched slider
    /// writes nothing. Sits inside plan §53's 2–5 s window.
    public static let defaultValue: TimeInterval = 3

    /// Plan §53's floor. The slider's own minimum is the same 2 s, so no AX
    /// poke, script or accident can poll faster through the UI; the clamp here
    /// closes the `defaults write` hole the slider cannot.
    public static let floor: TimeInterval = 2

    /// A sanity ceiling for raw `defaults write` values, so a typo cannot turn
    /// one tick into a day of silence. The slider itself stops at 10.
    public static let ceiling: TimeInterval = 3600

    /// Resolve a stored value to the interval the loop waits.
    ///
    /// An unset, zero or negative value means "the slider was never moved" and
    /// resolves to `defaultValue`; a positive value is honored, clamped to the
    /// plan's floor and the sanity ceiling.
    public static func interval(stored: Double) -> TimeInterval {
        guard stored > 0, stored.isFinite else { return defaultValue }
        return min(max(stored, floor), ceiling)
    }

    /// Read the interval from a defaults store. Injectable so the tests can
    /// use a scratch `UserDefaults` suite instead of the real one.
    public static func interval(from defaults: UserDefaults) -> TimeInterval {
        interval(stored: defaults.double(forKey: storageKey))
    }
}
