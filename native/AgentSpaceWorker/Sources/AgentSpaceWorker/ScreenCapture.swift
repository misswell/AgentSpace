import Foundation
import CoreGraphics
import ImageIO
import AgentSpaceCore

/// Screenshot capture for the MVP. Plan §15.
///
/// Uses `/usr/sbin/screencapture`, which is the boring, correct choice *because
/// the worker already lives in the target session*: the command captures that
/// session's framebuffer, so there is no cross-session capture problem to solve.
/// ScreenCaptureKit arrives in phase 2 for live preview (§16), not to replace
/// this.
enum ScreenCapture {

    struct Result {
        var path: String
        /// Dimensions of the PNG that was actually written (and downscaled).
        var width: Int
        var height: Int
        /// Dimensions of the full framebuffer before any downscale.
        var pixelWidth: Int
        var pixelHeight: Int
        var scale: Int

        var json: JSONValue {
            .obj([
                "path": .string(path),
                "width": .int(width),
                "height": .int(height),
                "pixelWidth": .int(pixelWidth),
                "pixelHeight": .int(pixelHeight),
                "scale": .int(scale),
            ])
        }
    }

    /// Main display geometry in points and pixels.
    ///
    /// `pixelWidth` comes from `CGDisplayCopyDisplayMode()`, **not** from
    /// `CGDisplayPixelsWide()`. Measured on macOS 27.0 with a scaled Retina
    /// display: `CGDisplayPixelsWide()` returned 1920 (points) while the mode's
    /// `pixelWidth` returned 3840. Deriving the scale from the former yields 1
    /// and quietly halves every coordinate an agent computes.
    static func mainDisplayGeometry() -> DisplayGeometry {
        let displayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayID)
        let mode = CGDisplayCopyDisplayMode(displayID)
        return DisplayGeometry(
            modeWidth: mode?.width ?? Int(bounds.width),
            modePixelWidth: mode?.pixelWidth ?? Int(bounds.width),
            boundsWidth: Int(bounds.width.rounded()),
            boundsHeight: Int(bounds.height.rounded()))
    }

    static func permissionGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Capture to `destination`. Caller must have checked permission first.
    static func capture(
        to destination: String,
        maxWidth: Int? = nil,
        display: Int? = nil,
        timeout: Int = 20
    ) throws -> Result {
        // Check first and refuse without invoking `screencapture`: running it
        // without the grant can raise a TCC prompt in a session nobody is
        // looking at, producing a dialog that can never be answered.
        guard permissionGranted() else {
            throw AgentSpaceError(
                code: .screenRecordingDenied,
                message: "Screen Recording is not granted to agentspace-worker in this session. Preflight said no, so `screencapture` was not run.")
        }

        let fm = FileManager.default
        let directory = (destination as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        try? fm.removeItem(atPath: destination)

        var arguments = ["-x", "-t", "png"]
        if let display {
            // `-D` is 1-based; the protocol's `display` is 1-based too, which is
            // what a human means by "display 2".
            guard display >= 1 else {
                throw AgentSpaceError(
                    code: .badRequest,
                    message: "display must be 1 or greater (1 is the main display), got \(display)")
            }
            arguments.append(contentsOf: ["-D", String(display)])
        }
        arguments.append(destination)

        let status = try runProcess("/usr/sbin/screencapture", arguments, timeout: timeout)
        guard status == 0 else {
            throw AgentSpaceError(
                code: .internalError,
                message: "screencapture exited \(status). It returns non-zero when the session has no capturable display.")
        }
        guard fm.fileExists(atPath: destination) else {
            throw AgentSpaceError(
                code: .internalError,
                message: "screencapture reported success but wrote no file at \(destination)")
        }

        let geometry = mainDisplayGeometry()
        var width = geometry.pixelWidth
        var height = geometry.pixelHeight
        if let header = pngHeader(path: destination) {
            width = header.width
            height = header.height
        }

        if let maxWidth, maxWidth > 0, width > maxWidth {
            // `sips --resampleHeightWidthMax` preserves aspect ratio.
            _ = try? runProcess(
                "/usr/bin/sips",
                ["--resampleHeightWidthMax", String(maxWidth), destination],
                timeout: timeout)
            if let header = pngHeader(path: destination) {
                width = header.width
                height = header.height
            }
        }

        Log.capture.debug("screenshot \(width)x\(height) (framebuffer \(geometry.pixelWidth)x\(geometry.pixelHeight), scale \(geometry.scale))")
        return Result(
            path: destination,
            width: width,
            height: height,
            pixelWidth: geometry.pixelWidth,
            pixelHeight: geometry.pixelHeight,
            scale: geometry.scale)
    }

    /// Read width/height straight out of the PNG IHDR. Cheaper and more honest
    /// than trusting what we asked for: it describes the file that exists.
    static func pngHeader(path: String) -> (width: Int, height: Int)? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 24), data.count >= 24 else { return nil }
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard Array(data.prefix(8)) == signature else { return nil }
        // 8 signature + 4 length + 4 "IHDR" = 16, then width and height as
        // big-endian UInt32.
        func be32(_ offset: Int) -> Int {
            let b = [UInt8](data[offset..<(offset + 4)])
            return (Int(b[0]) << 24) | (Int(b[1]) << 16) | (Int(b[2]) << 8) | Int(b[3])
        }
        return (be32(16), be32(20))
    }

    /// Run a fixed-path tool with no shell. Returns the exit status.
    @discardableResult
    static func runProcess(_ path: String, _ arguments: [String], timeout: Int) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AgentSpaceError(
                code: .internalError,
                message: "could not run \(path): \(error.localizedDescription)")
        }
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            usleep(200_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw AgentSpaceError(
                code: .commandTimeout,
                message: "\(path) did not finish within \(timeout)s")
        }
        return process.terminationStatus
    }
}
