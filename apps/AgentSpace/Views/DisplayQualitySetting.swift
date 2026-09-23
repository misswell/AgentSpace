import SwiftUI
import AgentSpaceCore

/// The picker both surfaces render for the display-quality choice.
///
/// The choice itself — the modes, the key it is stored under, and the one-time
/// translation of the width limit older builds stored — lives in Core, because
/// two views read it and only one of them may be on screen at a time. What lives
/// here is only how it reads: one option per mode, in the language the rest of
/// the window is in.
struct DisplayQualityPicker: View {
    /// Applied to the `Picker` itself, never to this struct.
    ///
    /// `.accessibilityIdentifier` on a composed view lands on whatever element
    /// SwiftUI decides to wrap it in, and the gate looks the control up as a
    /// `pop up button` — an identifier on the wrapper is found only when the two
    /// happen to be the same element, which is a coin flip across runs rather
    /// than a property of the code (`docs/validation.md` §323 row 860).
    var identifier: String
    @AppStorage(DisplayQuality.storageKey) private var stored = DisplayQuality.default.rawValue

    var body: some View {
        Picker("Display quality", selection: $stored) {
            ForEach(DisplayQuality.allCases, id: \.rawValue) { quality in
                Text(quality.title).tag(quality.rawValue)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(identifier)
    }
}

extension DisplayQuality {
    /// What a person reads. These three strings are localization keys, so each
    /// must exist in both tables — `LocalizationTests` is what makes that a fact
    /// rather than a habit.
    var title: String {
        switch self {
        case .native: return NSLocalizedString("Native Retina", comment: "")
        case .balanced: return NSLocalizedString("Balanced", comment: "")
        case .performance: return NSLocalizedString("Performance", comment: "")
        }
    }

    /// What the mode means, for the caption under the picker in Settings. The
    /// number is the promise, and each one is stated as what it is a fraction of.
    var explanation: String {
        switch self {
        case .native:
            return NSLocalizedString("The agent desktop's own pixels. Sharpest, and the most data.", comment: "")
        case .balanced:
            return NSLocalizedString("Three quarters of the agent desktop's pixels, in each direction.", comment: "")
        case .performance:
            return NSLocalizedString("At most 1280 pixels wide. For a slow link.", comment: "")
        }
    }
}
