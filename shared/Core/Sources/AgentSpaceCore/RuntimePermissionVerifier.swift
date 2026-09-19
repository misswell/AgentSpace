import Foundation

/// Fail-closed checks for the per-agent runtime boundary.
///
/// The helper creates this directory as mode 0700 owned by the agent and adds
/// inheritable ACL entries for the main and agent users. The worker calls this
/// before reading a token or binding a socket, so a partially applied helper
/// operation cannot quietly start with a different access boundary.
public enum RuntimePermissionVerifier {
    /// Injectable because unit tests must not mutate the test runner's ACLs.
    public static var aclReader: (String) -> String? = { path in
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ls")
        process.arguments = ["-lde", path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        } catch {
            return nil
        }
    }

    public static func verifyDirectory(
        _ path: String,
        expectedOwner: uid_t,
        mainUser: String,
        agentUser: String
    ) -> AgentSpaceError? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: path)
        } catch {
            return AgentSpaceError(
                code: .helperRejected,
                message: "the runtime directory is missing or unreadable: \(path)")
        }

        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            return AgentSpaceError(code: .helperRejected, message: "the runtime path is not a directory: \(path)")
        }
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        guard owner == expectedOwner else {
            return AgentSpaceError(
                code: .helperRejected,
                message: "the runtime directory owner is \(owner.map(String.init) ?? "unknown"), expected uid \(expectedOwner)")
        }
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        guard permissions & 0o077 == 0 else {
            return AgentSpaceError(
                code: .helperRejected,
                message: "the runtime directory mode is too broad: \(String(permissions, radix: 8))")
        }

        guard let acl = aclReader(path) else {
            return AgentSpaceError(code: .helperRejected, message: "the runtime directory ACL could not be read")
        }
        let entries = acl.split(whereSeparator: \.isNewline).map(String.init)
        for user in [mainUser, agentUser] {
            guard let entry = entries.first(where: { $0.contains("user:\(user) ") }),
                  entry.contains("file_inherit"),
                  entry.contains("directory_inherit") else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "the runtime directory ACL does not grant inherited access to \(user)")
            }
        }
        let allowedUsers = Set([mainUser, agentUser])
        for entry in entries where entry.contains(" allow ") {
            guard let marker = entry.range(of: "user:") else { continue }
            let remainder = entry[marker.upperBound...]
            guard let end = remainder.firstIndex(where: { $0 == " " || $0 == ":" }) else { continue }
            let principal = String(remainder[..<end])
            guard allowedUsers.contains(principal) else {
                return AgentSpaceError(
                    code: .helperRejected,
                    message: "the runtime directory ACL grants access to unexpected user \(principal)")
            }
        }
        return nil
    }
}
