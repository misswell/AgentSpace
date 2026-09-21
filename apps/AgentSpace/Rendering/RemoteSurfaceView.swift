import AppKit
import SwiftUI
import AgentSpaceCore

struct RemoteSurfaceView: NSViewRepresentable {
    let client: FrameClient
    var captureWidthLimit: Int = 0
    var captureMagnification: Double = 1
    var onMouseDown: ((Double, Double) -> Void)? = nil
    var onRightMouseDown: ((Double, Double) -> Void)? = nil

    func makeNSView(context: Context) -> RemoteSurfaceNSView {
        let view = RemoteSurfaceNSView(client: client)
        view.captureWidthLimit = captureWidthLimit; view.captureMagnification = captureMagnification
        view.onMouseDown = onMouseDown; view.onRightMouseDown = onRightMouseDown
        return view
    }

    func updateNSView(_ view: RemoteSurfaceNSView, context: Context) {
        view.captureWidthLimit = captureWidthLimit; view.captureMagnification = captureMagnification
        view.onMouseDown = onMouseDown; view.onRightMouseDown = onRightMouseDown
        view.needsLayout = true
    }
}

struct FrameClientStatusOverlay: View {
    @ObservedObject var client: FrameClient

    var body: some View {
        Group {
            switch client.streamNotice {
            case .unrecoverable:
                // Connections have failed the same way repeatedly, so a fourth
                // "reconnecting…" would be reporting the app's patience instead of
                // the picture's absence. This one names the step that can actually
                // change the answer.
                VStack(alignment: .leading, spacing: 5) {
                    Text("Frame stream unavailable").font(.headline)
                    Text("The shared picture could not be recovered. Reconnect, and if it keeps happening, update AgentSpace.").font(.caption)
                }
            case .resynchronising:
                // The protocol's own words for this — "logical mapping size
                // mismatch", "descriptor outside the region" — name a bookkeeping
                // disagreement between two binaries, which is not something a
                // person watching a desktop can repair. The sizes are in the unified
                // log; the window says what is being done about it.
                VStack(alignment: .leading, spacing: 5) {
                    Text("Frame stream is out of sync").font(.headline)
                    Text("AgentSpace is reconnecting the shared picture.").font(.caption)
                }
            case .none:
                if let error = client.lastError {
                    VStack(alignment: .leading, spacing: 5) {
                        if SharedFrameAllocation.classify(message: error.message) != nil {
                            // The syscall's own words belong in the log and in
                            // Diagnostics, which carry the full message. Over a
                            // desktop that is simply not appearing, what this viewer
                            // owes the person is the one thing they can still do.
                            //
                            // Read from the message because that is all that crosses
                            // the socket: a refusal is an ordinary internal error with
                            // this shape of text, and a structured field for it would
                            // make every older viewer fail to decode the error at all.
                            Text("Frame stream failed to start").font(.headline)
                            Text("Could not create the shared frame buffer. Reconnect; if it keeps happening, update AgentSpace.").font(.caption)
                        } else {
                            Text("Frame stream unavailable").font(.headline)
                            Text(error.message).font(.caption)
                        }
                    }
                } else if client.state == .connecting || client.state == .reconnecting {
                    Label(client.state == .connecting ? NSLocalizedString("Connecting frame stream…", comment: "") : NSLocalizedString("Reconnecting frame stream…", comment: ""),
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }
}

class RemoteSurfaceNSView: NSView {
    let client: FrameClient
    var onMouseDown: ((Double, Double) -> Void)?
    var onRightMouseDown: ((Double, Double) -> Void)?
    var captureWidthLimit = 0
    var captureMagnification = 1.0
    private let renderer: MetalSurfaceRenderer?
    private let cpuLayer = CALayer()
    private let cpuLock = NSLock()
    private var cpuPixels = Data()
    private var cpuWidth = 0
    private var cpuHeight = 0

    init(client: FrameClient) {
        self.client = client; self.renderer = MetalSurfaceRenderer()
        super.init(frame: .zero)
        wantsLayer = true
        if let metalLayer = renderer?.layer { layer = metalLayer }
        cpuLayer.contentsGravity = .resizeAspect
        cpuLayer.backgroundColor = NSColor.black.cgColor
        cpuLayer.isHidden = true
        layer?.addSublayer(cpuLayer)
        client.handleSharedFrame = { [weak self] mapping, _, _, slot, patches, presented in
            guard let self else { return .refused }
            let outcome = self.renderer?.apply(mapping: mapping, slot: slot, patches: patches, presented: presented) ?? .refused
            switch outcome {
            case .uploaded, .uploadedWithoutPresent:
                DispatchQueue.main.async { self.cpuLayer.isHidden = true }
                return outcome
            case .refused:
                // No Metal, or a texture this view could not build: the CPU layer is
                // the renderer now, and a frame it also refuses is the one case
                // where the viewer asks the worker for a baseline. The CPU path
                // reports no present timestamp — a stamped guess is worse than no
                // sample, because it is the flattering kind.
                return self.applyCPU(mapping: mapping, slot: slot, patches: patches) ? .uploaded : .refused
            }
        }
        client.handleVideoFrame = { [weak self] buffer in
            guard let self else { return }
            if self.renderer?.applyVideo(buffer) == true {
                DispatchQueue.main.async { self.cpuLayer.isHidden = true }
            } else {
                self.applyCPU(pixelBuffer: buffer)
            }
        }
        client.resetSurface = { [weak self] in
            self?.renderer?.clear()
            self?.cpuLayer.contents = nil
            self?.cpuLayer.isHidden = true
            self?.cpuLock.lock(); self?.cpuPixels.removeAll(keepingCapacity: false); self?.cpuWidth = 0; self?.cpuHeight = 0; self?.cpuLock.unlock()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        renderer?.resize(bounds.size, scale: scale)
        cpuLayer.frame = bounds
        let naturalWidth = max(1, Int(bounds.width * scale))
        let limitedWidth = captureWidthLimit > 0 ? min(naturalWidth, captureWidthLimit) : naturalWidth
        let targetWidth = max(1, Int(Double(limitedWidth) * captureMagnification))
        let targetHeight = max(1, Int(Double(targetWidth) * Double(bounds.height / max(1, bounds.width))))
        client.configure(width: targetWidth, height: targetHeight)
    }
    override func mouseDown(with event: NSEvent) {
        emit(event, to: onMouseDown)
    }
    override func rightMouseDown(with event: NSEvent) { emit(event, to: onRightMouseDown) }
    private func emit(_ event: NSEvent, to callback: ((Double, Double) -> Void)?) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        callback?(Double(point.x / bounds.width), Double(1 - point.y / bounds.height))
    }

    private func applyCPU(mapping: SharedFrameMapping, slot: SharedFrameSlotHeader, patches: [SharedPatchDescriptor]) -> Bool {
        let width = Int(slot.width), height = Int(slot.height), rowBytes = width * 4
        guard width > 0, height > 0 else { return false }
        cpuLock.lock(); defer { cpuLock.unlock() }
        if slot.frameKind == .fullBGRA || cpuWidth != width || cpuHeight != height {
            guard slot.frameKind == .fullBGRA else { return false }
            cpuPixels = Data(count: rowBytes * height); cpuWidth = width; cpuHeight = height
        }
        let copied = cpuPixels.withUnsafeMutableBytes { destination -> Bool in
            guard let base = destination.baseAddress else { return false }
            for patch in patches {
                let sourceOffset = Int(patch.payloadOffset)
                let patchRowBytes = Int(patch.bytesPerRow)
                guard sourceOffset >= 0,
                      sourceOffset + Int(patch.payloadLength) <= mapping.mappedCapacity,
                      Int(patch.x + patch.width) <= width,
                      Int(patch.y + patch.height) <= height else { return false }
                for row in 0..<Int(patch.height) {
                    memcpy(base.advanced(by: (Int(patch.y) + row) * rowBytes + Int(patch.x) * 4),
                           mapping.pointer.advanced(by: sourceOffset + row * patchRowBytes),
                           Int(patch.width) * 4)
                }
            }
            return true
        }
        guard copied else { return false }
        showCPU(pixels: cpuPixels, width: width, height: height, rowBytes: rowBytes)
        return true
    }

    private func applyCPU(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        let sourceRow = CVPixelBufferGetBytesPerRow(pixelBuffer), rowBytes = width * 4
        var pixels = Data(count: rowBytes * height)
        pixels.withUnsafeMutableBytes { destination in
            guard let output = destination.baseAddress else { return }
            for row in 0..<height { memcpy(output.advanced(by: row * rowBytes), base.advanced(by: row * sourceRow), rowBytes) }
        }
        cpuLock.lock(); cpuPixels = pixels; cpuWidth = width; cpuHeight = height; cpuLock.unlock()
        showCPU(pixels: pixels, width: width, height: height, rowBytes: rowBytes)
    }

    private func showCPU(pixels: Data, width: Int, height: Int, rowBytes: Int) {
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
        DispatchQueue.main.async { [weak self] in self?.cpuLayer.contents = image; self?.cpuLayer.isHidden = false }
    }
}
