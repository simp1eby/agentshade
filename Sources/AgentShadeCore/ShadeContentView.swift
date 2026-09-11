import AppKit

final class ShadeContentView: NSView {
    private let imageView = NSImageView(frame: .zero)
    private var fallbackView: BuiltInFrostedView?
    private var frostView: FrostedImageView?
    private let scene: ShadeScene
    private var frostAppearance = FrostedAppearance()
    private var presentationMode: FrostedPresentationMode = .lidAngle
    private var stopped = false
    private var snapshotGeneration = 0

    init(frame frameRect: NSRect, image: NSImage?, scene: ShadeScene = .black) {
        self.scene = scene
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = (scene.isFrosted ? NSColor.clear : NSColor.black).cgColor
        layer?.masksToBounds = true

        if scene.isFrosted {
            let fallback = BuiltInFrostedView(frame: bounds)
            fallback.autoresizingMask = [.width, .height]
            addSubview(fallback)
            fallbackView = fallback
            let frost = FrostedImageView(frame: bounds)
            frost.autoresizingMask = [.width, .height]
            frost.alphaValue = 0
            frost.onProgress = { [weak self] progress in
                guard let self, !self.stopped else { return }
                self.fallbackView?.update(appearance: self.frostAppearance, progress: progress, mode: self.presentationMode)
            }
            addSubview(frost)
            frostView = frost
            return
        }

        imageView.imageFrameStyle = .none
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = true
        imageView.image = image
        imageView.isHidden = image == nil
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    func setSnapshot(_ image: CGImage?) {
        guard !stopped, let frostView else { return }
        snapshotGeneration += 1
        let generation = snapshotGeneration
        guard let image else {
            frostView.onFirstFrame = nil
            frostView.setSource(nil)
            frostView.layer?.removeAllAnimations()
            frostView.alphaValue = 0
            fallbackView?.isHidden = false
            return
        }
        frostView.onFirstFrame = { [weak self] in
            guard let self, !self.stopped, self.snapshotGeneration == generation else { return }
            // Keep the app-owned background until an enhanced frame covers it.
            // A later failed capture invalidates both this callback and its fade.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
                self.frostView?.animator().alphaValue = 1
            }, completionHandler: { [weak self] in
                guard let self, !self.stopped, self.snapshotGeneration == generation else { return }
                self.fallbackView?.isHidden = true
            })
        }
        frostView.setSource(image)
    }

    func updateFrosting(appearance: FrostedAppearance, progress: Double, mode: FrostedPresentationMode = .lidAngle) {
        frostAppearance = appearance
        presentationMode = mode
        frostView?.update(scene: scene, appearance: appearance, progress: progress, mode: mode)
    }

    func setRenderingPaused(_ paused: Bool) { frostView?.setPaused(paused) }

    func stopRendering() {
        stopped = true
        frostView?.stop()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func layout() {
        super.layout()
        guard let image = imageView.image else {
            imageView.frame = bounds
            return
        }
        imageView.frame = AspectFillGeometry.frame(imageSize: image.size, in: bounds)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
}
