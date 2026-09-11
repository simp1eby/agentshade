import AppKit
import CoreGraphics

public final class ShadeWindow: NSWindow, ShadeOverlay {
    private let onDismiss: () -> Void
    let scene: ShadeScene
    var animatesNextClose = false
    private var fadingOut = false

    public convenience init(screen: NSScreen, image: NSImage?, scene: ShadeScene = .black, onDismiss: @escaping () -> Void) {
        self.init(frame: screen.frame, image: image, scene: scene, onDismiss: onDismiss)
    }

    public init(frame: NSRect, image: NSImage?, scene: ShadeScene = .black, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.scene = scene
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        setFrame(frame, display: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = scene.isFrosted ? .clear : .black
        isOpaque = !scene.isFrosted
        isReleasedWhenClosed = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        contentView = ShadeContentView(
            frame: NSRect(origin: .zero, size: frame.size),
            image: image,
            scene: scene
        )
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    /// Passing nil releases captured pixels and restores the built-in background.
    public func setSnapshot(_ image: CGImage?) { (contentView as? ShadeContentView)?.setSnapshot(image) }

    func setRenderingPaused(_ paused: Bool) { (contentView as? ShadeContentView)?.setRenderingPaused(paused) }

    func present(animated: Bool) {
        // The content interpolates its actual frosting strength from clear.
        // A second window-opacity fade would delay and distort that same curve.
        alphaValue = 1
        orderFrontRegardless()
    }

    public func updateFrosting(appearance: FrostedAppearance, progress: Double, mode: FrostedPresentationMode = .lidAngle) {
        (contentView as? ShadeContentView)?.updateFrosting(appearance: appearance, progress: progress, mode: mode)
    }

    public override func close() {
        guard !fadingOut else { return }
        if animatesNextClose, scene.isFrosted, isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animatesNextClose = false
            fadingOut = true
            ignoresMouseEvents = true
            setRenderingPaused(true)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                animator().alphaValue = 0
            }, completionHandler: { [weak self] in self?.finishClosing() })
            return
        }
        finishClosing()
    }

    private func finishClosing() {
        fadingOut = false
        (contentView as? ShadeContentView)?.stopRendering()
        super.close()
    }

    public override func keyDown(with event: NSEvent) {
        DispatchQueue.main.async { [onDismiss] in
            onDismiss()
        }
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        DispatchQueue.main.async { [onDismiss] in
            onDismiss()
        }
        return true
    }
}
