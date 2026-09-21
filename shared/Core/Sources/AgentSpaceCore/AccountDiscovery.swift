import Foundation

/// A real local macOS account that may be offered for attachment.
public struct LocalAccount: Equatable, Sendable, Identifiable {
    public var username: String
    public var uid: uid_t
    public var displayName: String
    public var homeDirectory: String
    public var isAdministrator: Bool
    /// Directory Service's explicit hidden flag. A username beginning with an
    /// underscore is not enough to classify an account as hidden: macOS can
    /// display a legitimate standard user whose short name was chosen that
    /// way (including accounts created by an older AgentSpace build).
    public var isHidden: Bool

    public var id: String { username }

    public init(
        username: String,
        uid: uid_t,
        displayName: String,
        homeDirectory: String,
        isAdministrator: Bool,
        isHidden: Bool = false
    ) {
        self.username = username
        self.uid = uid
        self.displayName = displayName
        self.homeDirectory = homeDirectory
        self.isAdministrator = isAdministrator
        self.isHidden = isHidden
    }
}

/// Discovers existing standard users. It is read-only: attachment is a
/// separate, explicit operation through the helper.
public enum AccountDiscovery {
    /// The predicates that decide eligibility without asking anything about a
    /// single account. `discover` applies these to every passwd record first and
    /// only then asks Directory Service about the survivors: a Mac carries
    /// hundreds of system records, and probing each one used to mean hundreds of
    /// `/usr/bin/id` processes before the first candidate was known (§300).
    static func passesCheapFilters(
        _ account: LocalAccount,
        currentUsername: String
    ) -> Bool {
        account.uid >= 500
            && account.username != currentUsername
            && !account.isHidden
            && account.homeDirectory.hasPrefix("/Users/")
    }

    public static func candidates(
        from accounts: [LocalAccount],
        currentUsername: String = NSUserName()
    ) -> [LocalAccount] {
        accounts.filter {
            passesCheapFilters($0, currentUsername: currentUsername) && !$0.isAdministrator
        }.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    public static func discover(currentUsername: String = NSUserName()) -> [LocalAccount] {
        discover(currentUsername: currentUsername, administratorProbe: isAdministrator(_:))
    }

    /// Seam for the test that proves the privilege probe is not asked about
    /// records the cheap filters already rejected.
    static func discover(
        currentUsername: String = NSUserName(),
        administratorProbe: (String) -> Bool
    ) -> [LocalAccount] {
        guard let hiddenUsernames = hiddenUsernames() else { return [] }
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
            let account = LocalAccount(
                username: username,
                uid: value.pw_uid,
                displayName: displayName.isEmpty ? username : displayName,
                homeDirectory: home,
                isAdministrator: false,
                isHidden: hiddenUsernames.contains(username))
            if passesCheapFilters(account, currentUsername: currentUsername) {
                found.append(account)
            }
        }
        let resolved = found.map { account in
            var probed = account
            probed.isAdministrator = administratorProbe(account.username)
            return probed
        }
        return candidates(from: resolved, currentUsername: currentUsername)
    }

    /// Resolve one user without walking every directory-service record. This is
    /// the CLI's fast path for `attach <username>` and keeps a typo from waiting
    /// on network-backed account enumeration.
    public static func find(
        username requested: String,
        currentUsername: String = NSUserName()
    ) -> LocalAccount? {
        guard !requested.isEmpty else { return nil }
        guard let hiddenUsernames = hiddenUsernames() else { return nil }
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
            isAdministrator: isAdministrator(username),
            isHidden: hiddenUsernames.contains(username))
        return candidates(from: [account], currentUsername: currentUsername).first
    }

    private static func hiddenUsernames() -> Set<String>? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-list", "/Users", "IsHidden"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            var hidden = Set<String>()
            for line in text.split(whereSeparator: { $0.isNewline }) {
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                guard fields.count >= 2 else { continue }
                let value = fields[1]
                if value == "1" || value.caseInsensitiveCompare("yes") == .orderedSame
                    || value.caseInsensitiveCompare("true") == .orderedSame {
                    hidden.insert(String(fields[0]))
                }
            }
            return hidden
        } catch {
            // Discovery is fail-closed when Directory Service cannot answer:
            // without the explicit hidden set we cannot safely distinguish a
            // system account from a displayable standard user.
            return nil
        }
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
