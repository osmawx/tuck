import AppKit
import CoreImage
import ScreenCaptureKit

/// Retains window streams started while icons are visible, instead of restarting capture off screen.
@MainActor
enum MenuBarLiveCapture {
    private struct Entry {
        let windowID: CGWindowID
        let token: UUID
        let session: MenuBarLiveCaptureSession
        var frameCount = 0
    }
    private static var sessions: [String: Entry] = [:]
    private static var lastFailureCodes: [String: Int] = [:]

    /// Reports whether a source window already has a running capture session.
    static func isRunning(itemID: String, windowID: CGWindowID?) -> Bool {
        guard let entry = sessions[itemID] else { return false }
        return windowID == nil || entry.windowID == windowID
    }

    /// Starts once while the window is rendered and forwards subsequent frames to the icon cache.
    static func start(item: MenuBarItem, window: SCWindow, onImage: @escaping (NSImage) -> Void) async -> Bool {
        if isRunning(itemID: item.id, windowID: window.windowID) { return true }
        if let previous = sessions.removeValue(forKey: item.id) {
            await previous.session.stop()
        }
        let token = UUID()
        let itemID = item.id
        let pointSize = window.frame.size
        let session = MenuBarLiveCaptureSession(onImage: { image in
            Task { @MainActor in
                guard sessions[itemID]?.token == token else { return }
                sessions[itemID]?.frameCount += 1
                let frameCount = sessions[itemID]?.frameCount ?? 0
                if frameCount == 1 || frameCount % 10 == 0 {
                    MenuDiagnostics.record("live icon frames received: \(itemID), count=\(frameCount)")
                }
                onImage(NSImage(cgImage: image, size: pointSize))
            }
        }, onStop: { errorCode in
            Task { @MainActor in
                guard sessions[itemID]?.token == token else { return }
                let stoppedSession = sessions.removeValue(forKey: itemID)?.session
                await stoppedSession?.stop()
                MenuDiagnostics.record("live icon stream stopped: \(itemID), code=\(errorCode)")
            }
        })
        sessions[itemID] = Entry(windowID: window.windowID, token: token, session: session)
        do {
            try await session.start(window: window)
            guard sessions[itemID]?.token == token else {
                await session.stop()
                return false
            }
            lastFailureCodes.removeValue(forKey: itemID)
            MenuDiagnostics.record("live icon stream started: \(itemID)")
            return true
        } catch {
            if sessions[itemID]?.token == token { sessions.removeValue(forKey: itemID) }
            await session.stop()
            let errorCode = (error as NSError).code
            if lastFailureCodes[itemID] != errorCode {
                lastFailureCodes[itemID] = errorCode
                MenuDiagnostics.record("live icon stream failed: \(itemID), code=\(errorCode)")
            }
            return false
        }
    }

    /// Stops recording when neither the layout window nor the hidden icon panel needs frames.
    static func stopAll() {
        let previousSessions = sessions.values.map(\.session)
        sessions.removeAll()
        Task {
            for session in previousSessions { await session.stop() }
        }
    }
}

/// Converts complete screen frames on a serial queue without blocking menu interaction.
private final class MenuBarLiveCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    private static let OUTPUT_QUEUE = DispatchQueue(label: "com.local.hider.icon-frames", qos: .utility)
    private let onImage: (CGImage) -> Void
    private let onStop: (Int) -> Void
    @MainActor private var stream: SCStream?

    /// Stores callbacks; frames remain local and are never written to disk.
    init(onImage: @escaping (CGImage) -> Void, onStop: @escaping (Int) -> Void) {
        self.onImage = onImage
        self.onStop = onStop
    }

    /// Starts a small window-only stream before its status item moves off screen.
    @MainActor
    func start(window: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = max(1, CGFloat(filter.pointPixelScale))
        configuration.width = max(2, Int(window.frame.width * scale))
        configuration.height = max(2, Int(window.frame.height * scale))
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 600)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.shouldBeOpaque = false
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: Self.OUTPUT_QUEUE)
        try await stream.startCapture()
        // Closing the last UI can cancel startup while ScreenCaptureKit is still awaiting its source.
        if self.stream !== stream {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .screen)
        }
    }

    /// Releases the stream after the last consumer closes or the source window changes.
    @MainActor
    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .screen)
    }

    /// Accepts new complete frames, discarding idle and blank WindowServer surfaces.
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let image = MenuBarLiveFrame.image(from: sampleBuffer) else { return }
        onImage(image)
    }

    /// Lets the owner retry a failed stream without retaining a dead session.
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop((error as NSError).code)
    }
}

/// Converts fresh stream frames without reusing a previous snapshot.
enum MenuBarLiveFrame {
    private static let IMAGE_CONTEXT = CIContext(options: [.cacheIntermediates: false])

    /// Ignores idle frames and validates every newly delivered image independently.
    static func image(from sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard CMSampleBufferIsValid(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let source = CIImage(cvPixelBuffer: buffer)
        guard let image = Self.IMAGE_CONTEXT.createCGImage(source, from: source.extent),
              MenuBarImageValidation.isUsable(image) else { return nil }
        return image
    }
}
