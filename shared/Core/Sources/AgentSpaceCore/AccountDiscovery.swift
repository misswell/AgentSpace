import Foundation

/// A real local macOS account that may be offered for attachment.
public struct LocalAccount: Equatable, Sendable, Identifiable {
    public var username: String
    public var uid: uid_t
    public var displayName: String
    public var homeDirectory: String
    public var isAdministrator: Bool

    public var id: String { username }

    public init(
        username: String,
        uid: uid_t,
        displayName: String,
        homeDirectory: String,
        isAdministrator: Bool
    ) {
        self.username = username
        self.uid = uid
        self.displayName = displayName
        self.homeDirectory = homeDirectory
        self.isAdministrator = isAdministrator
    }
}

/// Discovers existing standard users. It is read-only: attachment is a
/// separate, explicit operation through the helper.
public enum AccountDiscovery {
    public static func candidates(
        from accounts: [LocalAccount],
        currentUsername: String = NSUserName()
    ) -> [LocalAccount] {
        accounts.filter {
            $0.uid >= 500
                && $0.username != currentUsername
                && !$0.username.hasPrefix("_")
                && !$0.isAdministrator
                && $0.homeDirectory.hasPrefix("/Users/")
        }.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    public static func discover(currentUsername: String = NSUserName()) -> [LocalAccount] {
        var found: [LocalAccount] = []
        setpwent()
        defer { endpwent() }
        while let entry = getpwent() {
            let value = entry.pointee
            guard let namePointer = value.pw_name,
                  let homePointer = value.pw_dir else { continue }
            let username = String(cString: namePointer)
            let home = String(cString: homePointer)
            let displayName: String
            if let gecos = value.pw_gecos {
                displayName = String(cString: gecos).split(separator: ",").first.map(String.init) ?? username
            } else {
                displayName = username
            }
            found.append(LocalAccount(
                username: username,
                uid: value.pw_uid,
                displayName: displayName.isEmpty ? username : displayName,
                homeDirectory: home,
                isAdministrator: isAdministrator(username)))
        }
        return candidates(from: found, currentUsername: currentUsername)
    }

    /// Resolve one user without walking every directory-service record. This is
    /// the CLI's fast path for `attach <username>` and keeps a typo from waiting
    /// on network-backed account enumeration.
    public static func find(
        username requested: String,
        currentUsername: String = NSUserName()
    ) -> LocalAccount? {
        guard !requested.isEmpty else { return nil }
        guard let entry = getpwnam(requested)?.pointee,
              let namePointer = entry.pw_name,
              let homePointer = entry.pw_dir else { return nil }
        let username = String(cString: namePointer)
        let home = String(cString: homePointer)
        let displayName: String
        if let gecos = entry.pw_gecos {
            displayName = String(cString: gecos).split(separator: ",").first.map(String.init) ?? username
        } else {
            displayName = username
        }
        let account = LocalAccount(
            username: username,
            uid: entry.pw_uid,
            displayName: displayName.isEmpty ? username : displayName,
            homeDirectory: home,
            isAdministrator: isAdministrator(username))
        return candidates(from: [account], currentUsername: currentUsername).first
    }

    private static func isAdministrator(_ username: String) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/id")
        process.arguments = ["-Gn", username]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return true }
            let groups = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(whereSeparator: { $0.isWhitespace })
            return groups.contains("admin")
        } catch {
            // Discovery is fail-closed: an account whose privilege level cannot
            // be established is not offered as an agent target.
            return true
        }
    }
}
