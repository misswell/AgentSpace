import Foundation

/// Resources opened by the Worker with NSWorkspace, never by a controller-side shell.
public enum SessionResource {
    public static let maxTextBytes = 1_048_576

    public static func url(for reference: String) throws -> URL {
        guard !reference.isEmpty, !reference.contains("\0"),
              !reference.contains(where: { $0.isNewline }) else {
            throw AgentSpaceError(code: .badRequest, message: "resource must be a non-empty URL or absolute file path")
        }
        if reference.hasPrefix("/") { return URL(fileURLWithPath: reference) }
        guard let url = URL(string: reference), let scheme = url.scheme?.lowercased(),
              ["http", "https", "file", "x-apple.systempreferences"].contains(scheme) else {
            throw AgentSpaceError(code: .badRequest, message: "supported resource schemes are http, https, file and x-apple.systempreferences; file paths must be absolute")
        }
        if scheme == "http" || scheme == "https" {
            guard let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                throw AgentSpaceError(code: .badRequest, message: "web URLs require a host and must not include credentials")
            }
        }
        if scheme == "file" {
            guard (url.host == nil || url.host == "" || url.host == "localhost"),
                  url.path.hasPrefix("/"), !url.path.isEmpty else {
                throw AgentSpaceError(code: .badRequest, message: "file URLs must identify an absolute local path")
            }
        }
        return url
    }

    public static func validateText(_ text: String) throws {
        guard text.utf8.count <= maxTextBytes else {
            throw AgentSpaceError(code: .badRequest, message: "text exceeds the 1 MiB limit")
        }
    }
}
