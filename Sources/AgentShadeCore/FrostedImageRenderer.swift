import AppKit
import CoreImage

/// Manual frosting is an opaque privacy material; lid frosting fades in from clear.
public enum FrostedPresentationMode { case manual, lidAngle }

/// Keeps a cold first frame near the moving target without blocking later frames.
enum FrostedFirstFramePolicy {
    static func shouldWait(renderedProgress: Double, currentProgress: Double, elapsed: TimeInterval) -> Bool {
        elapsed < 0.25 && abs(renderedProgress - currentProgress) > 0.08
    }
}

public struct FrostedAppearance: Equatable {
    public static let defaultBlurRadius = 20.0
    public let blurRadius: Double
    public let tintOpacity: Double
    public let stretchAmount: Double

    public init(blurRadius: Double = FrostedAppearance.defaultBlurRadius, tintOpacity: Double = 0.12, stretchAmount: Double = 0) {
        self.blurRadius = blurRadius.isFinite ? min(60, max(0, blurRadius)) : Self.defaultBlurRadius
        self.tintOpacity = tintOpacity.isFinite ? min(0.45, max(0, tintOpacity)) : 0.12
        // Keep source compatibility for older integrations; deformation is gone.
        self.stretchAmount = 0
    }

    public static func progress(angle: Double, triggerAngle: Double) -> Double {
        guard angle.isFinite, triggerAngle.isFinite else { return 1 }
        let range = ShadePreferences.angleRange
        let threshold = min(range.upperBound, max(range.lowerBound, triggerAngle))
        let fullAngle = ShadePreferences.fullFrostAngle
        guard angle < threshold else { return 0 }
        guard angle > fullAngle else { return 1 }
        // Normalize to the configured travel, then reach 65% coverage at 30%.
        // A single smooth rational curve avoids a slope change at that milestone
        // and continues deepening all the way to the 40-degree endpoint.
        let distance = (threshold - angle) / (threshold - fullAngle)
        return 13 * distance / (3 + 10 * distance)
    }
}

/// A reusable renderer. Captures stay in memory; a caller serializes render requests.
public final class FrostedImageRenderer {
    // Share the expensive Metal context across windows and settings previews.
    // The context is first touched on the render queue during preparation, so a
    // newly created overlay does not initialize GPU resources on the main thread.
    private static let context = CIContext(options: [.cacheIntermediates: false])
    static let renderQueue = DispatchQueue(label: "AgentShade.frosted-render", qos: .userInitiated)
    private static let preparation: Void = {
        renderQueue.async {
            guard let bitmap = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 256,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
            bitmap.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            bitmap.setFillColor(CGColor(gray: 0, alpha: 1))
            bitmap.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
            guard let image = bitmap.makeImage() else { return }
            _ = FrostedImageRenderer().render(source: image, scene: .frostedDark, appearance: FrostedAppearance(), progress: 0.5)
        }
    }()

    public init() {}

    static func prepare() { _ = preparation }

    public func render(source: CGImage, scene: ShadeScene, appearance: FrostedAppearance, progress: Double) -> CGImage? {
        let amount = progress.isFinite ? min(1, max(0, progress)) : 1
        guard amount > 0, appearance.blurRadius > 0 || appearance.tintOpacity > 0 else { return source }
        let input = CIImage(cgImage: source)
        let extent = input.extent
        // Clamp before blur and crop afterward to preserve opaque display edges.
        var output = input.clampedToExtent()
        // A 960-point example and its 1920-pixel capture must have the same
        // relative detail loss. The stronger midrange also obscures small text.
        let sourceScale = Double(max(source.width, source.height)) / 960
        output = output.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: appearance.blurRadius * amount * 2 * sourceScale])
            .cropped(to: extent)
        // Share the shortcut artwork's palette. Its coverage follows the same
        // gentle angle progress, so the start stays clear and desktop structure
        // remains visible beneath the blue material at later angles.
        if let artwork = FrostedMaterial.artwork {
            let frame = AspectFillGeometry.frame(imageSize: CGSize(width: artwork.width, height: artwork.height), in: extent)
            let scale = frame.width / CGFloat(artwork.width)
            let material = CIImage(cgImage: artwork)
                .transformed(by: CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: frame.minX, ty: frame.minY))
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.7 * amount)])
            output = material.cropped(to: extent).composited(over: output)
        }
        let depth = CIImage(color: CIColor(red: 0, green: 0, blue: 0,
                                          alpha: FrostedMaterial.depth(appearance: appearance, progress: amount)))
        output = depth.cropped(to: extent).composited(over: output)
        return Self.context.createCGImage(output, from: extent, format: .BGRA8,
                                          colorSpace: CGColorSpace(name: CGColorSpace.sRGB), deferred: false)
    }
}

/// One immutable blue palette for manual artwork, lid snapshots and previews.
enum FrostedMaterial {
    static func depth(appearance: FrostedAppearance, progress: Double) -> Double {
        (0.34 + appearance.tintOpacity * 0.4) * progress
    }
    static let artwork: CGImage? = {
        let width = 384, height = 256
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(red: 0.10, green: 0.20, blue: 0.38, alpha: 1),
                      CGColor(red: 0.29, green: 0.48, blue: 0.67, alpha: 1),
                      CGColor(red: 0.44, green: 0.69, blue: 0.73, alpha: 1)]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.6, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        let glow = [CGColor(red: 0.57, green: 0.40, blue: 0.83, alpha: 0.5), CGColor(red: 0.57, green: 0.40, blue: 0.83, alpha: 0)]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glow as CFArray, locations: [0, 1]) {
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: 85, y: 180), startRadius: 0,
                                       endCenter: CGPoint(x: 85, y: 180), endRadius: 210, options: [])
        }
        return context.makeImage()
    }()
}

/// Permission-free path: angle changes update opacity without rendering frames.
final class BuiltInFrostedView: NSView {
    private let imageView = NSImageView(frame: .zero)
    private let tintView = NSView(frame: .zero)
    private static let artwork: NSImage = {
        guard let image = FrostedMaterial.artwork else { return NSImage() }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        imageView.frame = bounds
        imageView.image = Self.artwork
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.alphaValue = 0
        imageView.identifier = NSUserInterfaceItemIdentifier("builtin-frosted-image")
        addSubview(imageView)
        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        tintView.wantsLayer = true
        tintView.identifier = NSUserInterfaceItemIdentifier("builtin-frosted-tint")
        addSubview(tintView)
    }
    override func layout() {
        super.layout()
        if let image = imageView.image { imageView.frame = AspectFillGeometry.frame(imageSize: image.size, in: bounds) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(appearance: FrostedAppearance, progress: Double, mode: FrostedPresentationMode = .lidAngle) {
        let amount = progress.isFinite ? min(1, max(0, progress)) : 1
        imageView.alphaValue = mode == .manual ? 1 : amount
        // Strength changes the depth of the material throughout the full range.
        // Lid mode alone changes coverage, preserving a completely clear start.
        tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(FrostedMaterial.depth(appearance: appearance, progress: amount)).cgColor
    }
}

/// At most one GPU render is in flight per view. New sensor values replace pending
/// work, preventing a slow GPU from accumulating old lid-angle frames.
final class FrostedImageView: NSView {
    private let renderer = FrostedImageRenderer()
    private var source: CGImage?
    private var scene: ShadeScene = .frostedDark
    private var frostAppearance = FrostedAppearance()
    private var presentationMode: FrostedPresentationMode = .lidAngle
    private var progress: Double = 0
    private var generation = 0
    private var rendering = false
    private var closed = false
    private var paused = false
    private var smoother = FrostedProgressSmoother(value: 0)
    private var animationTimer: Timer?
    private var lastFrameTime: TimeInterval = 0
    private var sourceRevision = 0
    private var pendingSourceTransition = false
    private var firstFrameRequestedAt: TimeInterval = 0
    var onFirstFrame: (() -> Void)?
    var onFrameRendered: ((Bool) -> Void)?
    var onProgress: ((Double) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { animationTimer?.invalidate() }

    func setSource(_ image: CGImage?) {
        firstFrameRequestedAt = ProcessInfo.processInfo.systemUptime
        sourceRevision += 1
        pendingSourceTransition = layer?.contents != nil
        source = image
        closed = false
        generation += 1
        guard image != nil else {
            layer?.contents = nil
            pendingSourceTransition = false
            return
        }
        FrostedImageRenderer.prepare()
        renderLatest()
    }

    func update(scene: ShadeScene, appearance: FrostedAppearance, progress: Double, mode: FrostedPresentationMode = .lidAngle) {
        let progress = progress.isFinite ? min(1, max(0, progress)) : 1
        let entersManual = mode == .manual && presentationMode != .manual
        presentationMode = mode
        guard entersManual || scene != self.scene || appearance != self.frostAppearance || abs(progress - smoother.target) > 0.002 else {
            onProgress?(self.progress)
            return
        }
        self.scene = scene; self.frostAppearance = appearance
        // A manual cover starts at its requested strength. Its first captured
        // image must never be a clear screenshot while the opaque material waits.
        if entersManual || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            smoother = FrostedProgressSmoother(value: progress)
            self.progress = smoother.value
        } else {
            smoother.retarget(progress)
            startAnimationIfNeeded()
        }
        onProgress?(self.progress)
        generation += 1
        renderLatest()
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        if paused {
            animationTimer?.invalidate()
            animationTimer = nil
        } else {
            startAnimationIfNeeded()
            renderLatest()
        }
    }

    private func startAnimationIfNeeded() {
        guard !closed, !paused, smoother.needsFrames, animationTimer == nil else { return }
        lastFrameTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.smoother.advance(by: now - self.lastFrameTime)
            self.lastFrameTime = now
            self.progress = self.smoother.value
            self.onProgress?(self.progress)
            self.generation += 1
            self.renderLatest()
            if !self.smoother.needsFrames {
                self.animationTimer?.invalidate()
                self.animationTimer = nil
            }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        closed = true
        animationTimer?.invalidate()
        animationTimer = nil
        sourceRevision += 1
        generation += 1
        source = nil
        layer?.contents = nil
        onFirstFrame = nil
        onFrameRendered = nil
        onProgress = nil
    }

    private func renderLatest() {
        guard !closed, !paused, !rendering, let source else { return }
        rendering = true
        let version = generation, scene = scene, appearance = frostAppearance, progress = progress
        let revision = sourceRevision
        FrostedImageRenderer.renderQueue.async { [weak self, renderer] in
            let image = renderer.render(source: source, scene: scene, appearance: appearance, progress: progress)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.rendering = false
                guard !self.closed, !self.paused else { return }
                // Show a completed recent frame even while the lid moves; otherwise
                // a slower render could starve the display until movement stops.
                // During the initial handoff, a cold/queued frame may represent an
                // earlier angle. Keep the responsive built-in artwork until a frame
                // is close enough. After 250ms, abandon a still-stale source instead
                // of flashing it over the material. A new source starts a fresh try.
                // Once visible, recent frames remain eligible during continuous movement.
                let isFirstFrame = self.layer?.contents == nil && self.onFirstFrame != nil
                let firstFrameElapsed = ProcessInfo.processInfo.systemUptime - self.firstFrameRequestedAt
                if revision == self.sourceRevision, isFirstFrame, firstFrameElapsed >= 0.25,
                   abs(progress - self.progress) > 0.08 {
                    self.source = nil
                    self.pendingSourceTransition = false
                    self.onFirstFrame = nil
                    return
                }
                let firstFrameTooOld = isFirstFrame
                    && FrostedFirstFramePolicy.shouldWait(renderedProgress: progress, currentProgress: self.progress,
                                                        elapsed: firstFrameElapsed)
                if let image, revision == self.sourceRevision, !firstFrameTooOld {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    if self.pendingSourceTransition && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        let fade = CATransition()
                        fade.type = .fade
                        fade.duration = 0.22
                        self.layer?.add(fade, forKey: "snapshot-refresh")
                    }
                    self.pendingSourceTransition = false
                    self.layer?.contents = image
                    CATransaction.commit()
                    self.onFrameRendered?(true)
                    self.onFirstFrame?()
                    self.onFirstFrame = nil
                } else if image == nil, revision == self.sourceRevision {
                    self.onFrameRendered?(false)
                }
                if version != self.generation { self.renderLatest() }
            }
        }
    }
}

/// An app-owned example scene, never a screenshot of the user's desktop.
public final class FrostedPreviewView: NSView {
    private let backdropView = NSImageView(frame: .zero)
    private let imageView = FrostedImageView(frame: .zero)
    private let fallbackView = BuiltInFrostedView(frame: .zero)
    private var language: AppLanguage = .english
    private var usesSnapshot = false
    private var frostAppearance = FrostedAppearance()
    private var presentationMode: FrostedPresentationMode = .lidAngle
    private var exampleSource: CGImage?
    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        backdropView.frame = bounds
        backdropView.imageScaling = .scaleProportionallyUpOrDown
        backdropView.identifier = NSUserInterfaceItemIdentifier("frosted-example-desktop")
        exampleSource = Self.makeExampleImage(language: language)
        if let exampleSource { backdropView.image = NSImage(cgImage: exampleSource, size: .zero) }
        addSubview(backdropView)
        fallbackView.frame = bounds
        fallbackView.autoresizingMask = [.width, .height]
        addSubview(fallbackView)
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        imageView.isHidden = true
        imageView.onProgress = { [weak self] progress in
            guard let self else { return }
            self.fallbackView.update(appearance: self.frostAppearance, progress: progress, mode: self.presentationMode)
        }
        imageView.onFrameRendered = { [weak self] succeeded in
            guard let self, self.usesSnapshot else { return }
            // Never leave a stale clear example exposed after a failed render.
            // The fallback already follows the current smoothed progress.
            self.imageView.isHidden = !succeeded
            self.fallbackView.isHidden = succeeded
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    public override func layout() {
        super.layout()
        if let image = backdropView.image { backdropView.frame = AspectFillGeometry.frame(imageSize: image.size, in: bounds) }
    }
    public func update(scene: ShadeScene, appearance: FrostedAppearance, progress: Double, usesSnapshot: Bool = true, mode: FrostedPresentationMode = .lidAngle) {
        self.frostAppearance = appearance
        presentationMode = mode
        // Set the intended strength before assigning a source, exactly as the
        // controller does for an overlay. Otherwise manual preview starts clear.
        imageView.update(scene: scene, appearance: appearance, progress: progress, mode: mode)
        if self.usesSnapshot != usesSnapshot {
            self.usesSnapshot = usesSnapshot
            imageView.isHidden = true
            fallbackView.isHidden = false
            imageView.setSource(usesSnapshot ? exampleSource : nil)
        }
    }

    public func updateLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        exampleSource = Self.makeExampleImage(language: language)
        if let exampleSource { backdropView.image = NSImage(cgImage: exampleSource, size: .zero) }
        if usesSnapshot { imageView.setSource(exampleSource) }
    }

    public static func makeExampleImage(language: AppLanguage = .english) -> CGImage? {
        let size = NSSize(width: 960, height: 720)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.60, alpha: 1),
                            NSColor(calibratedRed: 0.55, green: 0.61, blue: 0.80, alpha: 1),
                            NSColor(calibratedRed: 0.87, green: 0.68, blue: 0.63, alpha: 1)])!
            .draw(in: NSRect(origin: .zero, size: size), angle: -35)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(ovalIn: NSRect(x: 440, y: 180, width: 650, height: 620)).fill()
        NSColor(calibratedRed: 0.065, green: 0.095, blue: 0.17, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: NSRect(x: 86, y: 195, width: 595, height: 385), xRadius: 22, yRadius: 22).fill()
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill(); NSBezierPath(ovalIn: NSRect(x: 111 + index * 23, y: 549, width: 11, height: 11)).fill()
        }
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.white]
        (language.text("Agent 工作区", "Agent workspace") as NSString).draw(at: NSPoint(x: 119, y: 499), withAttributes: title)
        for row in 0..<8 {
            (row % 3 == 0 ? NSColor.systemTeal : NSColor.white.withAlphaComponent(0.32)).setFill()
            NSBezierPath(roundedRect: NSRect(x: 120 + (row % 3) * 18, y: 466 - row * 29, width: [305, 410, 230, 365][row % 4], height: 8), xRadius: 4, yRadius: 4).fill()
        }
        NSColor.white.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: NSRect(x: 555, y: 106, width: 320, height: 230), xRadius: 24, yRadius: 24).fill()
        (language.text("后台运行中", "IN THE BACKGROUND") as NSString).draw(at: NSPoint(x: 584, y: 286), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.gray])
        (language.text("Agent 正在工作。", "Your agent is working.") as NSString).draw(at: NSPoint(x: 584, y: 239), withAttributes: [.font: NSFont.systemFont(ofSize: 21, weight: .semibold), .foregroundColor: NSColor.darkGray])
        NSColor.systemTeal.setFill()
        NSBezierPath(roundedRect: NSRect(x: 585, y: 189, width: 235, height: 9), xRadius: 4, yRadius: 4).fill()
        (language.text("保护一点隐私，不打断工作。", "A little privacy. No interruption.") as NSString).draw(at: NSPoint(x: 584, y: 143), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.gray])
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
