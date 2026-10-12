import Foundation
import AppKit
import AgentSpaceCore

extension Operations {
    func openResource(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("open a resource")
        guard let reference = params["resource"]?.stringValue else {
            throw AgentSpaceError(code: .badRequest, message: "resource.open requires resource")
        }
        let url = try SessionResource.url(for: reference)
        if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) {
            throw AgentSpaceError(code: .badRequest, message: "the file resource does not exist or is not accessible to this account")
        }
        guard NSWorkspace.shared.open(url) else {
            throw AgentSpaceError(code: .appNotFound, message: "no application accepted this resource in the agent session")
        }
        return .obj(["opened": .bool(true)])
    }

    func clipboardRead() throws -> JSONValue {
        try requireDesktopSession("read the agent clipboard")
        let text = NSPasteboard.general.string(forType: .string)
        if let text { try SessionResource.validateText(text) }
        return .obj(["text": text.map(JSONValue.string) ?? .null,
                     "hasText": .bool(text != nil)])
    }

    func clipboardWrite(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("write the agent clipboard")
        guard let text = params["text"]?.stringValue else {
            throw AgentSpaceError(code: .badRequest, message: "clipboard.write requires a text string (empty clears the text)")
        }
        try SessionResource.validateText(text)
        let board = NSPasteboard.general
        board.clearContents()
        if text.isEmpty {
            return .obj(["written": .bool(true), "bytes": .int(0)])
        }
        guard board.setString(text, forType: .string) else {
            throw AgentSpaceError(code: .internalError, message: "the agent clipboard could not accept text")
        }
        return .obj(["written": .bool(true), "bytes": .int(text.utf8.count)])
    }

    func axSetValue(params: JSONValue) throws -> JSONValue {
        try requireDesktopSession("set an accessibility value")
        try AccessibilityBridge.requireTrust()
        guard let pid = targetPid(params), let value = params["value"] else {
            throw AgentSpaceError(code: .badRequest, message: "ax.setValue requires value and a target application")
        }
        return try AccessibilityBridge.setValue(
            pid: pid, value: value, role: params["role"]?.stringValue,
            titleContains: params["titleContains"]?.stringValue,
            identifier: params["identifier"]?.stringValue)
    }
}
