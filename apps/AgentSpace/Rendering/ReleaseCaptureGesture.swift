import AppKit

/// The two escape gestures that hand the pointer back to the person.
///
/// Absolute pointer capture does not need one in the ordinary case: moving the
/// mouse off the picture is what releases it, and that is the whole point of the
/// mode. The gesture exists for the case where the pointer *cannot* leave — a
/// captured surface inside a full-screen window, or a person who wants to reach a
/// local window control without closing the desktop.
///
/// Two spellings, because the first is what virtualization products have trained
/// hands to use and the second is unambiguous on a keyboard where Control-Option
/// is already an input source switch on some layouts.
enum ReleaseCaptureGesture {
    static func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Control + Option.
        if flags == [.control, .option] { return true }
        // Control + Command + G.
        if flags == [.control, .command], event.charactersIgnoringModifiers?.lowercased() == "g" { return true }
        return false
    }
}
