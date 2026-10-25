import Foundation

// The shared root (`/Library/Application Support/AgentSpace`) is root-owned,
// and its `Network` configuration directory is created and handed to the main
// user by the helper on every worker install/update (§402). Until a machine
// has run that once, every write the app or the CLI makes into it is refused
// — and that one refusal has a fix, so the surfaces translate it instead of
// showing Cocoa's raw prose. Lived in `PortMap.swift` until the port map was
// removed (§406); the API configuration writes it serves are why it stays.
public enum SharedRootWrite {

    /// Whether a thrown write error is the "not prepared yet" permission
    /// refusal. NSCocoaErrorDomain 513 is what `Data.write` answers with, and
    /// NSPOSIXErrorDomain 13 (EACCES) is what `createDirectory` answers with;
    /// the former usually wraps the latter.
    public static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == 513 { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == 13 { return true }
        if ns.domain == NSCocoaErrorDomain,
           let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, underlying.code == 13 {
            return true
        }
        return false
    }
}
