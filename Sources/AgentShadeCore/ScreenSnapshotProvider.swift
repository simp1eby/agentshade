import Foundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// Call capture/cancel on the main thread. Cancellation (including a new capture)
/// suppresses the previous completion; all other completions run once on main.
public protocol ScreenSnapshotProviding: AnyObject {
    func capture(displayIDs: [CGDirectDisplayID], completion: @escaping ([CGDirectDisplayID: CGImage]) -> Void)
    func cancel()
}

/// Captures one complete frame per display, entirely in memory. Screen Recording
/// permission must already be granted: this provider never requests it.
public final class ScreenSnapshotProvider: ScreenSnapshotProviding {
    private let outputQueue = DispatchQueue(label: "io.github.simp1eby.agentshade.snapshots", qos: .userInitiated)
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var generation: UInt64 = 0
    private var request: SnapshotRequest?

    public init() {}

    deinit {
        let request = request
        if Thread.isMainThread {
            request?.cancel()
        } else {
            DispatchQueue.main.async { request?.cancel() }
        }
    }

    public func capture(displayIDs: [CGDirectDisplayID], completion: @escaping ([CGDirectDisplayID: CGImage]) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancel()
        guard !displayIDs.isEmpty, CGPreflightScreenCaptureAccess() else {
            completion([:])
            return
        }

        let currentGeneration = generation
        let request = SnapshotRequest(displayIDs: Set(displayIDs), outputQueue: outputQueue, imageContext: imageContext) { [weak self] images in
            guard let self, self.generation == currentGeneration else { return }
            self.request = nil
            completion(images)
        }
        self.request = request
        request.start()
    }

    public func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation &+= 1
        let previous = request
        request = nil
        previous?.cancel()
    }
}

/// Request bookkeeping is confined to main. Only image conversion uses outputQueue.
private final class SnapshotRequest {
    private let displayIDs: Set<CGDirectDisplayID>
    private let outputQueue: DispatchQueue
    private let imageContext: CIContext
    private var completion: (([CGDirectDisplayID: CGImage]) -> Void)?
    private var timeout: DispatchWorkItem?
    private var streams: [CGDirectDisplayID: SnapshotStream] = [:]
    private var pending: Set<CGDirectDisplayID> = []
    private var images: [CGDirectDisplayID: CGImage] = [:]
    private var finished = false

    init(displayIDs: Set<CGDirectDisplayID>, outputQueue: DispatchQueue, imageContext: CIContext,
         completion: @escaping ([CGDirectDisplayID: CGImage]) -> Void) {
        self.displayIDs = displayIDs
        self.outputQueue = outputQueue
        self.imageContext = imageContext
        self.completion = completion
    }

    func start() {
        // The deadline includes shareable-content enumeration, which can itself stall.
        let timeout = DispatchWorkItem { [weak self] in self?.finish() }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.finished else { return }
                guard error == nil, let content else {
                    self.finish()
                    return
                }
                self.startStreams(content: content)
            }
        }
    }

    func cancel() {
        guard !finished else { return }
        completion = nil
        finish()
    }

    private func startStreams(content: SCShareableContent) {
        let processID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == processID }
        // Without the application identity, later-created overlay windows cannot
        // safely be excluded. Keep the caller's native-material fallback instead.
        guard !ownApplications.isEmpty, CGPreflightScreenCaptureAccess() else {
            finish()
            return
        }
        let displays = content.displays.filter { displayIDs.contains($0.displayID) }
        pending = Set(displays.map(\.displayID))
        guard !pending.isEmpty else {
            finish()
            return
        }

        for display in displays {
            let displayID = display.displayID
            let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            let width = max(1, display.width)
            let height = max(1, display.height)
            let scale = min(1, 1920 / Double(max(width, height)))
            configuration.width = max(1, Int((Double(width) * scale).rounded(.down)))
            configuration.height = max(1, Int((Double(height) * scale).rounded(.down)))
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.colorSpaceName = CGColorSpace.sRGB
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
            configuration.queueDepth = 1
            configuration.showsCursor = false
            configuration.capturesAudio = false

            let stream = SnapshotStream(imageContext: imageContext) { [weak self] image in
                self?.receive(image, for: displayID)
            }
            streams[displayID] = stream
            stream.start(filter: filter, configuration: configuration, outputQueue: outputQueue)
        }
    }

    private func receive(_ image: CGImage?, for displayID: CGDirectDisplayID) {
        guard !finished, pending.remove(displayID) != nil else { return }
        streams.removeValue(forKey: displayID)?.stop()
        if let image { images[displayID] = image }
        if pending.isEmpty { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        timeout?.cancel()
        timeout = nil
        for stream in streams.values { stream.stop() }
        streams.removeAll()
        pending.removeAll()
        let result = images
        images.removeAll()
        let completion = completion
        self.completion = nil
        completion?(result)
    }
}

private final class SnapshotStream: NSObject, SCStreamOutput, SCStreamDelegate {
    private let imageContext: CIContext
    private let completion: (CGImage?) -> Void
    private var stream: SCStream?
    private var stopped = false
    private var delivered = false

    // Output/delegate callbacks may race main-thread cancellation. Claiming a frame
    // consumes the gate before rendering, so only one pixel buffer is ever converted.
    private let frameLock = NSLock()
    private var acceptsFrame = true

    init(imageContext: CIContext, completion: @escaping (CGImage?) -> Void) {
        self.imageContext = imageContext
        self.completion = completion
    }

    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, outputQueue: DispatchQueue) {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        } catch {
            deliver(nil)
            return
        }

        stream.startCapture { [weak self, stream] error in
            DispatchQueue.main.async { [weak self, stream] in
                guard let self, !self.stopped else {
                    // stopCapture can fail while startCapture is still pending.
                    // Always stop again after that late start completes, even when
                    // cancellation has already released the request and receiver.
                    Self.stopCapture(stream)
                    return
                }
                if error != nil, self.claimFrame() { self.deliver(nil) }
            }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        frameLock.lock()
        acceptsFrame = false
        frameLock.unlock()
        guard let stream else { return }
        self.stream = nil
        Self.stopCapture(stream)
    }

    private static func stopCapture(_ stream: SCStream) {
        // Retain the stream until its asynchronous stop is acknowledged. The
        // receiver has already dropped its stream reference, avoiding a cycle.
        stream.stopCapture { [stream] _ in withExtendedLifetime(stream) {} }
    }

    private func claimFrame() -> Bool {
        frameLock.lock()
        defer { frameLock.unlock() }
        guard acceptsFrame else { return false }
        acceptsFrame = false
        return true
    }

    private func deliver(_ image: CGImage?) {
        guard !stopped, !delivered else { return }
        delivered = true
        completion(image)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              claimFrame() else { return }

        let image: CGImage? = autoreleasepool {
            let source = CIImage(cvPixelBuffer: pixelBuffer)
            // Eager rendering detaches the image from the capture IOSurface. No
            // CMSampleBuffer, CVPixelBuffer, or lazy CIImage leaves this callback.
            return imageContext.createCGImage(source, from: source.extent, format: .BGRA8,
                                              colorSpace: CGColorSpace(name: CGColorSpace.sRGB), deferred: false)
        }
        DispatchQueue.main.async { [weak self] in self?.deliver(image) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard claimFrame() else { return }
        DispatchQueue.main.async { [weak self] in self?.deliver(nil) }
    }
}
