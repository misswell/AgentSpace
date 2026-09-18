import Foundation

/// Which running applications belong in the `apps` list (§22).
///
/// The plan requires the list to include menu-bar apps — accessory /
/// `LSUIElement` processes — not just regular windowed apps. A launch
/// of such an app that then vanished from the list would look like a
/// failed launch to every caller, so the rule lives here as a pure
/// predicate the worker can be tested against.
public enum AppVisibility {
    /// An app is listed when AppKit calls it regular or accessory, or
    /// when the window server sees an on-screen window for it even if
    /// AppKit calls the policy `prohibited`. Unknown policies are
    /// visible only through a window — the same fail-open-by-evidence
    /// rule the rest of the list follows: the window server's word
    /// outranks AppKit's classification.
    public static func isVisible(policy: String, pid: pid_t, windowPids: Set<pid_t>) -> Bool {
        policy == "regular" || policy == "accessory" || windowPids.contains(pid)
    }
}
